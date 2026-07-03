import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;

class SkipInterval {
  final double startTime;
  final double endTime;
  final String skipType; // 'op', 'ed', 'recap', etc.

  SkipInterval({
    required this.startTime,
    required this.endTime,
    required this.skipType,
  });

  factory SkipInterval.fromJson(Map<String, dynamic> json) {
    final interval = json['interval'] as Map<String, dynamic>;
    return SkipInterval(
      startTime: (interval['startTime'] as num).toDouble(),
      endTime: (interval['endTime'] as num).toDouble(),
      skipType: json['skipType'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'startTime': startTime,
    'endTime': endTime,
    'skipType': skipType,
  };
}

class AniSkipService {
  static final AniSkipService _instance = AniSkipService._internal();
  factory AniSkipService() => _instance;
  AniSkipService._internal();

  // Cache: key is anilistId, value is malId
  final Map<int, int> _malIdCache = {};

  Future<int?> _fetchMalId(int anilistId) async {
    if (_malIdCache.containsKey(anilistId)) {
      return _malIdCache[anilistId];
    }
    final url = Uri.parse('https://api.ani.zip/mappings?anilist_id=$anilistId');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final malId = data['mappings']?['mal_id'];
        if (malId != null) {
          final mappedId = (malId as num).toInt();
          _malIdCache[anilistId] = mappedId;
          return mappedId;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<SkipInterval>> fetchSkipTimes({
    required int anilistId,
    required int episodeNumber,
    required double episodeLength,
  }) async {
    if (episodeLength <= 0) return [];

    // Fetch MAL ID from AniList ID
    final malId = await _fetchMalId(anilistId);
    if (malId == null) {
      developer.log(
        'Could not map AniList ID $anilistId to MyAnimeList ID',
        name: 'watchAny.AniSkipService',
      );
      return [];
    }

    final url = Uri.parse(
      'https://api.aniskip.com/v2/skip-times/$malId/$episodeNumber'
      '?types[]=op&types[]=ed&types[]=mixed-op&types[]=mixed-ed&types[]=recap'
      '&episodeLength=${episodeLength.round()}',
    );

    developer.log(
      'Fetching skip times for MAL $malId (AniList $anilistId), Ep $episodeNumber, Length ${episodeLength.round()}s',
      name: 'watchAny.AniSkipService',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['found'] == true) {
          final results = data['results'] as List<dynamic>? ?? [];
          final intervals = results.map((r) => SkipInterval.fromJson(r)).toList();
          developer.log(
            'Found ${intervals.length} skip intervals for MAL $malId',
            name: 'watchAny.AniSkipService',
          );
          return intervals;
        }
      } else {
        developer.log(
          'API request failed with status: ${response.statusCode}',
          name: 'watchAny.AniSkipService',
        );
      }
    } catch (e) {
      developer.log(
        'Failed to fetch skip times: $e',
        name: 'watchAny.AniSkipService',
        error: e,
      );
    }
    return [];
  }
}
