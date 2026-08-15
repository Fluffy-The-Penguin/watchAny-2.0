import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service to fetch high-definition 1920x1080 widescreen banner images from Kitsu API.
class KitsuService {
  static final Map<String, String?> _bannerCache = {};

  /// Fetches a high-resolution 16:9 / 21:9 horizontal cover/banner image for a given anime title.
  static Future<String?> getBannerImage(String animeTitle) async {
    final String cleanKey = animeTitle.trim().toLowerCase();
    if (_bannerCache.containsKey(cleanKey)) {
      return _bannerCache[cleanKey];
    }

    try {
      final uri = Uri.parse(
        'https://kitsu.io/api/edge/anime?filter[text]=${Uri.encodeComponent(animeTitle)}&page[limit]=1',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && (data['data'] as List).isNotEmpty) {
          final attributes = data['data'][0]['attributes'];
          final coverImage = attributes['coverImage'];
          if (coverImage != null) {
            final String? bannerUrl = coverImage['original'] ?? coverImage['large'] ?? coverImage['tiny'];
            if (bannerUrl != null && bannerUrl.isNotEmpty) {
              _bannerCache[cleanKey] = bannerUrl;
              return bannerUrl;
            }
          }
        }
      }
    } catch (_) {}

    _bannerCache[cleanKey] = null;
    return null;
  }
}
