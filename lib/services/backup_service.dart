import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../state/app_settings.dart';
import '../state/library_state.dart';
import 'download_service.dart';

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  bool _isRestoring = false;
  Timer? _debounceTimer;

  void backupAllDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 5), () {
      backupAll();
    });
  }

  Future<String> get _defaultBackupDirPath async {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Download/watchAny/.backup';
    } else {
      final homeDir = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;
      return '$homeDir/Downloads/watchAny/.backup';
    }
  }

  // Helper to resolve the active backup directory (uses custom download path if set, otherwise default)
  Future<String> getBackupDirPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customPath = prefs.getString('download_path') ?? '';
      if (customPath.isNotEmpty) {
        return '$customPath/.backup';
      }
    } catch (_) {}
    return _defaultBackupDirPath;
  }

  // Backup settings, library, and downloads to external files
  Future<void> backupAll() async {
    if (_isRestoring) return; // Prevent loop during restore
    try {
      final path = await getBackupDirPath();
      final dir = Directory(path);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      final prefs = await SharedPreferences.getInstance();

      // 1. Backup Library Items (serialize from memory, which is in sync with SQLite)
      final libraryState = LibraryState();
      final items = libraryState.items;
      final categories = libraryState.categories;
      final mangaCache = libraryState.mangaCache;

      if (items.isNotEmpty || categories.isNotEmpty || mangaCache.isNotEmpty) {
        final ts = DateTime.now().toIso8601String();
        final libraryBackup = {
          'library_items': items.map((item) => item.toJson()).toList(),
          'library_categories': categories.map((cat) => cat.toJson()).toList(),
          'manga_library_cache': mangaCache.map((key, value) => MapEntry(key.toString(), value)),
          'timestamp': ts,
        };
        final libraryFile = File('${dir.path}/library_backup.json');
        await libraryFile.writeAsString(jsonEncode(libraryBackup));
      }

      // 2. Backup App Settings — exclude large cache blobs (anime/movie caches, notif state)
      // These were being written into settings_backup.json = tens of MB every 5 seconds.
      const cacheKeys = {
        'library_items', 'library_categories',
        'manga_library_cache', 'anime_library_cache', 'movie_library_cache',
        'notif_ack_all', 'notif_start_all', 'library_last_notif_sync',
        'downloads_backup',
      };
      final settingsBackup = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (!cacheKeys.contains(key)) {
          settingsBackup[key] = prefs.get(key);
        }
      }
      if (settingsBackup.isNotEmpty) {
        final settingsFile = File('${dir.path}/settings_backup.json');
        await settingsFile.writeAsString(jsonEncode(settingsBackup));
      }

      // 3. Backup Downloads Database
      final docDir = await getApplicationDocumentsDirectory();
      final internalDbFile = File('${docDir.path}/downloads.json');
      if (internalDbFile.existsSync()) {
        final downloadsFile = File('${dir.path}/downloads_backup.json');
        await internalDbFile.copy(downloadsFile.path);
      }

      debugPrint("Backup successfully completed at: ${dir.path}");
    } catch (e) {
      debugPrint("Failed to write watchAny database backups: $e");
    }
  }

  // Restore everything from the active backup path
  Future<void> restoreAll() async {
    final path = await getBackupDirPath();
    await restoreFromPath(path);
  }

  // Restores configurations from a specific custom folder path
  Future<void> restoreFromPath(String folderPath) async {
    if (_isRestoring) return;
    _isRestoring = true;

    try {
      final backupDir = Directory(folderPath.endsWith('.backup') ? folderPath : '$folderPath/.backup');
      if (!backupDir.existsSync()) {
        debugPrint("No backup folder located at: ${backupDir.path}");
        _isRestoring = false;
        return;
      }

      final prefs = await SharedPreferences.getInstance();

      // Check if we are restoring onto a clean app instance (no local database items)
      final bool hasLocalLibrary = LibraryState().items.isNotEmpty;
      
      // 1. Restore App Settings (do not overwrite critical paths if they exist)
      final settingsFile = File('${backupDir.path}/settings_backup.json');
      if (settingsFile.existsSync()) {
        final content = await settingsFile.readAsString();
        final Map<String, dynamic> settings = jsonDecode(content);
        for (final entry in settings.entries) {
          final key = entry.key;
          final value = entry.value;
          
          // Only restore if the local setting does not exist or we want to overwrite settings
          if (prefs.get(key) == null) {
            if (value is String) {
              await prefs.setString(key, value);
            } else if (value is int) {
              await prefs.setInt(key, value);
            } else if (value is double) {
              await prefs.setDouble(key, value);
            } else if (value is bool) {
              await prefs.setBool(key, value);
            } else if (value is List) {
              await prefs.setStringList(key, value.map((e) => e.toString()).toList());
            }
          }
        }
        debugPrint("Settings successfully restored.");
      }

      // 2. Restore Library (only restore if currently empty to avoid overwriting newer data)
      if (!hasLocalLibrary) {
        final libraryFile = File('${backupDir.path}/library_backup.json');
        if (libraryFile.existsSync()) {
          final content = await libraryFile.readAsString();
          final Map<String, dynamic> libraryBackup = jsonDecode(content);

          final items = libraryBackup['library_items'];
          final categories = libraryBackup['library_categories'];
          final mangaCache = libraryBackup['manga_library_cache'];

          // Stage items to SharedPreferences. When LibraryState.init() runs next,
          // it will detect them, migrate them atomically into SQLite, and clear the keys.
          if (items != null) {
            await prefs.setString('library_items', jsonEncode(items));
          }
          if (categories != null) {
            await prefs.setString('library_categories', jsonEncode(categories));
          }
          if (mangaCache != null) {
            await prefs.setString('manga_library_cache', jsonEncode(mangaCache));
          }
          debugPrint("Library items staged for database migration.");
        }
      }

      // 3. Restore Downloads tasks
      final downloadsFile = File('${backupDir.path}/downloads_backup.json');
      final docDir = await getApplicationDocumentsDirectory();
      final internalDbFile = File('${docDir.path}/downloads.json');

      if (downloadsFile.existsSync() && !internalDbFile.existsSync()) {
        await downloadsFile.copy(internalDbFile.path);
        debugPrint("Downloads database successfully restored.");
      }

      // Reload memory states of all services to reflect the restored databases
      await AppSettings().init();
      await LibraryState().init();
      await DownloadService().init();

    } catch (e) {
      debugPrint("Error encountered during backup restoration: $e");
    } finally {
      _isRestoring = false;
    }
  }
}
