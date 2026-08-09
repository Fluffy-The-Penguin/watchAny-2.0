import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
      final dir = Directory(customPath);
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return customPath;
      } catch (e) {
        debugPrint("Error accessing custom cache path $customPath: $e");
      }
    }
    
    // Default isolated cache path
    try {
      final tempDir = await getTemporaryDirectory();
      final defaultPath = '${tempDir.path}${Platform.pathSeparator}watchAnyCache';
      final dir = Directory(defaultPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return defaultPath;
    } catch (e) {
      debugPrint("Error resolving default cache directory: $e");
      return Directory.systemTemp.path;
    }
  }

  /// Calculates total size of all cache directories in bytes.
  Future<int> getCacheSize() async {
    int totalSize = 0;
    try {
      final path = await getEffectiveCachePath();
      totalSize += await _getDirectorySize(Directory(path));

      // Also include system temp directory size
      try {
        final tempDir = await getTemporaryDirectory();
        if (tempDir.path != path) {
          totalSize += await _getDirectorySize(tempDir);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint("Error calculating cache size: $e");
    }
    return totalSize;
  }

  Future<int> _getDirectorySize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int size = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            size += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return size;
  }

  /// Clears all files in the cache directories and resets Flutter image memory cache.
  Future<void> clearCache() async {
    if (_isCleaning) return;
    _isCleaning = true;
    notifyListeners();

    try {
      // 1. Clear Flutter Image Cache in memory
      try {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (_) {}

      // 2. Clear effective custom/default watchAny cache folder
      final path = await getEffectiveCachePath();
      await _deleteDirectoryContents(Directory(path));

      // 3. Clear system temp directory contents
      try {
        final tempDir = await getTemporaryDirectory();
        if (tempDir.path != path) {
          await _deleteDirectoryContents(tempDir);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint("Error clearing cache: $e");
    } finally {
      _isCleaning = false;
      notifyListeners();
    }
  }

  Future<void> _deleteDirectoryContents(Directory dir) async {
    if (!await dir.exists()) return;
    try {
      await for (final entity in dir.list(recursive: false)) {
        try {
          if (entity is File) {
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          }
        } catch (_) {
          // Ignore files currently locked by open video players or processes
        }
      }
    } catch (_) {}
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
      
      final List<MapEntry<File, DateTime>> fileList = [];
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            fileList.add(MapEntry(entity, stat.modified));
          } catch (_) {}
        }
      }

      fileList.sort((a, b) => a.value.compareTo(b.value));

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
