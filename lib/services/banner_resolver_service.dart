import 'dart:convert';
import 'package:http/http.dart' as http;

/// Dedicated high-definition Banner Resolver Service.
/// 1st Choice: TMDB / TVDB 1080p/4K Widescreen Backdrop
/// 2nd Choice: AniList Genuine Banner Image (bannerImage)
/// 
/// NEVER falls back to vertical cover poster art (extraLarge) to avoid 2.7x zoom stretch!
class BannerResolverService {
  static final Map<String, String?> _resolvedCache = {};

  /// Resolves the optimal high-definition horizontal banner URL for an anime or show.
  static Future<String?> getBestBanner({
    required String title,
    String? anilistBanner,
    String? format,
  }) async {
    final String cleanKey = title.trim().toLowerCase();
    if (_resolvedCache.containsKey(cleanKey)) {
      return _resolvedCache[cleanKey];
    }

    // 1st Choice: Check if AniList already has a valid horizontal bannerImage
    if (anilistBanner != null && anilistBanner.isNotEmpty) {
      String finalAnilist = anilistBanner;
      if (finalAnilist.contains('image.tmdb.org/t/p/')) {
        finalAnilist = finalAnilist.replaceAll(RegExp(r'/w\d+/'), '/original/');
      }
      _resolvedCache[cleanKey] = finalAnilist;
      return finalAnilist;
    }

    // 2nd Choice: Search TMDB for a 1080p / 4K Widescreen Backdrop
    if (title.isNotEmpty) {
      final tmdbBackdrop = await _fetchTmdbBackdrop(title, format: format ?? 'TV');
      if (tmdbBackdrop != null && tmdbBackdrop.isNotEmpty) {
        _resolvedCache[cleanKey] = tmdbBackdrop;
        return tmdbBackdrop;
      }
    }

    _resolvedCache[cleanKey] = null;
    return null;
  }

  /// Fetches a high-resolution 4K/1080p backdrop from TMDB search
  static Future<String?> _fetchTmdbBackdrop(String title, {String format = 'TV'}) async {
    try {
      final searchType = format.toUpperCase() == 'MOVIE' ? 'movie' : 'tv';
      // Clean title for better search precision
      final cleanTitle = title.split(':').first.split('~').first.trim();
      final uri = Uri.parse(
        'https://api.themoviedb.org/3/search/$searchType?api_key=15d2ec48754c86065f357913610d720a&query=${Uri.encodeComponent(cleanTitle)}',
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
