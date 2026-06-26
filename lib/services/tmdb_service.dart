import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class TmdbSeasonInfo {
  final int seasonNumber;
  final int episodeCount;

  TmdbSeasonInfo({required this.seasonNumber, required this.episodeCount});
}

class TmdbService {
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  // Memory caches
  final Map<String, int?> _showIdCache = {};
  final Map<int, List<TmdbSeasonInfo>> _seasonsInfoCache = {};
  final Map<String, Map<int, Map<String, dynamic>>> _seasonEpisodesCache = {};

  // Check if API key is configured
  bool get isConfigured => tmdbApiKey.isNotEmpty;

  // Search TMDB for a show/movie and return its ID
  Future<int?> searchShow(String title, {int? year, required String format}) async {
    if (!isConfigured) return null;

    final isMovie = format.toUpperCase() == 'MOVIE';
    final cacheKey = '${title.toLowerCase()}_${year ?? 0}_$format';
    if (_showIdCache.containsKey(cacheKey)) {
      return _showIdCache[cacheKey];
    }

    try {
      int? id;
      
      // Step 1: Search with year filter if provided
      if (year != null) {
        id = await _performSearch(title, isMovie: isMovie, year: year);
      }

      // Step 2: Fallback to searching without year filter if no results
      id ??= await _performSearch(title, isMovie: isMovie);

      _showIdCache[cacheKey] = id;
      return id;
    } catch (e) {
      debugPrint('TMDB Service searchShow error: $e');
      return null;
    }
  }

  Future<int?> _performSearch(String title, {required bool isMovie, int? year}) async {
    final searchType = isMovie ? 'movie' : 'tv';
    final yearParam = year != null 
        ? (isMovie ? '&year=$year' : '&first_air_date_year=$year') 
        : '';
    final url = '$_baseUrl/search/$searchType?api_key=$tmdbApiKey&query=${Uri.encodeComponent(title)}$yearParam';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final results = data['results'] as List?;
      if (results != null && results.isNotEmpty) {
        return results[0]['id'] as int?;
      }
    }
    return null;
  }

  // Fetch season information for a TV show (list of seasons with episode counts)
  Future<List<TmdbSeasonInfo>> fetchTvSeasons(int tvShowId) async {
    if (!isConfigured) return [];
    if (_seasonsInfoCache.containsKey(tvShowId)) {
      return _seasonsInfoCache[tvShowId]!;
    }

    try {
      final url = '$_baseUrl/tv/$tvShowId?api_key=$tmdbApiKey';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final seasonsList = data['seasons'] as List?;
        final List<TmdbSeasonInfo> seasons = [];
        if (seasonsList != null) {
          for (var item in seasonsList) {
            final seasonNum = item['season_number'] as int? ?? 0;
            final epCount = item['episode_count'] as int? ?? 0;
            // Skip season 0 (Specials/Extras)
            if (seasonNum > 0 && epCount > 0) {
              seasons.add(TmdbSeasonInfo(
                seasonNumber: seasonNum,
                episodeCount: epCount,
              ));
            }
          }
        }
        // Sort seasons by season number
        seasons.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
        _seasonsInfoCache[tvShowId] = seasons;
        return seasons;
      }
    } catch (e) {
      debugPrint('TMDB Service fetchTvSeasons error: $e');
    }
    return [];
  }

  // Fetch details for a specific season, returning mapped episodes by episode_number
  Future<Map<int, Map<String, dynamic>>> fetchSeasonEpisodes(int tvShowId, int seasonNumber) async {
    if (!isConfigured) return {};
    final cacheKey = '${tvShowId}_$seasonNumber';
    if (_seasonEpisodesCache.containsKey(cacheKey)) {
      return _seasonEpisodesCache[cacheKey]!;
    }

    try {
      final url = '$_baseUrl/tv/$tvShowId/season/$seasonNumber?api_key=$tmdbApiKey';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final episodesList = data['episodes'] as List?;
        final Map<int, Map<String, dynamic>> episodesMap = {};
        if (episodesList != null) {
          for (var ep in episodesList) {
            final epNum = ep['episode_number'] as int?;
            if (epNum != null) {
              episodesMap[epNum] = {
                'name': ep['name'] ?? '',
                'overview': ep['overview'] ?? '',
                'still_path': ep['still_path'] != null 
                    ? 'https://image.tmdb.org/t/p/w300${ep['still_path']}' 
                    : '',
                'air_date': ep['air_date'] ?? '',
              };
            }
          }
        }
        _seasonEpisodesCache[cacheKey] = episodesMap;
        return episodesMap;
      }
    } catch (e) {
      debugPrint('TMDB Service fetchSeasonEpisodes error: $e');
    }
    return {};
  }

  // Fetch movie details to use as a fallback single episode
  Future<Map<String, dynamic>?> fetchMovieDetails(int movieId) async {
    if (!isConfigured) return null;
    try {
      final url = '$_baseUrl/movie/$movieId?api_key=$tmdbApiKey';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'name': data['title'] ?? '',
          'overview': data['overview'] ?? '',
          'still_path': data['backdrop_path'] != null 
              ? 'https://image.tmdb.org/t/p/w500${data['backdrop_path']}' 
              : (data['poster_path'] != null ? 'https://image.tmdb.org/t/p/w300${data['poster_path']}' : ''),
          'air_date': data['release_date'] ?? '',
        };
      }
    } catch (e) {
      debugPrint('TMDB Service fetchMovieDetails error: $e');
    }
    return null;
  }

  // Search and discover movies and tv shows with filter options
  Future<List<dynamic>> searchAndDiscover({
    required String query,
    int? year,
    String? format, // 'MOVIE' or 'TV'
    List<int>? genres,
    String? sortBy, // 'popularity.desc', 'vote_average.desc', 'release_date.desc'
  }) async {
    if (!isConfigured) return [];
    try {
      if (query.trim().isNotEmpty) {
        // Search API
        final searchType = (format == 'MOVIE') ? 'movie' : ((format == 'TV') ? 'tv' : 'multi');
        final yearParam = year != null 
            ? ((searchType == 'movie') ? '&year=$year' : ((searchType == 'tv') ? '&first_air_date_year=$year' : '')) 
            : '';
        final url = '$_baseUrl/search/$searchType?api_key=$tmdbApiKey&query=${Uri.encodeComponent(query)}$yearParam';
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final results = data['results'] as List? ?? [];
          
          return results.map((item) {
            final isMovieType = item['media_type'] == 'movie' || format == 'MOVIE';
            return {
              'id': item['id'],
              'title': item[isMovieType ? 'title' : 'name'] ?? 'Untitled',
              'coverImage': {
                'large': item['poster_path'] != null 
                    ? 'https://image.tmdb.org/t/p/w300${item['poster_path']}' 
                    : '',
              },
              'averageScore': (item['vote_average'] as num?)?.toDouble() != null 
                  ? ((item['vote_average'] as num).toDouble() * 10).toInt()
                  : null,
              'format': isMovieType ? 'MOVIE' : 'TV',
            };
          }).toList();
        }
      } else {
        // Discover API
        final searchType = (format == 'TV') ? 'tv' : 'movie';
        final yearParam = year != null 
            ? ((searchType == 'movie') ? '&primary_release_year=$year' : '&first_air_date_year=$year') 
            : '';
        final genreParam = (genres != null && genres.isNotEmpty) 
            ? '&with_genres=${genres.join(',')}' 
            : '';
        final sortParam = sortBy != null ? '&sort_by=$sortBy' : '&sort_by=popularity.desc';
        
        final url = '$_baseUrl/discover/$searchType?api_key=$tmdbApiKey$yearParam$genreParam$sortParam';
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final results = data['results'] as List? ?? [];
          
          return results.map((item) {
            final isMovieType = searchType == 'movie';
            return {
              'id': item['id'],
              'title': item[isMovieType ? 'title' : 'name'] ?? 'Untitled',
              'coverImage': {
                'large': item['poster_path'] != null 
                    ? 'https://image.tmdb.org/t/p/w300${item['poster_path']}' 
                    : '',
              },
              'averageScore': (item['vote_average'] as num?)?.toDouble() != null 
                  ? ((item['vote_average'] as num).toDouble() * 10).toInt() 
                  : null,
              'format': isMovieType ? 'MOVIE' : 'TV',
            };
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('TMDB Service searchAndDiscover error: $e');
    }
    return [];
  }
}
