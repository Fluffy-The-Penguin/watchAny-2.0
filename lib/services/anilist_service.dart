import 'dart:convert';
import 'package:http/http.dart' as http;

class AnilistService {
  static const String _endpoint = 'https://graphql.anilist.co';

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
  Future<Map<String, dynamic>> fetchDashboardData() async {
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
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'query': query,
          'variables': variables,
        }),
      );

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
      throw Exception('Failed to load AniList dashboard data: $e');
    }
  }

  // Fetch detailed information for a single anime
  Future<Map<String, dynamic>> fetchAnimeDetails(int id) async {
    const query = r'''
      query($id: Int) {
        Media(id: $id, type: ANIME) {
          id
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
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'query': query,
          'variables': variables,
        }),
      );

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
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'query': query,
          'variables': variables,
        }),
      );

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
          }
        }
      }
    ''';

    final variables = {
      'ids': ids,
      'type': type,
    };

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'query': query,
          'variables': variables,
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['data'] != null && body['data']['Page'] != null) {
          return body['data']['Page']['media'] as List<dynamic>;
        }
        throw Exception('GraphQL error: ${body['errors']}');
      } else {
        throw Exception('HTTP Request failed with status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load AniList multiple media ($ids): $e');
    }
  }

  // Fetch airing schedule within a time range (Epoch seconds)
  Future<List<dynamic>> fetchAiringSchedule(int startTimestamp, int endTimestamp) async {
    List<dynamic> allSchedules = [];
    int page = 1;
    bool hasNextPage = true;

    const query = r'''
      query($start: Int, $end: Int, $page: Int) {
        Page(page: $page, perPage: 100) {
          pageInfo {
            hasNextPage
          }
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

    while (hasNextPage) {
      final variables = {
        'start': startTimestamp,
        'end': endTimestamp,
        'page': page,
      };

      try {
        final response = await http.post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'query': query,
            'variables': variables,
          }),
        );

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          if (body['data'] != null && body['data']['Page'] != null) {
            final pageData = body['data']['Page'];
            final schedules = pageData['airingSchedules'] as List<dynamic>;
            allSchedules.addAll(schedules);
            hasNextPage = pageData['pageInfo']['hasNextPage'] == true;
            page++;
            if (page > 10) break; // Avoid infinite loops
          } else {
            throw Exception('GraphQL error: ${body['errors']}');
          }
        } else {
          throw Exception('HTTP Request failed with status: ${response.statusCode}');
        }
      } catch (e) {
        throw Exception('Failed to load airing schedules: $e');
      }
    }

    return allSchedules;
  }
}
