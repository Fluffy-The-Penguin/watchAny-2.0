import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class FillerService {
  static final FillerService _instance = FillerService._internal();
  factory FillerService() => _instance;
  FillerService._internal();

  final http.Client _httpClient = http.Client();
  final Map<int, Map<int, String>> _fillerCache = {};
  bool _initialized = false;
  late final File _cacheFile;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final appDir = await getApplicationSupportDirectory();
      _cacheFile = File('${appDir.path}/filler_cache.json');
      if (await _cacheFile.exists()) {
          final content = await _cacheFile.readAsString();
          final rawJson = jsonDecode(content) as Map<String, dynamic>;
          rawJson.forEach((animeIdStr, epMapRaw) {
            final animeId = int.tryParse(animeIdStr);
            if (animeId != null && epMapRaw is Map<String, dynamic>) {
              final Map<int, String> epMap = {};
              epMapRaw.forEach((epNumStr, type) {
                final epNum = int.tryParse(epNumStr);
                if (epNum != null) {
                  epMap[epNum] = type.toString();
                }
              });
              _fillerCache[animeId] = epMap;
            }
          });
      }
    } catch (e) {
      debugPrint('[FillerService] Error loading cache: $e');
    }
    _initialized = true;
  }

  Future<void> loadFillerData(int animeId, List<String> titles) async {
    await init();
    if (_fillerCache.containsKey(animeId) && _fillerCache[animeId]!.isNotEmpty) {
      return; // Already loaded and cached
    }

    final slugs = _generateSlugs(titles);
    if (slugs.isEmpty) return;

    for (final slug in slugs) {
      try {
        final url = Uri.parse('https://www.animefillerlist.com/shows/$slug');
        debugPrint('[FillerService] Scraping filler list for slug: $slug');
        final response = await _httpClient.get(
          url,
          headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'},
        ).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final html = response.body;
          // Parse HTML table rows using regex
          final regExp = RegExp(
            r'<tr class="([^"]+)"[^>]*>.*?<td class="Number">(\d+)</td>.*?<td class="Type"><span>(.*?)</span>',
            dotAll: true,
          );

          final matches = regExp.allMatches(html);
          if (matches.isNotEmpty) {
            final Map<int, String> epMap = {};
            for (final m in matches) {
              final epNum = int.tryParse(m.group(2) ?? '');
              final type = m.group(3)?.trim() ?? '';
              if (epNum != null && type.isNotEmpty) {
                epMap[epNum] = type;
              }
            }

            if (epMap.isNotEmpty) {
              _fillerCache[animeId] = epMap;
              debugPrint('[FillerService] Successfully scraped ${epMap.length} episodes for $slug');
              await _saveCacheToDisk();
              return; // Found a working slug, no need to try others
            }
          }
        }
      } catch (e) {
        debugPrint('[FillerService] Scraper error for slug $slug: $e');
      }
    }

    // If all slugs fail, save an empty entry to avoid spamming requests
    _fillerCache[animeId] = {};
  }

  String? getFillerType(int animeId, int epNum) {
    final animeMap = _fillerCache[animeId];
    if (animeMap == null) return null;
    return animeMap[epNum];
  }

  bool isFiller(int animeId, int epNum) {
    final type = getFillerType(animeId, epNum);
    if (type == null) return false;
    // We treat "Filler" as filler.
    // "Mixed Canon/Filler" is not pure filler and contains canon story, so we don't skip it.
    return type.toLowerCase() == 'filler';
  }

  List<String> _generateSlugs(List<String> titles) {
    final List<String> slugs = [];
    for (final title in titles) {
      if (title.isEmpty) continue;
      
      // Slugify rules:
      // 1. Lowercase
      // 2. Remove season indicators like "Season X", "Part X", "Cour X", "S2", "S3", etc.
      // 3. Remove punctuation and non-alphanumeric (except spaces/hyphens)
      // 4. Replace spaces/hyphens with single hyphen
      String slug = title.toLowerCase();
      
      // Clean typical season suffixes
      slug = slug.replaceAll(RegExp(r'\b(?:s(?:eason)?|part|cour)\s*0*[1-9]\d*\b'), '');
      slug = slug.replaceAll(RegExp(r'\b\d+(?:st|nd|rd|th)\s*(?:season|cour)\b'), '');
      slug = slug.replaceAll(RegExp(r'\b[ivx]+\b'), ''); // Roman numerals
      
      // Clean non-alphanumeric except space and hyphen
      slug = slug.replaceAll(RegExp(r'[^a-z0-9\s\-]'), '');
      
      // Clean multiple spaces/hyphens
      slug = slug.trim().replaceAll(RegExp(r'[\s\-]+'), '-');
      
      if (slug.isNotEmpty && !slugs.contains(slug)) {
        slugs.add(slug);
        
        // Also add variations (e.g. without "-tv" suffix or similar)
        if (slug.endsWith('-tv')) {
          slugs.add(slug.substring(0, slug.length - 3));
        }
      }
    }
    return slugs;
  }

  Future<void> _saveCacheToDisk() async {
    try {
      final Map<String, Map<String, String>> serializable = {};
      _fillerCache.forEach((animeId, epMap) {
        final Map<String, String> stringEpMap = {};
        epMap.forEach((epNum, type) {
          stringEpMap[epNum.toString()] = type;
        });
        serializable[animeId.toString()] = stringEpMap;
      });
      await _cacheFile.writeAsString(jsonEncode(serializable));
    } catch (e) {
      debugPrint('[FillerService] Failed to save cache: $e');
    }
  }
}
