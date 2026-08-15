import 'dart:convert';
import 'package:http/http.dart' as http;
import 'kitsu_service.dart';

/// Helper service that resolves high-resolution hero/banner images using the user's exact 3-tier fallback:
/// 1st Choice: Kitsu 1080p Widescreen Banner
/// 2nd Fallback: TMDB 1080p/4K Widescreen Backdrop
/// 3rd (Last) Fallback: AniList bannerImage
class BannerResolverService {
  static final Map<String, String?> _resolvedCache = {};

  /// Resolves the optimal high-definition banner URL for an anime or title.
  static Future<String?> getBestBanner({
    required String title,
    String? anilistBanner,
    String? format,
  }) async {
    final String cleanKey = title.trim().toLowerCase();
    if (_resolvedCache.containsKey(cleanKey) && _resolvedCache[cleanKey] != null) {
      return _resolvedCache[cleanKey];
    }

    // 1st Choice: Kitsu 1080p Widescreen Banner
    if (title.isNotEmpty) {
      final kitsuBanner = await KitsuService.getBannerImage(title);
      if (kitsuBanner != null && kitsuBanner.isNotEmpty) {
        _resolvedCache[cleanKey] = kitsuBanner;
        return kitsuBanner;
      }
    }

    // 2nd Fallback: TMDB 1080p/4K Backdrop
    if (title.isNotEmpty) {
      final tmdbBackdrop = await _fetchTmdbBackdrop(title, format: format ?? 'TV');
      if (tmdbBackdrop != null && tmdbBackdrop.isNotEmpty) {
        _resolvedCache[cleanKey] = tmdbBackdrop;
        return tmdbBackdrop;
      }
    }

    // 3rd (Last) Fallback: AniList bannerImage
    if (anilistBanner != null && anilistBanner.isNotEmpty) {
      String finalAnilist = anilistBanner;
      if (finalAnilist.contains('image.tmdb.org/t/p/')) {
        finalAnilist = finalAnilist.replaceAll(RegExp(r'/w\d+/'), '/original/');
      }
      _resolvedCache[cleanKey] = finalAnilist;
      return finalAnilist;
    }

    return null;
  }

  /// Fetches a high-resolution 4K/1080p backdrop from TMDB search
  static Future<String?> _fetchTmdbBackdrop(String title, {String format = 'TV'}) async {
    try {
      final searchType = format.toUpperCase() == 'MOVIE' ? 'movie' : 'tv';
      final uri = Uri.parse(
        'https://api.themoviedb.org/3/search/$searchType?api_key=15d2ec48754c86065f357913610d720a&query=${Uri.encodeComponent(title)}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          for (var item in results) {
            final String? backdropPath = item['backdrop_path'];
            if (backdropPath != null && backdropPath.isNotEmpty) {
              return 'https://image.tmdb.org/t/p/original$backdropPath';
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
