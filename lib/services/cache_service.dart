import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../state/app_settings.dart';

class CacheService extends ChangeNotifier {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  bool _isCleaning = false;
  bool get isCleaning => _isCleaning;

  /// Returns the custom cache path if configured, or the default isolated temp directory.
  Future<String> getEffectiveCachePath() async {
    final customPath = AppSettings().cachePath;
    if (customPath.isNotEmpty) {
      return customPath;
    }
    
    // Default isolated cache path
    final tempDir = await getTemporaryDirectory();
    final defaultPath = '${tempDir.path}${Platform.pathSeparator}watchAnyCache';
    
    final dir = Directory(defaultPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return defaultPath;
  }

  /// Calculates total size of the cache directory in bytes.
  Future<int> getCacheSize() async {
    try {
      final path = await getEffectiveCachePath();
      final dir = Directory(path);
      if (!await dir.exists()) return 0;

      int totalSize = 0;
      await for (final file in dir.list(recursive: true, followLinks: false)) {
        if (file is File) {
          try {
            totalSize += await file.length();
          } catch (_) {
            // Ignore files currently locked by process
          }
        }
      }
      return totalSize;
    } catch (e) {
      debugPrint("Error calculating cache size: $e");
      return 0;
    }
  }

  /// Clears all files in the cache directory.
  Future<void> clearCache() async {
    if (_isCleaning) return;
    _isCleaning = true;
    notifyListeners();

    try {
      final path = await getEffectiveCachePath();
      final dir = Directory(path);
      if (await dir.exists()) {
        await for (final file in dir.list(recursive: false)) {
          try {
            if (file is File) {
              await file.delete();
            } else if (file is Directory) {
              await file.delete(recursive: true);
            }
          } catch (_) {
            // Ignore files currently in use/locked
          }
        }
      }
    } catch (e) {
      debugPrint("Error clearing cache: $e");
    } finally {
      _isCleaning = false;
      notifyListeners();
    }
  }

  /// Deletes the oldest files until the cache directory is under 90% of the set limit.
  Future<void> pruneCache() async {
    try {
      final path = await getEffectiveCachePath();
      final dir = Directory(path);
      if (!await dir.exists()) return;

      final limitBytes = (AppSettings().cacheLimitGB * 1024 * 1024 * 1024).round();
      int currentSize = await getCacheSize();
      if (currentSize <= limitBytes) return;

      final targetSize = (limitBytes * 0.9).round();
      
      // Get all files with their last modified timestamps
      final List<MapEntry<File, DateTime>> fileList = [];
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            fileList.add(MapEntry(entity, stat.modified));
          } catch (_) {}
        }
      }

      // Sort oldest files first
      fileList.sort((a, b) => a.value.compareTo(b.value));

      // Evict oldest files
      for (final entry in fileList) {
        if (currentSize <= targetSize) break;
        final file = entry.key;
        try {
          final size = await file.length();
          await file.delete();
          currentSize -= size;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("Error pruning cache: $e");
    }
  }
}
