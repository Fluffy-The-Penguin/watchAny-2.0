import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Singleton service that persistently caches episode thumbnails to disk.
///
/// Thumbnails are saved to [getApplicationDocumentsDirectory()]/ep_thumbs/
/// so they load instantly on subsequent visits without any network calls.
class TvdbService {
  static final TvdbService _instance = TvdbService._internal();
  factory TvdbService() => _instance;
  TvdbService._internal();

  Directory? _thumbsDir;

  Future<Directory> _getThumbsDir() async {
    if (_thumbsDir != null) return _thumbsDir!;
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/ep_thumbs');
    if (!await dir.exists()) await dir.create(recursive: true);
    _thumbsDir = dir;
    return dir;
  }

  /// Stable 31-bit hash of [url] used as a cache filename.
  static String _fileNameForUrl(String url) {
    int h = 5381;
    for (final c in url.codeUnits) {
      h = (((h << 5) + h) ^ c) & 0x7FFFFFFF;
    }
    return '$h.jpg';
  }

  /// Returns the local cached file path for [url] if it exists on disk.
  Future<String?> getCachedPath(String url) async {
    if (url.isEmpty) return null;
    try {
      final dir = await _getThumbsDir();
      final file = File('${dir.path}/${_fileNameForUrl(url)}');
      if (await file.exists() && (await file.length()) > 512) {
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  /// Downloads [url] and saves it to the persistent ep_thumbs cache.
  /// Skips the download if already cached. Returns the local path or null.
  Future<String?> downloadAndCache(String url) async {
    if (url.isEmpty) return null;

    // Skip TVDB URLs — they need auth that we no longer support
    if (url.contains('thetvdb.com') || url.contains('artworks.thetvdb.com')) {
      return null;
    }

    final existing = await getCachedPath(url);
    if (existing != null) return existing;

    try {
      final dir = await _getThumbsDir();
      final file = File('${dir.path}/${_fileNameForUrl(url)}');

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (compatible; watchAny/2.0)'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && response.bodyBytes.length > 512) {
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e) {
      debugPrint('[ThumbnailCache] Download failed for $url: $e');
    }
    return null;
  }
}
