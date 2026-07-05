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

      // 1. Backup Library Items
      final String? itemsJson = prefs.getString('library_items');
      final String? catsJson = prefs.getString('library_categories');
      final String? cacheJson = prefs.getString('manga_library_cache');

      if (itemsJson != null || catsJson != null || cacheJson != null) {
        final libraryBackup = {
          'library_items': itemsJson != null ? jsonDecode(itemsJson) : [],
          'library_categories': catsJson != null ? jsonDecode(catsJson) : [],
          'manga_library_cache': cacheJson != null ? jsonDecode(cacheJson) : {},
          'timestamp': DateTime.now().toIso8601String(),
        };
        final libraryFile = File('${dir.path}/library_backup.json');
        await libraryFile.writeAsString(jsonEncode(libraryBackup));
      }

      // 2. Backup App Settings
      final settingsBackup = <String, dynamic>{};
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key != 'library_items' &&
            key != 'library_categories' &&
            key != 'manga_library_cache' &&
            key != 'downloads_backup') {
          final value = prefs.get(key);
          settingsBackup[key] = value;
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

      // Check if we are restoring onto a clean app instance
      final bool hasLocalLibrary = prefs.getString('library_items') != null;
      
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

          if (items != null) {
            await prefs.setString('library_items', jsonEncode(items));
          }
          if (categories != null) {
            await prefs.setString('library_categories', jsonEncode(categories));
          }
          if (mangaCache != null) {
            await prefs.setString('manga_library_cache', jsonEncode(mangaCache));
          }
          debugPrint("Library items and categories successfully restored.");
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
