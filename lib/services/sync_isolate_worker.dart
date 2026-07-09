import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Input payload sent from the main thread to initiate a sync
class SyncRequest {
  final List<int> animeIds;
  final List<int> mangaIds;
  final List<int> movieIds;
  final String suwayomiBaseUrl;

  SyncRequest({
    required this.animeIds,
    required this.mangaIds,
    required this.movieIds,
    required this.suwayomiBaseUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'animeIds': animeIds,
      'mangaIds': mangaIds,
      'movieIds': movieIds,
      'suwayomiBaseUrl': suwayomiBaseUrl,
    };
  }

  factory SyncRequest.fromJson(Map<String, dynamic> json) {
    return SyncRequest(
      animeIds: List<int>.from(json['animeIds']),
      mangaIds: List<int>.from(json['mangaIds']),
      movieIds: List<int>.from(json['movieIds']),
      suwayomiBaseUrl: json['suwayomiBaseUrl'] ?? '',
    );
  }
}

/// Output payload sent back from the isolate to the main thread
class SyncResponse {
  final Map<int, int> animeLatestReleased;
  final Map<int, int> mangaLatestReleased;
  final Map<int, int> movieLatestReleased;
  final Map<int, Map<String, dynamic>> freshAnimeDetails;

  SyncResponse({
    required this.animeLatestReleased,
    required this.mangaLatestReleased,
    required this.movieLatestReleased,
    required this.freshAnimeDetails,
  });

  Map<String, dynamic> toJson() {
    return {
      'animeLatestReleased': animeLatestReleased.map((k, v) => MapEntry(k.toString(), v)),
      'mangaLatestReleased': mangaLatestReleased.map((k, v) => MapEntry(k.toString(), v)),
      'movieLatestReleased': movieLatestReleased.map((k, v) => MapEntry(k.toString(), v)),
      'freshAnimeDetails': freshAnimeDetails.map((k, v) => MapEntry(k.toString(), v)),
    };
  }

  factory SyncResponse.fromJson(Map<String, dynamic> json) {
    final animeLatest = (json['animeLatestReleased'] as Map).map((k, v) => MapEntry(int.parse(k.toString()), v as int));
    final mangaLatest = (json['mangaLatestReleased'] as Map).map((k, v) => MapEntry(int.parse(k.toString()), v as int));
    final movieLatest = (json['movieLatestReleased'] as Map).map((k, v) => MapEntry(int.parse(k.toString()), v as int));
    final freshAnime = (json['freshAnimeDetails'] as Map).map((k, v) => MapEntry(int.parse(k.toString()), Map<String, dynamic>.from(v as Map)));
    return SyncResponse(
      animeLatestReleased: animeLatest,
      mangaLatestReleased: mangaLatest,
      movieLatestReleased: movieLatest,
      freshAnimeDetails: freshAnime,
    );
  }
}

/// Persistent background worker that runs network calls and JSON decoding inside a Dart isolate.
class SyncIsolateWorker {
  static final SyncIsolateWorker _instance = SyncIsolateWorker._internal();
  factory SyncIsolateWorker() => _instance;
  SyncIsolateWorker._internal();

  Isolate? _isolate;
  SendPort? _sendPort;
  final _receivePort = ReceivePort();
  bool _isInitialized = false;

  Completer<SyncResponse>? _syncCompleter;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    _isolate = await Isolate.spawn(_isolateEntryPoint, _receivePort.sendPort);
    
    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
      } else if (message is String) {
        final Map<String, dynamic> decoded = jsonDecode(message);
        if (decoded.containsKey('error')) {
          _syncCompleter?.completeError(Exception(decoded['error']));
        } else {
          _syncCompleter?.complete(SyncResponse.fromJson(decoded));
        }
      }
    });
  }

  Future<SyncResponse> performSync(SyncRequest request) async {
    await init();
    if (_sendPort == null) {
      // Bounded wait for isolate ready signal
      for (int i = 0; i < 20; i++) {
        if (_sendPort != null) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_sendPort == null) {
        throw Exception("SyncIsolateWorker failed to initialize background isolate port.");
      }
    }

    _syncCompleter = Completer<SyncResponse>();
    _sendPort!.send(jsonEncode(request.toJson()));
    return _syncCompleter!.future;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _receivePort.close();
    _isInitialized = false;
  }
}

/// Isolate entry point - executes on a separate Dart execution thread (independent memory stack)
void _isolateEntryPoint(SendPort mainSendPort) {
  final isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort);

  isolateReceivePort.listen((message) async {
    if (message is String) {
      try {
        final request = SyncRequest.fromJson(jsonDecode(message));
        final response = await _executeBackgroundSync(request);
        mainSendPort.send(jsonEncode(response.toJson()));
      } catch (e) {
        mainSendPort.send(jsonEncode({'error': e.toString()}));
      }
    }
  });
}

Future<SyncResponse> _executeBackgroundSync(SyncRequest request) async {
  final animeLatest = <int, int>{};
  final mangaLatest = <int, int>{};
  final movieLatest = <int, int>{};
  final freshAnime = <int, Map<String, dynamic>>{};

  // 1. Sync Manga via local Suwayomi server if configured
  if (request.mangaIds.isNotEmpty && request.suwayomiBaseUrl.isNotEmpty) {
    try {
      final response = await http.get(
        Uri.parse('${request.suwayomiBaseUrl}/api/v1/manga'),
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        for (var m in list) {
          final int? id = m['id'];
          final int? chapters = m['chapters'];
          if (id != null && chapters != null && request.mangaIds.contains(id)) {
            mangaLatest[id] = chapters;
          }
        }
      }
    } catch (_) {}
  }

  // 2. Sync Movies / Series via Cinemeta
  if (request.movieIds.isNotEmpty) {
    final futures = request.movieIds.map((id) async {
      final imdbId = 'tt${id.toString().padLeft(7, '0')}';
      final url = 'https://v3-cinemeta.strem.io/meta/series/$imdbId.json';
      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final videos = decoded['meta']?['videos'] as List? ?? [];
          movieLatest[id] = videos.length;
        }
      } catch (_) {}
    });
    await Future.wait(futures);
  }

  // 3. Sync Anime via AniList GraphQL
  if (request.animeIds.isNotEmpty) {
    // We batch query in chunks of 50 to avoid network request storms and AniList rate limits!
    const chunkSize = 50;
    for (var i = 0; i < request.animeIds.length; i += chunkSize) {
      final chunk = request.animeIds.sublist(
        i,
        i + chunkSize > request.animeIds.length ? request.animeIds.length : i + chunkSize,
      );

      final query = '''
      query (\$ids: [Int]) {
        Page(page: 1, perPage: 50) {
          media(id_in: \$ids, type: ANIME) {
            id
            status
            episodes
            bannerImage
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            nextAiringEpisode {
              episode
            }
          }
        }
      }
      ''';

      try {
        final response = await http.post(
          Uri.parse('https://graphql.anilist.co'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'query': query,
            'variables': {'ids': chunk},
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);
          final List<dynamic> mediaList = data['data']?['Page']?['media'] ?? [];
          for (var media in mediaList) {
            final int? id = media['id'];
            if (id != null) {
              final int? nextEpisode = media['nextAiringEpisode']?['episode'];
              final int totalEpisodes = media['episodes'] ?? 0;
              final int latestReleased = nextEpisode != null ? (nextEpisode - 1) : totalEpisodes;
              animeLatest[id] = latestReleased;
              freshAnime[id] = Map<String, dynamic>.from(media);
            }
          }
        }
      } catch (_) {}
    }
  }

  return SyncResponse(
    animeLatestReleased: animeLatest,
    mangaLatestReleased: mangaLatest,
    movieLatestReleased: movieLatest,
    freshAnimeDetails: freshAnime,
  );
}
