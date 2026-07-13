import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Singleton service that permanently caches library cover and banner images
/// to [getApplicationDocumentsDirectory()]/covers/.
///
/// Unlike [CachedNetworkImage]'s automatic disk cache (which lives in
/// getTemporaryDirectory() and can be purged by the OS), files stored here
/// survive across app restarts and are never deleted by the system.
class LibraryImageCache {
  static final LibraryImageCache _instance = LibraryImageCache._internal();
  factory LibraryImageCache() => _instance;
  LibraryImageCache._internal();

  Directory? _coversDir;

  Future<Directory> _getCacheDir() async {
    if (_coversDir != null) return _coversDir!;
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/covers');
    if (!await dir.exists()) await dir.create(recursive: true);
    _coversDir = dir;
    return dir;
  }

  /// Returns the local file name for a given item.
  /// [type] is either `'cover'` or `'banner'`.
  String _fileName(int id, String mode, String type) =>
      '${mode}_${id}_$type.jpg';

  /// Returns the absolute local path if the image is cached and non-empty,
  /// otherwise returns null.
  Future<String?> getLocalPath(int id, String mode, String type) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_fileName(id, mode, type)}');
      if (await file.exists() && (await file.length()) > 0) {
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  /// Downloads [url] and saves it permanently under the covers directory.
  /// This is a no-op if the file already exists (idempotent).
  /// Safe to call fire-and-forget (never throws).
  Future<void> cacheImage(String url, int id, String mode, String type) async {
    if (url.isEmpty) return;
    try {
      final localPath = await getLocalPath(id, mode, type);
      if (localPath != null) return; // Already cached

      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_fileName(id, mode, type)}');

      final response = await http
          .get(Uri.parse(url), headers: {
            'User-Agent':
                'Mozilla/5.0 (compatible; watchAny/2.0; +https://github.com/Fluffy-The-Penguin/watchAny-2.0)',
          })
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes);
      }
    } catch (_) {
      // Silently swallow — offline caching is best-effort
    }
  }

  /// Deletes the cached cover and banner for the given library item.
  /// Called when an item is removed from the library.
  Future<void> deleteImages(int id, String mode) async {
    try {
      final dir = await _getCacheDir();
      for (final type in ['cover', 'banner']) {
        final file = File('${dir.path}/${_fileName(id, mode, type)}');
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
  }

  /// Builds the appropriate image widget: [Image.file] if a local path is
  /// available, otherwise [CachedNetworkImage] (falls back to network).
  Widget buildWidget({
    required String? localPath,
    required String? networkUrl,
    BoxFit fit = BoxFit.cover,
    int? memCacheWidth,
    Widget? placeholder,
    Widget? errorFallback,
  }) {
    final fallback =
        placeholder ?? Container(color: Colors.white.withValues(alpha: 0.02));

    if (localPath != null && localPath.isNotEmpty) {
      return Image.file(
        File(localPath),
        fit: fit,
        cacheWidth: memCacheWidth,
        errorBuilder: (_, __, ___) {
          // If local file is corrupt, fall through to network
          if (networkUrl != null && networkUrl.isNotEmpty) {
            return CachedNetworkImage(
              imageUrl: networkUrl,
              fit: fit,
              memCacheWidth: memCacheWidth,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => errorFallback ?? fallback,
            );
          }
          return errorFallback ?? fallback;
        },
      );
    }

    if (networkUrl != null && networkUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: networkUrl,
        fit: fit,
        memCacheWidth: memCacheWidth,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => errorFallback ?? fallback,
      );
    }

    return fallback;
  }
}
