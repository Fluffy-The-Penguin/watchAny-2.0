import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockHttpResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  _MockHttpResponse(this.statusCode, this.body, {this.headers = const {}});
}

class AnilistService {
  static const String _endpoint = 'https://graphql.anilist.co';

  static final Dio _dio = Dio()
    ..httpClientAdapter = Http2Adapter(
      ConnectionManager(idleTimeout: const Duration(seconds: 15)),
    );

  Future<_MockHttpResponse> _post(String query, Map<String, dynamic>? variables, {Map<String, String>? headers}) async {
    final Map<String, dynamic> finalHeaders = {..._headers};
    if (headers != null) finalHeaders.addAll(headers);

    try {
      final response = await _dio.post(
        _endpoint,
        data: {
          'query': query,
          'variables': variables,
        },
        options: Options(
          headers: finalHeaders,
          validateStatus: (status) => true,
        ),
      );
      
      final Map<String, String> headerMap = {};
      response.headers.forEach((name, values) {
        headerMap[name] = values.join(',');
      });

      final String jsonStr = response.data is String ? response.data : jsonEncode(response.data);
      return _MockHttpResponse(
        response.statusCode ?? 200, 
        jsonStr, 
        headers: headerMap,
      );
    } catch (e) {
      return _MockHttpResponse(500, jsonEncode({'errors': [{'message': e.toString()}]}));
    }
  }

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  };

  static Map<String, dynamic>? _dashboardCache;
  static DateTime? _lastFetchedTime;

  // Get current season string for AniList API
  static String getCurrentSeason(DateTime date) {
    final month = date.month;
    if (month == 12 || month == 1 || month == 2) {
      return 'WINTER';
    } else if (month >= 3 && month <= 5) {
      return 'SPRING';
    } else if (month >= 6 && month <= 8) {
      return 'SUMMER';
    } else {
      return 'FALL';
    }
  }

  // Fetch all dashboard categories in one query
  Future<Map<String, dynamic>> fetchDashboardData({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      if (_dashboardCache != null && _lastFetchedTime != null) {
        final difference = DateTime.now().difference(_lastFetchedTime!);
        if (difference.inMinutes < 15) {
          return _dashboardCache!;
        }
      }
      
      final String? cachedJson = prefs.getString('anilist_dashboard_cache');
      final int? lastFetched = prefs.getInt('anilist_dashboard_last_fetched');
      if (cachedJson != null && lastFetched != null) {
        final age = DateTime.now().millisecondsSinceEpoch - lastFetched;
        if (age < const Duration(hours: 3).inMilliseconds) {
          try {
            final decoded = jsonDecode(cachedJson);
            if (decoded is Map<String, dynamic>) {
              _dashboardCache = decoded;
              _lastFetchedTime = DateTime.fromMillisecondsSinceEpoch(lastFetched);
              return _dashboardCache!;
            }
          } catch (_) {}
        }
      }
    }

    final now = DateTime.now();
    final season = getCurrentSeason(now);
    final year = now.year;

    const query = r'''
      query($season: MediaSeason, $seasonYear: Int) {
        trending: Page(page: 1, perPage: 8) {
          media(sort: TRENDING_DESC, type: ANIME) {
            id
            title {
              romaji
              english
              native
            }
            bannerImage
            coverImage {
              extraLarge
              large
            }
            description
            genres
            averageScore
            episodes
            format
          }
        }
        popularThisSeason: Page(page: 1, perPage: 12) {
          media(sort: POPULARITY_DESC, type: ANIME, season: $season, seasonYear: $seasonYear) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            averageScore
            format
            episodes
          }
        }
        newlyReleased: Page(page: 1, perPage: 12) {
          media(sort: TRENDING_DESC, type: ANIME, status: RELEASING) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            averageScore
            format
            episodes
          }
        }
        upcoming: Page(page: 1, perPage: 12) {
          media(sort: POPULARITY_DESC, type: ANIME, status: NOT_YET_RELEASED) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            format
            episodes
          }
        }
        action: Page(page: 1, perPage: 12) {
          media(genre: "Action", sort: POPULARITY_DESC, type: ANIME) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            averageScore
          }
        }
        adventure: Page(page: 1, perPage: 12) {
          media(genre: "Adventure", sort: POPULARITY_DESC, type: ANIME) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            averageScore
          }
        }
        romance: Page(page: 1, perPage: 12) {
          media(genre: "Romance", sort: POPULARITY_DESC, type: ANIME) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            averageScore
          }
        }
        fantasy: Page(page: 1, perPage: 12) {
          media(genre: "Fantasy", sort: POPULARITY_DESC, type: ANIME) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            averageScore
          }
        }
      }
    ''';

    final variables = {
      'season': season,
      'seasonYear': year,
    };

    try {
      final response = await _post(query, variables);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['data'] != null) {
          _dashboardCache = body['data'] as Map<String, dynamic>;
          _lastFetchedTime = DateTime.now();
          await prefs.setString('anilist_dashboard_cache', jsonEncode(_dashboardCache));
          await prefs.setInt('anilist_dashboard_last_fetched', _lastFetchedTime!.millisecondsSinceEpoch);
          return _dashboardCache!;
        }
        throw Exception('GraphQL error: ${body['errors']}');
      } else {
        throw Exception('HTTP Request failed with status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load AniList dashboard data: $e');
    }
  }

  // Fetch detailed information for a single anime
  Future<Map<String, dynamic>> fetchAnimeDetails(int id) async {
    const query = r'''
      query($id: Int) {
        Media(id: $id, type: ANIME) {
          id
          idMal
          startDate {
            year
            month
            day
          }
          title {
            romaji
            english
            native
          }
          bannerImage
          coverImage {
            extraLarge
            large
          }
          description
          genres
          averageScore
          episodes
          format
          status
          season
          seasonYear
          studios(isMain: true) {
            nodes {
              name
            }
          }
          nextAiringEpisode {
            episode
            timeUntilAiring
          }
          streamingEpisodes {
            title
            thumbnail
            url
            site
          }
          characters(sort: ROLE, page: 1, perPage: 12) {
            edges {
              role
              node {
                id
                name {
                  full
                }
                image {
                  large
                }
              }
              voiceActors(language: JAPANESE) {
                name {
                  full
                }
                image {
                  large
                }
              }
            }
          }
          relations {
            edges {
              relationType
              node {
                id
                type
                format
                title {
                  romaji
                  english
                }
                coverImage {
                  large
                }
                status
              }
            }
          }
          recommendations(perPage: 6, sort: RATING_DESC) {
            nodes {
              mediaRecommendation {
                id
                type
                format
                title {
                  romaji
                  english
                }
                coverImage {
                  large
                }
                averageScore
              }
            }
          }
        }
      }
    ''';

    final variables = {
      'id': id,
    };

    try {
      final response = await _post(query, variables);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['data'] != null && body['data']['Media'] != null) {
          return body['data']['Media'] as Map<String, dynamic>;
        }
        throw Exception('GraphQL error or Media not found: ${body['errors']}');
      } else {
        throw Exception('HTTP Request failed with status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load anime details ($id): $e');
    }
  }

  // Search and discover AniList media (type 'ANIME' or 'MANGA') with filters
  Future<Map<String, dynamic>> search({
    required int page,
    required int perPage,
    String? searchQuery,
    required String type, // 'ANIME' or 'MANGA'
    List<String>? genres,
    int? year,
    String? season, // 'WINTER', 'SPRING', 'SUMMER', 'FALL'
    List<String>? formats, // list of formats like 'TV', 'MOVIE', etc.
    String? status, // 'FINISHED', 'RELEASING', etc.
    String? sort, // 'TRENDING_DESC', 'POPULARITY_DESC', 'SCORE_DESC', etc.
  }) async {
    const query = r'''
      query($page: Int, $perPage: Int, $search: String, $type: MediaType, $genres: [String], $year: Int, $season: MediaSeason, $formats: [MediaFormat], $status: MediaStatus, $sort: [MediaSort]) {
        Page(page: $page, perPage: $perPage) {
          pageInfo {
            total
            currentPage
            lastPage
            hasNextPage
          }
          media(search: $search, type: $type, genre_in: $genres, seasonYear: $year, season: $season, format_in: $formats, status: $status, sort: $sort) {
            id
            title {
              romaji
              english
              native
            }
            coverImage {
              extraLarge
              large
            }
            averageScore
            format
            episodes
            status
          }
        }
      }
    ''';

    final Map<String, dynamic> variables = {
      'page': page,
      'perPage': perPage,
      'type': type,
    };

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      variables['search'] = searchQuery.trim();
    }
    if (genres != null && genres.isNotEmpty) {
      variables['genres'] = genres;
    }
    if (year != null) {
      variables['year'] = year;
    }
    if (season != null && season.isNotEmpty && season != 'ALL') {
      variables['season'] = season.toUpperCase();
    }
    if (formats != null && formats.isNotEmpty) {
      variables['formats'] = formats.map((f) => f.toUpperCase()).toList();
    }
    if (status != null && status.isNotEmpty && status != 'ALL') {
      variables['status'] = status.toUpperCase();
    }
    if (sort != null && sort.isNotEmpty) {
      variables['sort'] = [sort.toUpperCase()];
    } else {
      variables['sort'] = ['POPULARITY_DESC'];
    }

    try {
      final response = await _post(query, variables);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['data'] != null) {
          return body['data'] as Map<String, dynamic>;
        }
        throw Exception('GraphQL error: ${body['errors']}');
      } else {
        throw Exception('HTTP Request failed with status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Search failed: $e');
    }
  }

  // Fetch multiple media items by ID for the library page (real-time fetching)
  Future<List<dynamic>> fetchMultipleMedia(List<int> ids, String type) async {
    if (ids.isEmpty) return [];
    final uniqueIds = ids.toSet().toList();

    try {
      final List<dynamic> results = [];
      for (int i = 0; i < uniqueIds.length; i += 50) {
        final chunk = uniqueIds.sublist(i, i + 50 > uniqueIds.length ? uniqueIds.length : i + 50);
        final batchResult = await _fetchMultipleMediaBatch(chunk, type);
        results.addAll(batchResult);
      }
      return results;
    } catch (e) {
      // If batch fails, query in chunks of 10 to isolate any problematic IDs
      final List<dynamic> results = [];
      for (int i = 0; i < uniqueIds.length; i += 10) {
        final chunk = uniqueIds.sublist(i, i + 10 > uniqueIds.length ? uniqueIds.length : i + 10);
        try {
          final batchResult = await _fetchMultipleMediaBatch(chunk, type);
          results.addAll(batchResult);
        } catch (_) {
          // If chunk fails, query each individually to skip the offending ID
          for (final id in chunk) {
            try {
              final singleResult = await _fetchMultipleMediaBatch([id], type);
              results.addAll(singleResult);
            } catch (_) {}
          }
        }
      }
      return results;
    }
  }

  Future<List<dynamic>> _fetchMultipleMediaBatch(List<int> ids, String type) async {
    if (ids.isEmpty) return [];
    const query = r'''
      query($ids: [Int], $type: MediaType) {
        Page(page: 1, perPage: 100) {
          media(id_in: $ids, type: $type) {
            id
            title {
              romaji
              english
              native
            }
            coverImage {
              large
            }
            averageScore
            format
            episodes
            status
            bannerImage
          }
        }
      }
    ''';

    final response = await _post(query, {
      'ids': ids,
      'type': type,
    });

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['data'] != null && body['data']['Page'] != null && body['data']['Page']['media'] != null) {
        return body['data']['Page']['media'] as List<dynamic>;
      }
      throw Exception('GraphQL error: ${body['errors']}');
    } else {
      throw Exception('HTTP Request failed with status: ${response.statusCode}');
    }
  }

  // Fetch airing schedule within a time range (Epoch seconds)
  Future<List<dynamic>> fetchAiringSchedule(int startTimestamp, int endTimestamp) async {
    // Fetch 15 pages (up to 1500 entries) in parallel, spacing each request by 80ms to avoid burst rate limit locks
    final futures = List.generate(15, (index) async {
      if (index > 0) {
        await Future.delayed(Duration(milliseconds: index * 80));
      }
      return _fetchAiringSchedulePage(startTimestamp, endTimestamp, index + 1);
    });
    try {
      final results = await Future.wait(futures);
      return results.expand((x) => x).toList();
    } catch (e) {
      throw Exception('Failed to load airing schedules: $e');
    }
  }

  Future<List<dynamic>> _fetchAiringSchedulePage(int start, int end, int page) async {
    const query = r'''
      query($start: Int, $end: Int, $page: Int) {
        Page(page: $page, perPage: 100) {
          airingSchedules(airingAt_greater: $start, airingAt_lesser: $end, sort: TIME) {
            id
            airingAt
            episode
            mediaId
            media {
              id
              title {
                romaji
                english
                native
              }
              coverImage {
                extraLarge
                large
              }
              bannerImage
              genres
              averageScore
              episodes
              format
              description
            }
          }
        }
      }
    ''';

    final variables = {
      'start': start,
      'end': end,
      'page': page,
    };

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _post(query, variables);

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          if (body['data'] != null && body['data']['Page'] != null) {
            final pageData = body['data']['Page'];
            return pageData['airingSchedules'] as List<dynamic>? ?? [];
          }
        } else if (response.statusCode == 429) {
          // Rate limited, wait based on headers or default to 2s, then retry
          final retryAfter = response.headers['retry-after'];
          final waitSeconds = retryAfter != null ? int.tryParse(retryAfter) ?? 2 : 2;
          await Future.delayed(Duration(seconds: waitSeconds));
          continue;
        }
      } catch (_) {}
      
      // Minor delay on generic network errors before retry
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return [];
  }

  Future<List<dynamic>> fetchLibraryDetails(List<int> ids, {String type = 'ANIME'}) async {
    if (ids.isEmpty) return [];
    
    const query = r'''
      query($ids: [Int], $type: MediaType) {
        Page(page: 1, perPage: 50) {
          media(id_in: $ids, type: $type) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            status
            episodes
            chapters
            nextAiringEpisode {
              episode
              airingAt
            }
          }
        }
      }
    ''';
    
    try {
      final response = await _post(query, {
        'ids': ids,
        'type': type,
      });
      
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['data']?['Page']?['media'] ?? [];
      }
    } catch (e) {
      // ignore
    }
    return [];
  }

  Future<String?> exchangeCodeForToken(String code) async {
    const tokenUrl = 'https://anilist.co/api/v2/oauth/token';
    try {
      final dioResponse = await _dio.post(
        tokenUrl,
        data: {
          'grant_type': 'authorization_code',
          'client_id': '45095',
          'client_secret': 'VzfQd0wcEAg2VUiWEV8oCiZMGsVI0QsXrvSONL8r',
          'redirect_uri': 'https://anilist.co/api/v2/oauth/pin',
          'code': code.trim(),
        },
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          },
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      final Map<String, String> headerMap = {};
      dioResponse.headers.forEach((name, values) {
        headerMap[name] = values.join(',');
      });

      final response = _MockHttpResponse(
        dioResponse.statusCode ?? 200,
        dioResponse.data is String ? dioResponse.data : jsonEncode(dioResponse.data),
        headers: headerMap,
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['access_token'] as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchViewerDetails(String token) async {
    const query = r'''
      query {
        Viewer {
          id
          name
          avatar {
            large
          }
          bannerImage
          statistics {
            anime {
              count
              episodesWatched
              minutesWatched
            }
            manga {
              count
              chaptersRead
              volumesRead
            }
          }
        }
      }
    ''';

    try {
      final response = await _post(
        query,
        null,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['data']?['Viewer'];
      }
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>> fetchUserLibrary(int userId, String type, String token) async {
    const query = r'''
      query($userId: Int, $type: MediaType) {
        MediaListCollection(userId: $userId, type: $type) {
          lists {
            name
            status
            entries {
              id
              status
              score(format: POINT_10_DECIMAL)
              progress
              media {
                id
                title {
                  romaji
                  english
                  native
                }
                coverImage {
                  large
                }
                episodes
                chapters
                format
                status
                averageScore
                bannerImage
              }
            }
          }
        }
      }
    ''';

    try {
      final response = await _post(
        query,
        {
          'userId': userId,
          'type': type,
        },
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final lists = body['data']?['MediaListCollection']?['lists'] as List? ?? [];
        final List<dynamic> allEntries = [];
        for (var list in lists) {
          final entries = list['entries'] as List? ?? [];
          allEntries.addAll(entries);
        }
        return allEntries;
      }
    } catch (_) {}
    return [];
  }

  Future<bool> syncProgressToAnilist({
    required int mediaId,
    required String status,
    required int progress,
    required double score,
    required String token,
  }) async {
    const query = r'''
      mutation($mediaId: Int, $status: MediaListStatus, $progress: Int, $score: Float) {
        SaveMediaListEntry(mediaId: $mediaId, status: $status, progress: $progress, score: $score) {
          id
          status
          progress
          score
        }
      }
    ''';

    String aniListStatus = 'CURRENT';
    if (status == 'watching') {
      aniListStatus = 'CURRENT';
    } else if (status == 'planning') {
      aniListStatus = 'PLANNING';
    } else if (status == 'completed') {
      aniListStatus = 'COMPLETED';
    } else if (status == 'paused_dropped') {
      aniListStatus = 'DROPPED';
    }

    try {
      final response = await _post(
        query,
        {
          'mediaId': mediaId,
          'status': aniListStatus,
          'progress': progress,
          'score': score,
        },
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['data']?['SaveMediaListEntry'] != null;
      }
    } catch (_) {}
    return false;
  }
}
