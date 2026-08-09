import '../services/notification_service.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../state/navigation_state.dart';
import '../services/stremio_addon_service.dart';
import '../state/player_state.dart';
import '../state/library_state.dart';
import 'player_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/extension_service.dart';
import '../widgets/torrent_selector_panel.dart';
import '../widgets/movie_stream_selector_panel.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/smooth_scroll_area.dart';
import '../widgets/poster_image_viewer.dart';
import '../services/batch_mapping_service.dart';
import '../services/torrserver_service.dart';
import '../services/torrserver_manager.dart';
import '../models/torrent.dart';
import '../services/watch_together_service.dart';
import '../widgets/watch_together_dialog.dart';
import 'watch_together_room_screen.dart';
import '../services/download_service.dart';

// ─── Lightweight metadata cache (populated on home page card tap) ─────────────
class MovieMetadataCache {
  static final Map<String, Map<String, dynamic>> placeholders = {};
}

// ─── Details Page ─────────────────────────────────────────────────────────────

class MovieDetailsPage extends StatefulWidget {
  /// Format: "type:id" — e.g. "movie:tt11378946" or "series:kitsu:47"
  final String movieId;
  final NavigationState navigationState;

  const MovieDetailsPage({
    super.key,
    required this.movieId,
    required this.navigationState,
  });

  @override
  State<MovieDetailsPage> createState() => _MovieDetailsPageState();
}

class _MovieDetailsPageState extends State<MovieDetailsPage> {
  bool _isLoading = true;
  String _error = '';
  Map<String, dynamic> _meta = {};

  String _type = 'movie';
  String _realId = '';

  int _selectedSeason = 1;
  List<int> _seasons = [];
  Map<int, List<dynamic>> _episodesBySeason = {};

  int _continueEpisode = 1;
  bool _continueEpisodeFinished = false;
  String? _continueStreamUrl;
  String? _continueStreamTitle;
  bool _hasCheckedContinue = false;

  @override
  void initState() {
    super.initState();
    _parseId();

    // Instantly populate from cache so the UI shows something immediately
    final cached =
        MovieMetadataCache.placeholders[_realId] ?? MovieMetadataCache.placeholders[widget.movieId];
    if (cached != null) {
      _meta = Map<String, dynamic>.from(cached);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadMetadata();
      }
    });
  }

  /// Splits "type:id" into (_type, _realId).
  /// Handles multi-colon IDs like "series:kitsu:47"
  void _parseId() {
    final firstColon = widget.movieId.indexOf(':');
    if (firstColon > 0) {
      final possibleType = widget.movieId.substring(0, firstColon);
      if (possibleType == 'movie' || possibleType == 'series' || possibleType == 'anime' || possibleType == 'tv' || possibleType == 'channel') {
        _type = possibleType;
        _realId = widget.movieId.substring(firstColon + 1);
        return;
      }
    }
    _type = 'movie';
    _realId = widget.movieId;
  }

  bool get _hasVideos => _meta['videos'] is List && (_meta['videos'] as List).isNotEmpty;
  bool get _isSeries => _type == 'series' || _type == 'tv' || (_meta.isNotEmpty && _meta['type']?.toString().toLowerCase() == 'series');

  // ── Metadata Loading ──────────────────────────────────────────────────────

  Future<void> _loadMetadata() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = _meta.isEmpty; // Only show spinner if we have no placeholder data
        _error = '';
      });

      final addonService = StremioAddonService();
      await addonService.init();

      Map<String, dynamic>? metaData;

      // 1. Query all installed meta-capable addons in parallel, with ID prefix filtering
      final metaAddons = addonService.metaAddons;
      final metaFutures = <Future<Map<String, dynamic>?>>[];

      for (final addon in metaAddons) {
        if (!addon.matchesId(_realId)) continue;
        if (!addon.supportsType(_type) && addon.types.isNotEmpty) continue;

        metaFutures.add(() async {
          try {
            final url = '${addon.baseUrl}/meta/$_type/$_realId.json';
            final response =
                await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
            if (response.statusCode == 200) {
              final body = jsonDecode(response.body);
              if (body['meta'] is Map) {
                return Map<String, dynamic>.from(body['meta']);
              }
            }
          } catch (e, stack) {
            developer.log('Error fetching meta from ${addon.name}', name: 'MovieDetailsPage', error: e, stackTrace: stack);
          }
          return null;
        }());
      }

      if (metaFutures.isNotEmpty) {
        final results = await Future.wait(metaFutures);
        for (final r in results) {
          if (r != null) {
            metaData = r;
            break;
          }
        }
      }

      // 2. Fallback: query Cinemeta for mainstream IMDB IDs
      if (metaData == null && (_type == 'movie' || _type == 'series') && _realId.startsWith('tt')) {
        try {
          final url = 'https://v3-cinemeta.strem.io/meta/$_type/$_realId.json';
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            if (body['meta'] is Map) {
              metaData = Map<String, dynamic>.from(body['meta']);
            }
          }
        } catch (e, stack) {
          developer.log('Cinemeta fallback failed', name: 'MovieDetailsPage', error: e, stackTrace: stack);
        }
      }

      // 3. Fall back to SQLite movieCache first if bookmarked
      if (metaData == null) {
        final libId = _imdbToLibraryId(_realId);
        final cachedMovie = LibraryState().movieCache[libId];
        if (cachedMovie != null) {
          metaData = Map<String, dynamic>.from(cachedMovie);
        }
      }

      // 4. Fall back to placeholder cache
      if (metaData == null && _meta.isNotEmpty) {
        metaData = Map<String, dynamic>.from(_meta);
      }

      if (metaData == null) {
        if (mounted) {
          setState(() {
            _error = 'Could not load details for this title.\nCheck your addon settings or internet connection.';
            _isLoading = false;
          });
        }
        return;
      }

      // Safeguard: if fetched metadata is missing name/title/poster, retrieve them from our cached placeholder
      if (metaData['name'] == null && metaData['title'] == null) {
        if (_meta['name'] != null) metaData['name'] = _meta['name'];
        if (_meta['title'] != null) metaData['title'] = _meta['title'];
      }
      if (metaData['poster'] == null && metaData['coverImage'] == null) {
        if (_meta['poster'] != null) metaData['poster'] = _meta['poster'];
        if (_meta['coverImage'] != null) metaData['coverImage'] = _meta['coverImage'];
      }
      if (metaData['background'] == null && _meta['background'] != null) {
        metaData['background'] = _meta['background'];
      }

      // ── Process videos / episodes ─────────────────────────────────────────

      var videosList = <dynamic>[];
      if (metaData['videos'] is List) {
        videosList = List<dynamic>.from(metaData['videos']);
      }

      // For series with no episodes yet, create a placeholder Episode 1
      if (videosList.isEmpty &&
          (_type == 'series' || (metaData['type']?.toString().toLowerCase() == 'series'))) {
        videosList = [
          {
            'id': '$_realId:1:1',
            'episode': 1,
            'season': 1,
            'title': 'Episode 1',
          }
        ];
        metaData['videos'] = videosList;
      }

      // Build season → episode map
      if (videosList.isNotEmpty) {
        final Map<int, List<dynamic>> grouped = {};
        final Set<int> seasonNums = {};

        for (final video in videosList) {
          int s = int.tryParse(video['season']?.toString() ?? '') ?? 1;
          // Treat season 0 (specials) as season 0 — we label it properly below
          seasonNums.add(s);
          grouped.putIfAbsent(s, () => []).add(video);
        }

        for (final s in grouped.keys) {
          grouped[s]!.sort((a, b) {
            final ae = (a['episode'] as num?)?.toInt() ?? 0;
            final be = (b['episode'] as num?)?.toInt() ?? 0;
            return ae.compareTo(be);
          });
        }

        final sortedSeasons = seasonNums.toList()..sort();
        _seasons = sortedSeasons;
        _episodesBySeason = grouped;
        // Default to first non-zero season if possible
        _selectedSeason = sortedSeasons.firstWhere((s) => s > 0, orElse: () => sortedSeasons.first);
      }

      // ── Save lightweight metadata for continue-watching ───────────────────

      final mediaTitle = metaData['name']?.toString() ??
          metaData['title']?.toString() ??
          'Untitled';
      final lightweightMedia = {
        'id': _realId,
        'title': mediaTitle,
        'coverImage': metaData['poster']?.toString() ?? metaData['coverImage']?.toString() ?? '',
        'averageScore': double.tryParse(metaData['imdbRating']?.toString() ?? '') ?? 0.0,
        'format': _isSeries ? 'SERIES' : 'MOVIE',
        'episodes': _isSeries && videosList.isNotEmpty ? videosList.length : 1,
        'type': _type,
      };

      final prefs = await SharedPreferences.getInstance();
      final compositeId = '$_type:$_realId';
      await prefs.setString('movie_continue_watching_metadata_$compositeId', jsonEncode(lightweightMedia));

      if (mounted) {
        setState(() {
          _meta = metaData!;
          _isLoading = false;
        });

        // Save metadata to library sqlite cache if bookmarked
        final libId = _imdbToLibraryId(_realId);
        if (LibraryState().isSaved(libId, 'movies')) {
          final updatedCache = Map<String, dynamic>.from(metaData);
          updatedCache['format'] = _isSeries ? 'SERIES' : 'MOVIE';
          updatedCache['type'] = _type;
          LibraryState().updateMovieCache(libId, updatedCache);
        }

        await _loadPlaybackProgress();
      }
    } catch (e, stack) {
      developer.log('Unhandled error in _loadMetadata', name: 'MovieDetailsPage', error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _error = 'Error loading metadata: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPlaybackProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final compositeId = '$_type:$_realId';

    final lastEp = prefs.getInt('movie_continue_watching_last_ep_$compositeId') ?? 1;
    final pos = prefs.getInt('movie_playback_pos_${compositeId}_$lastEp');
    final dur = prefs.getInt('movie_playback_dur_${compositeId}_$lastEp');

    int targetEp = lastEp;
    bool finished = false;

    if (pos != null && dur != null && dur > 0) {
      final ratio = pos / dur;
      if (ratio >= 0.90) {
        finished = true;
        // Advance to next episode within the current season
        final currentSeasonEps = _episodesBySeason[_selectedSeason] ?? [];
        final currentIdx =
            currentSeasonEps.indexWhere((v) => (v['episode'] as num?)?.toInt() == lastEp);
        if (currentIdx >= 0 && currentIdx < currentSeasonEps.length - 1) {
          targetEp = (currentSeasonEps[currentIdx + 1]['episode'] as num?)?.toInt() ?? lastEp + 1;
        }
      }
    }

    final savedStream = prefs.getString('playback_stream_${_realId}_$targetEp');
    final savedTitle = prefs.getString('playback_title_${_realId}_$targetEp');

    // Preload all episode progress values
    final allEpNums = <int>[];
    if (_hasVideos) {
      for (final video in _meta['videos'] as List) {
        final n = (video['episode'] as num?)?.toInt() ?? 1;
        allEpNums.add(n);
      }
    } else {
      allEpNums.add(1);
    }
    await PlayerState().loadProgressForAnime(_realId, allEpNums);

    if (mounted) {
      setState(() {
        _continueEpisode = targetEp;
        _continueEpisodeFinished = finished;
        _continueStreamUrl = savedStream;
        _continueStreamTitle = savedTitle;
        _hasCheckedContinue = true;
        _isLoading = false;
      });
    }
  }

  // ── Stream Fetching ───────────────────────────────────────────────────────

  String _getFormattedEpisodeId({String? episodeId, int? episode}) {
    if (_type == 'movie') {
      return _realId;
    }
    if (episodeId != null && episodeId.contains(':') && episodeId.startsWith('tt')) {
      return episodeId;
    }
    final baseId = _realId.replaceAll('series:', '').replaceAll('movie:', '');
    if (baseId.startsWith('tt')) {
      final seasonNum = _selectedSeason;
      final epNum = episode ?? 1;
      return '$baseId:$seasonNum:$epNum';
    }
    if (episodeId != null && episodeId.isNotEmpty) {
      return episodeId;
    }
    return '$baseId:${episode ?? 1}';
  }

  Future<void> _fetchStreamsAndPlay({int? episode, String? episodeId, bool isDownload = false}) async {
    final String mediaId = widget.movieId;
    final int epNum = episode ?? 1;
    final mapping = BatchMappingService().getMapping(mediaId, epNum);
    if (mapping != null) {
      _showBatchMappingPlayDialog(mapping, epNum);
      return;
    }

    final targetId = _getFormattedEpisodeId(episodeId: episodeId, episode: episode);

    // Show loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    final addonService = StremioAddonService();
    final streamAddons = addonService.streamAddons
        .where((a) => a.matchesId(targetId))
        .where((a) => a.supportsType(_type) || a.types.isEmpty)
        .toList();

    final streamFutures = <Future<List<dynamic>>>[];
    for (final addon in streamAddons) {
      streamFutures.add(() async {
        try {
          final url = '${addon.baseUrl}/stream/$_type/$targetId.json';
          final response =
              await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            final List streams = body['streams'] ?? [];
            return streams
                .map((s) => Map<String, dynamic>.from(s as Map)
                  ..['addonName'] = addon.name)
                .toList();
          }
        } catch (e, stack) {
          developer.log('Error fetching stream from ${addon.name}', name: 'MovieDetailsPage', error: e, stackTrace: stack);
        }
        return [];
      }());
    }

    final allStreams = <dynamic>[];
    if (streamFutures.isNotEmpty) {
      final results = await Future.wait(streamFutures);
      for (final r in results) {
        allStreams.addAll(r);
      }
    }

    if (mounted) Navigator.pop(context);

    if (allStreams.isEmpty) {
      if (mounted) {
        NotificationService().show(context, 'No streams found. Install a stream addon like Torrentio.');
      }
      return;
    }

    if (mounted) _showStreamSheet(allStreams, episode, isDownload: isDownload);
  }

  // ── Stream Selector Bottom Sheet ──────────────────────────────────────────

  void _showStreamSheet(List<dynamic> streams, int? episode, {bool isDownload = false}) {
    final mediaTitle = _meta['name']?.toString() ?? _meta['title']?.toString() ?? 'Media';
    final panelTitle = episode != null ? '$mediaTitle — Episode $episode' : mediaTitle;

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobileSheet = screenWidth < 650;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: isMobileSheet ? double.infinity : 800.0,
            height: MediaQuery.of(context).size.height * (isMobileSheet ? 0.8 : 0.65),
            margin: isMobileSheet
                ? EdgeInsets.zero
                : const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C0E),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
              border: Border.all(color: Colors.white10, width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black87,
                  blurRadius: 30,
                  spreadRadius: 2,
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15.0)),
              child: MovieStreamSelectorPanel(
                streams: streams,
                title: panelTitle,
                onStreamSelected: (stream, {bool isDownload = false}) {
                  Navigator.pop(context); // close bottom sheet
                  _playStream(stream, episode, isDownload: isDownload);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  void _playStream(dynamic rawStream, int? episode, {bool isDownload = false}) {
    var stream = rawStream;
    if (stream is Map) {
      final map = Map<String, dynamic>.from(stream);
      final String? url = map['url']?.toString();
      if (map['infoHash'] == null && url != null && url.startsWith('magnet:')) {
        final match = RegExp(r'urn:btih:([a-zA-Z0-9]+)', caseSensitive: false).firstMatch(url);
        if (match != null) {
          map['infoHash'] = match.group(1);
        }
      }
      stream = map;
    }

    final mediaTitle =
        _meta['name']?.toString() ?? _meta['title']?.toString() ?? 'Media';
    final poster = _meta['poster']?.toString() ?? _meta['coverImage']?.toString() ?? '';
    final rating = double.tryParse(_meta['imdbRating']?.toString() ?? '') ?? 0.0;
    final epCount = _isSeries && _hasVideos ? (_meta['videos'] as List).length : 1;

    final media = {
      'id': _realId,
      'stremioId': _realId,
      'title': mediaTitle,
      'coverImage': poster,
      'averageScore': rating,
      'format': _isSeries ? 'SERIES' : 'MOVIE',
      'episodes': epCount,
      'type': _type,
    };

    // Torrent stream (via infoHash) — route through TorrServer / PlaybackProgressDialog
    if (stream['infoHash'] != null) {
      final String hash = stream['infoHash'].toString();
      final String streamTitle = stream['title']?.toString() ?? stream['name']?.toString() ?? '';
      final int seeders = _parseSeeders(stream);
      final int sizeBytes = _parseSize(stream);

      final List<dynamic>? sources = stream['sources'] as List?;
      String magnetLink = 'magnet:?xt=urn:btih:$hash';
      final List<String> trackers = [];
      if (sources != null && sources.isNotEmpty) {
        for (final src in sources) {
          final s = src.toString();
          if (s.startsWith('tracker:')) {
            trackers.add(s.replaceFirst('tracker:', ''));
          } else if (!s.startsWith('dht:')) {
            trackers.add(s);
          }
        }
      }
      if (trackers.isEmpty) {
        trackers.addAll([
          'udp://tracker.coppersurfer.tk:6969/announce',
          'udp://tracker.openittracker.com:80/announce',
          'udp://tracker.opentrackr.org:1337/announce',
          'udp://explodie.org:6969/announce',
          'udp://9.rarbg.to:2710/announce',
          'udp://9.rarbg.me:2780/announce',
          'udp://open.stealth.si:80/announce',
          'udp://tracker.torrent.eu.org:451/announce',
          'udp://opentracker.i2p.rocks:6969/announce',
        ]);
      }
      for (final tr in trackers) {
        magnetLink += '&tr=${Uri.encodeComponent(tr)}';
      }

      final torrentStream = TorrentStream(
        title: streamTitle.isNotEmpty ? streamTitle : mediaTitle,
        link: magnetLink,
        seeders: seeders,
        leechers: 0,
        downloads: 0,
        hash: hash,
        size: sizeBytes,
        accuracy: 'high',
        type: _type,
        extensionName: stream['addonName']?.toString() ?? 'Stremio Addon',
      );

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => PlaybackProgressDialog(
          stream: torrentStream,
          parentContext: context,
          anilistId: null, // Not an AniList item
          movieId: '$_type:$_realId',
          episodeNumber: episode ?? 1,
          titles: [mediaTitle],
          episodeCount: epCount,
          isMovie: !_isSeries,
          media: media,
          episodes: _isSeries && _hasVideos ? _meta['videos'] : null,
          isDownload: isDownload,
          season: _selectedSeason,
        ),
      );
      return;
    }

    // Direct URL stream
    final String streamUrl = stream['url']?.toString() ?? '';
    if (streamUrl.isEmpty) {
      NotificationService().show(context, 'This stream has no playable URL or hash.');
      return;
    }

    Map<String, String>? headers;
    if (stream['behaviorHints'] is Map) {
      final bh = stream['behaviorHints'] as Map;
      if (bh['proxyHeaders'] is Map && bh['proxyHeaders']['request'] is Map) {
        headers = (bh['proxyHeaders']['request'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
      } else if (bh['headers'] is Map) {
        headers = (bh['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    }
    if (headers == null && stream['headers'] is Map) {
      headers = (stream['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    if (isDownload) {
      final taskTitle = episode != null ? '$mediaTitle — Episode $episode' : mediaTitle;
      DownloadService().addDownloadTask(
        hash: 'mov_${streamUrl.hashCode}_${episode ?? 1}',
        fileIndex: episode ?? 1,
        title: taskTitle,
        streamUrl: streamUrl,
        episodeNumber: episode,
        season: _selectedSeason,
        isMovie: !_isSeries,
        mediaJson: jsonEncode(media),
        episodesJson: _isSeries && _hasVideos ? jsonEncode(_meta['videos']) : null,
        headers: headers,
      );
      NotificationService().show(context, 'Added "$taskTitle" to download queue.');
      return;
    }

    PlayerState().startPlayback(
      streamUrl: streamUrl,
      title: episode != null ? '$mediaTitle — Episode $episode' : mediaTitle,
      movieId: '$_type:$_realId',
      episodeNumber: episode ?? 1,
      isMovie: !_isSeries,
      media: media,
      episodes: _isSeries && _hasVideos ? _meta['videos'] : null,
      titles: [mediaTitle],
      headers: headers,
    );
  }

  // ── Stream parsing helpers ─────────────────────────────────────────────────

  int _parseSeeders(dynamic stream) {
    if (stream['seeders'] != null) {
      return int.tryParse(stream['seeders'].toString()) ?? 0;
    }
    final t = stream['title']?.toString() ?? stream['description']?.toString() ?? '';
    final m = RegExp(r'(?:👤|seeders?:?)\s*(\d+)', caseSensitive: false).firstMatch(t);
    return m != null ? (int.tryParse(m.group(1)!) ?? 0) : 0;
  }

  int _parseSize(dynamic stream) {
    if (stream['size'] != null) {
      return int.tryParse(stream['size'].toString()) ?? 0;
    }
    return 0;
  }

  /// Converts any Stremio string ID to a stable non-zero int for LibraryItem.id
  /// scoped under mode='movies' (won't conflict with AniList IDs which use mode='anime').
  int _imdbToLibraryId(String id) {
    if (id.isEmpty) return 0;
    // For tt-ids: extract digit string (e.g. tt11378946 -> 11378946)
    final digits = RegExp(r'\d+').allMatches(id).map((m) => m.group(0)!).join();
    final n = int.tryParse(digits);
    if (n != null && n > 0) return n;
    // For non-numeric IDs (e.g. kitsu:47): use hashCode
    return id.hashCode.abs();
  }

  // ── UI Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // If loading and we have NO placeholder data — show full-screen spinner
    if (_isLoading && _meta.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
        ),
      );
    }

    if (_error.isNotEmpty && _meta.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 48.0),
                const SizedBox(height: 16.0),
                Text(
                  _error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14.0),
                ),
                const SizedBox(height: 24.0),
                ElevatedButton(
                  onPressed: _loadMetadata,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    developer.log('build: movieId=$widget.movieId, title=${_meta["name"] ?? _meta["title"] ?? "Untitled"}', name: 'MovieDetailsPage');

    final background =
        _meta['background']?.toString() ?? _meta['poster']?.toString() ?? _meta['coverImage']?.toString() ?? '';
    final poster = _meta['poster']?.toString() ?? _meta['coverImage']?.toString() ?? '';
    final title = _meta['name']?.toString() ?? _meta['title']?.toString() ?? 'Untitled';
    final description = _meta['description']?.toString() ?? '';
    final rating = _meta['imdbRating']?.toString();
    final releaseInfo = _meta['releaseInfo']?.toString();
    final runtime = _meta['runtime']?.toString();
    final List<dynamic> genres = _meta['genres'] is List ? _meta['genres'] : [];

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: LibraryState(),
        builder: (context, _) {
          // Use IMDB digits as int library key, scoped to mode='movies'
          // to avoid collision with AniList IDs (which use a separate mode)
          final libId = _imdbToLibraryId(_realId);
          final isBookmarked =
              LibraryState().items.any((i) => i.id == libId && i.mode == 'movies');

          return SmoothScrollArea(
            builder: (controller, physics) => SingleChildScrollView(
              controller: controller,
              physics: physics,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // 1. Header Banner
                _buildBanner(
                  background: background,
                  poster: poster,
                  title: title,
                  rating: rating,
                  releaseInfo: releaseInfo,
                  runtime: runtime,
                  genres: genres,
                  isBookmarked: isBookmarked,
                  onBookmarkToggle: () {
                    final savedItem = LibraryState().getItem(libId, 'movies');
                    final totalEps = _isSeries && _hasVideos
                        ? (_meta['videos'] is List ? (_meta['videos'] as List).length : 0)
                        : 1;
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _MovieLibraryEditPanel(
                        libId: libId,
                        mediaTitle: title,
                        format: _isSeries ? 'SERIES' : 'MOVIE',
                        savedItem: savedItem,
                        totalEpisodes: totalEps,
                        hasSeasons: _isSeries && _hasVideos && _seasons.isNotEmpty,
                        seasons: _seasons,
                        episodesBySeason: _episodesBySeason,
                        metaData: _meta,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24.0),

                // 2. Actions + Synopsis
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPlayButton(title: title, poster: poster, rating: rating),
                      const SizedBox(height: 20.0),
                      if (description.isNotEmpty) ...[
                        const Text(
                          'Synopsis',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.0,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 6.0),
                        Text(
                          description,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14.0, height: 1.45),
                        ),
                      ],
                    ],
                  ),
                ),

                _buildDetailsSection(),

                // 3. Episodes Section (TV only)
                if (_isSeries) _buildEpisodesSection(),

                const SizedBox(height: 64.0),
              ],
            ),
          ),
          );
        },
      ),
    );
  }

  Widget _buildBanner({
    required String background,
    required String poster,
    required String title,
    required String? rating,
    required String? releaseInfo,
    required String? runtime,
    required List<dynamic> genres,
    required bool isBookmarked,
    required VoidCallback onBookmarkToggle,
  }) {
    return Stack(
      children: [
        // Backdrop
        Container(
          height: 380.0,
          width: double.infinity,
          decoration: BoxDecoration(
            image: background.isNotEmpty
                ? DecorationImage(
                    image: CachedNetworkImageProvider(background), fit: BoxFit.cover)
                : null,
            color: Colors.white10,
          ),
        ),
        // Gradient
        Container(
          height: 380.0,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black38, Colors.black87, Colors.black],
            ),
          ),
        ),
        // Nav row
        Positioned(
          top: 40.0,
          left: 16.0,
          right: 16.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24.0),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  shape: const CircleBorder(),
                ),
                onPressed: () => widget.navigationState.selectMovie(null),
              ),
              // Loading indicator if metadata is still loading in background
              if (_isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white54, strokeWidth: 2),
                ),
              IconButton(
                icon: Icon(
                  isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                  color: isBookmarked ? Colors.amber : Colors.white,
                  size: 24.0,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  shape: const CircleBorder(),
                ),
                onPressed: onBookmarkToggle,
              ),
            ],
          ),
        ),
        // Info row
        Positioned(
          left: 24.0,
          right: 24.0,
          bottom: 0.0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Poster thumbnail
              GestureDetector(
                onTap: () => showPosterImageViewerDialog(context, imageUrl: poster, title: title.isNotEmpty ? title : 'Poster'),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    height: 180.0,
                    width: 125.0,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.white24),
                      image: poster.isNotEmpty
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(poster), fit: BoxFit.cover)
                          : null,
                      color: Colors.white10,
                    ),
                    child: poster.isEmpty
                        ? const Center(
                            child: Icon(Icons.movie, color: Colors.white24, size: 32))
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 20.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Type badge
                    if (_type == 'series')
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'TV SERIES',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.0,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8),
                        ),
                      ),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Row(
                      children: [
                        if (rating != null) ...[
                          const Icon(Icons.star, color: Colors.amber, size: 14.0),
                          const SizedBox(width: 4.0),
                          Text(rating,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.0,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12.0),
                        ],
                        if (releaseInfo != null) ...[
                          Text(releaseInfo,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13.0)),
                          const SizedBox(width: 12.0),
                        ],
                        if (runtime != null)
                          Text(runtime,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 13.0)),
                      ],
                    ),
                    if (genres.isNotEmpty) ...[
                      const SizedBox(height: 10.0),
                      Wrap(
                        spacing: 6.0,
                        runSpacing: 4.0,
                        children: genres
                            .take(5)
                            .map((g) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0, vertical: 3.0),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(4.0),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Text(
                                    g.toString(),
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 10.5),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsSection() {
    final directorList = _meta['director'] is List 
        ? (_meta['director'] as List) 
        : (_meta['director'] != null ? [_meta['director']] : []);
    final writerList = _meta['writers'] is List
        ? (_meta['writers'] as List)
        : (_meta['writer'] is List 
            ? (_meta['writer'] as List) 
            : (_meta['writers'] != null ? [_meta['writers']] : (_meta['writer'] != null ? [_meta['writer']] : [])));
    final castList = _meta['cast'] is List ? (_meta['cast'] as List) : [];

    final hasDirector = directorList.isNotEmpty;
    final hasWriters = writerList.isNotEmpty;
    final hasCast = castList.isNotEmpty;

    if (!hasDirector && !hasWriters && !hasCast) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.white10, height: 40.0),
          
          if (hasCast) ...[
            const Text(
              'Cast',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 12.0),
            SizedBox(
              height: 48.0,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: castList.length,
                itemBuilder: (context, index) {
                  final actorName = castList[index].toString();
                  final initial = actorName.isNotEmpty ? actorName[0].toUpperCase() : '?';
                  return Container(
                    margin: const EdgeInsets.only(right: 12.0),
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(24.0),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 14.0,
                          backgroundColor: Colors.white10,
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 12.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                          actorName,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13.0,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24.0),
          ],

          if (hasDirector || hasWriters) ...[
            const Text(
              'Production',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 12.0),
            Wrap(
              spacing: 16.0,
              runSpacing: 16.0,
              children: [
                if (hasDirector)
                  _buildProductionItem('Director', directorList.join(', ')),
                if (hasWriters)
                  _buildProductionItem('Writer', writerList.join(', ')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductionItem(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 200.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10.0,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14.0,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayButton({
    required String title,
    required String poster,
    required String? rating,
  }) {
    Widget? primaryPlayBtn;

    if (!_isSeries) {
      // Movie — single play button
      if (_hasCheckedContinue && _continueStreamUrl != null) {
        primaryPlayBtn = ElevatedButton.icon(
          onPressed: () => PlayerState().startPlayback(
            streamUrl: _continueStreamUrl!,
            title: _continueStreamTitle ?? title,
            movieId: '$_type:$_realId',
            episodeNumber: 1,
            isMovie: true,
            media: {
              'id': '$_type:$_realId',
              'stremioId': '$_type:$_realId',
              'title': title,
              'coverImage': poster,
              'averageScore': double.tryParse(rating ?? '0') ?? 0.0,
              'format': 'MOVIE',
              'episodes': 1,
              'type': _type,
            },
          ),
          icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24.0),
          label: const Text('Resume',
              style: TextStyle(
                  color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16.0)),
          style: _playButtonStyle(Colors.amber),
        );
      } else {
        primaryPlayBtn = ElevatedButton.icon(
          onPressed: () => _fetchStreamsAndPlay(),
          icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24.0),
          label: const Text('Play',
              style: TextStyle(
                  color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16.0)),
          style: _playButtonStyle(Colors.white),
        );
      }
    } else if (_hasCheckedContinue) {
      // TV Series — continue/start button
      final label = _continueEpisode == 1 &&
              !_continueEpisodeFinished &&
              _continueStreamUrl == null
          ? 'Start Watching'
          : 'Continue — Ep $_continueEpisode';

      primaryPlayBtn = ElevatedButton.icon(
        onPressed: () {
          if (_continueStreamUrl != null && _continueStreamUrl!.isNotEmpty) {
            PlayerState().startPlayback(
              streamUrl: _continueStreamUrl!,
              title: _continueStreamTitle ?? '$title — Episode $_continueEpisode',
              movieId: '$_type:$_realId',
              episodeNumber: _continueEpisode,
              isMovie: false,
              media: {
                'id': '$_type:$_realId',
                'stremioId': '$_type:$_realId',
                'title': title,
                'coverImage': poster,
                'averageScore': double.tryParse(rating ?? '0') ?? 0.0,
                'format': 'SERIES',
                'episodes': (_meta['videos'] as List?)?.length ?? 1,
                'type': _type,
              },
              episodes: _meta['videos'],
            );
          } else {
            // Find the episode ID from the videos array
            final videos = _meta['videos'] as List? ?? [];
            final epObj = videos.firstWhere(
              (v) => (v['episode'] as num?)?.toInt() == _continueEpisode,
              orElse: () => null,
            );
            final epId = epObj?['id']?.toString() ??
                '$_realId:$_selectedSeason:$_continueEpisode';
            _fetchStreamsAndPlay(episode: _continueEpisode, episodeId: epId);
          }
        },
        icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24.0),
        label: Text(
          label,
          style: const TextStyle(
              color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16.0),
        ),
        style: _playButtonStyle(Colors.amber),
      );
    }

    final watchTogetherBtn = ListenableBuilder(
      listenable: WatchTogetherService(),
      builder: (context, _) {
        final wtService = WatchTogetherService();
        final bool inRoom = wtService.isActive;

        return ElevatedButton.icon(
          onPressed: () {
            final payload = WatchMediaPayload(
              title: title,
              movieId: '$_type:$_realId',
              episodeNumber: _isSeries ? _continueEpisode : 1,
              season: _isSeries ? _selectedSeason : null,
              isMovie: !_isSeries,
              videoUrl: _continueStreamUrl,
            );

            if (inRoom) {
              _showActiveRoomOptionsDialog(context, payload, wtService);
            } else {
              showDialog(
                context: context,
                builder: (_) => WatchTogetherDialog(
                  mediaPayload: payload,
                  onStartPlayback: (media) {
                    if (media.videoUrl != null && media.videoUrl!.isNotEmpty) {
                      PlayerState().startPlayback(
                        streamUrl: media.videoUrl!,
                        title: media.title,
                        movieId: media.movieId,
                        episodeNumber: media.episodeNumber,
                        isMovie: media.isMovie,
                        media: {
                          'id': media.movieId,
                          'stremioId': media.movieId,
                          'title': title,
                          'coverImage': poster,
                          'averageScore': double.tryParse(rating ?? '0') ?? 0.0,
                          'format': media.isMovie ? 'MOVIE' : 'SERIES',
                          'episodes': _isSeries && _hasVideos ? (_meta['videos'] as List).length : 1,
                          'type': _type,
                        },
                      );
                    } else {
                      _fetchStreamsAndPlay(
                        episode: media.isMovie ? null : media.episodeNumber,
                      );
                    }
                  },
                ),
              );
            }
          },
          icon: Icon(
            inRoom ? Icons.sensors : Icons.groups_rounded,
            color: Colors.white,
            size: 20.0,
          ),
          label: Text(
            inRoom ? 'In Room (${wtService.roomCode})' : 'Watch Together',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15.0),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: inRoom ? Colors.teal.shade700 : Colors.deepPurpleAccent,
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
          ),
        );
      },
    );

    return Wrap(
      spacing: 12.0,
      runSpacing: 12.0,
      children: [
        if (primaryPlayBtn != null) primaryPlayBtn,
        watchTogetherBtn,
      ],
    );
  }

  void _showActiveRoomOptionsDialog(BuildContext context, WatchMediaPayload payload, WatchTogetherService wtService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141419),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.sensors, color: Colors.tealAccent, size: 22),
            const SizedBox(width: 10),
            Text(
              'Room ${wtService.roomCode}',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              wtService.isHost
                  ? 'You are the Host of Room ${wtService.roomCode}.'
                  : 'You are connected as a Guest in Room ${wtService.roomCode}.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (wtService.isHost) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  minimumSize: const Size(double.infinity, 44),
                ),
                icon: const Icon(Icons.movie_creation, size: 18),
                label: Text('Set "${payload.title}" for Room'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _fetchStreamsAndPlay(
                    episode: payload.isMovie ? null : payload.episodeNumber,
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                minimumSize: const Size(double.infinity, 44),
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open Room Screen'),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WatchTogetherRoomScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                minimumSize: const Size(double.infinity, 40),
              ),
              icon: const Icon(Icons.exit_to_app, size: 18),
              label: const Text('Manage / Leave Room'),
              onPressed: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (_) => WatchTogetherDialog(mediaPayload: payload),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _playButtonStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
    );
  }

  Widget _buildEpisodesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32.0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Episodes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              if (_seasons.length > 1)
                DropdownButton<int>(
                  value: _selectedSeason,
                  dropdownColor: const Color(0xFF0F0F11),
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                  items: _seasons
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s == 0 ? 'Specials' : 'Season $s'),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedSeason = val);
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12.0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bool isMobile = constraints.maxWidth < 650;
              final episodes = _episodesBySeason[_selectedSeason] ?? [];
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: isMobile ? 180.0 : 220.0,
                  crossAxisSpacing: 12.0,
                  mainAxisSpacing: 12.0,
                  childAspectRatio: 1.4,
                ),
                itemCount: episodes.length,
                itemBuilder: (context, index) {
                  final ep = episodes[index];
                  final String epTitle =
                      ep['title']?.toString() ?? ep['name']?.toString() ?? '';
                  final String epId = ep['id']?.toString() ?? '';
                  final int epNum =
                      (ep['episode'] as num?)?.toInt() ?? (index + 1);
                  final String thumbnail =
                      ep['thumbnail']?.toString() ?? ep['still_path']?.toString() ?? '';

                  return _MovieEpisodeCard(
                    movieId: _realId,
                    epNum: epNum,
                    title: epTitle.isNotEmpty ? epTitle : 'Episode $epNum',
                    thumbnail: thumbnail,
                    onTap: () => _fetchStreamsAndPlay(episode: epNum, episodeId: epId, isDownload: false),
                    onDownload: () => _fetchStreamsAndPlay(episode: epNum, episodeId: epId, isDownload: true),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showBatchMappingPlayDialog(Map<String, dynamic> mapping, int epNum) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F0F11),
          title: const Text(
            "Play Stream",
            style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 16.0),
          ),
          content: Text(
            "This episode is available in your active batch torrent:\n\n${mapping['torrentTitle']}\n\nDo you want to play it directly or search for another stream?",
            style: const TextStyle(color: Colors.white70, fontSize: 13.0, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                _fetchStreamsAndPlayBypassingBatch(episode: epNum);
              },
              child: const Text("Search Streams", style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                _startDirectPlayback(mapping, epNum);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              child: const Text("Play Direct", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _startDirectPlayback(Map<String, dynamic> mapping, int epNum) {
    final mediaTitle = _meta['name']?.toString() ?? _meta['title']?.toString() ?? 'Media';
    final List<dynamic> videos = _meta['videos'] is List ? _meta['videos'] as List : [];
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _DirectPlaybackProgressDialog(
          mapping: mapping,
          episodeNumber: epNum,
          parentContext: context,
          titles: [mediaTitle],
          episodeCount: videos.isNotEmpty ? videos.length : 1,
          isMovie: !_isSeries,
          media: _meta,
          episodes: videos,
        );
      },
    );
  }

  Future<void> _fetchStreamsAndPlayBypassingBatch({required int episode}) async {
    final targetId = _getFormattedEpisodeId(episode: episode);
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
    final addonService = StremioAddonService();
    final streamAddons = addonService.streamAddons
        .where((a) => a.matchesId(targetId))
        .where((a) => a.supportsType(_type) || a.types.isEmpty)
        .toList();
    final streamFutures = <Future<List<dynamic>>>[];
    for (final addon in streamAddons) {
      streamFutures.add(() async {
        try {
          final url = '${addon.baseUrl}/stream/$_type/$targetId.json';
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            final List streams = body['streams'] ?? [];
            return streams.map((s) => Map<String, dynamic>.from(s as Map)..['addonName'] = addon.name).toList();
          }
        } catch (e, stack) {
          developer.log('Error fetching stream', error: e, stackTrace: stack);
        }
        return [];
      }());
    }
    final allStreams = <dynamic>[];
    if (streamFutures.isNotEmpty) {
      final results = await Future.wait(streamFutures);
      for (final r in results) {
        allStreams.addAll(r);
      }
    }
    if (mounted) Navigator.pop(context);
    if (allStreams.isEmpty) {
      if (mounted) NotificationService().show(context, 'No streams found.');
      return;
    }
    if (mounted) _showStreamSheet(allStreams, episode);
  }
}

// ─── Stream Tile ──────────────────────────────────────────────────────────────



// ─── Episode Card ─────────────────────────────────────────────────────────────

class _MovieEpisodeCard extends StatefulWidget {
  final String movieId;
  final int epNum;
  final String title;
  final String thumbnail;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  const _MovieEpisodeCard({
    required this.movieId,
    required this.epNum,
    required this.title,
    required this.thumbnail,
    required this.onTap,
    this.onDownload,
  });

  @override
  State<_MovieEpisodeCard> createState() => _MovieEpisodeCardState();
}

class _MovieEpisodeCardState extends State<_MovieEpisodeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayerState(),
      builder: (context, _) {
        final progress = PlayerState().getProgress(widget.movieId, widget.epNum);
        final double ratio = progress != null && progress.duration > 0
            ? (progress.position / progress.duration).clamp(0.0, 1.0)
            : 0.0;
        final bool isWatched = ratio >= 0.90;

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6.0),
                      border: Border.all(
                        color: _isHovered ? Colors.white30 : Colors.white10,
                      ),
                      boxShadow: _isHovered
                          ? [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.05),
                                blurRadius: 6.0,
                                spreadRadius: 1.0,
                              )
                            ]
                          : [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5.0),
                      child: Stack(
                        children: [
                          // Thumbnail image (ColorFiltered and Opacity wrap ONLY the image)
                          Positioned.fill(
                            child: ColorFiltered(
                              colorFilter: isWatched
                                  ? const ColorFilter.matrix(<double>[
                                      0.2126, 0.7152, 0.0722, 0, 0,
                                      0.2126, 0.7152, 0.0722, 0, 0,
                                      0.2126, 0.7152, 0.0722, 0, 0,
                                      0,      0,      0,      1, 0,
                                    ])
                                  : const ColorFilter.mode(
                                      Colors.transparent, BlendMode.multiply),
                              child: Opacity(
                                opacity: isWatched ? 0.5 : 1.0,
                                child: AnimatedScale(
                                  scale: _isHovered ? 1.05 : 1.0,
                                  duration: const Duration(milliseconds: 150),
                                  child: widget.thumbnail.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: widget.thumbnail,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 640,
                                          placeholder: (_, __) => const SizedBox(),
                                          errorWidget: (_, __, ___) => _placeholder(),
                                        )
                                      : _placeholder(),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: AnimatedOpacity(
                              opacity: _isHovered ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 150),
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.4),
                                child: const Center(
                                  child: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Colors.white,
                                    child: Icon(Icons.play_arrow,
                                        color: Colors.black, size: 20),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Text(
                                  'EP ${widget.epNum}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.0,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ),
                            ),
                            if (widget.onDownload != null)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: widget.onDownload,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.75),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white24, width: 1.0),
                                      ),
                                      child: const Icon(
                                        Icons.download_rounded,
                                        color: Colors.white,
                                        size: 14.0,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // Progress bar
                            if (ratio > 0.0 && ratio < 0.90)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: 3.5,
                                child: Container(
                                  color: Colors.white24,
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: ratio,
                                    child: Container(color: Colors.amber),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6.0),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Outfit',
                  ),
                ),
                Text(
                  'Episode ${widget.epNum}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder() => Container(
        color: Colors.grey[950],
        child: const Center(
          child: Icon(Icons.play_circle_outline, color: Colors.white24, size: 28),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Movie / TV Series Library Edit Panel
// ═══════════════════════════════════════════════════════════════════════════════

class _MovieLibraryEditPanel extends StatefulWidget {
  final int libId;
  final String mediaTitle;
  final String format; // 'MOVIE' or 'SERIES'
  final LibraryItem? savedItem;
  final int totalEpisodes;
  final bool hasSeasons;
  final List<int> seasons;
  final Map<int, List<dynamic>> episodesBySeason;
  final Map<String, dynamic> metaData;

  const _MovieLibraryEditPanel({
    required this.libId,
    required this.mediaTitle,
    required this.format,
    required this.savedItem,
    required this.totalEpisodes,
    required this.hasSeasons,
    required this.seasons,
    required this.episodesBySeason,
    required this.metaData,
  });

  @override
  State<_MovieLibraryEditPanel> createState() => _MovieLibraryEditPanelState();
}

class _MovieLibraryEditPanelState extends State<_MovieLibraryEditPanel> {
  late String _activeStatus;
  late double _activeRating;
  late int _watchedEps;

  late final TextEditingController _episodesController;
  late final TextEditingController _scoreController;

  // For series with seasons: track how many eps watched per season
  late Map<int, int> _watchedPerSeason;

  @override
  void initState() {
    super.initState();
    _activeStatus = widget.savedItem?.libraryStatus ?? 'planning';
    _activeRating = widget.savedItem?.rating ?? 0.0;
    _watchedEps = widget.savedItem?.watchedEpisodes ?? 0;

    // Initialize per-season tracking
    _watchedPerSeason = {};
    if (widget.hasSeasons && widget.seasons.isNotEmpty) {
      // Distribute watched episodes across seasons in order
      int remaining = _watchedEps;
      for (final s in widget.seasons) {
        final epsInSeason = widget.episodesBySeason[s]?.length ?? 0;
        final watched = remaining.clamp(0, epsInSeason);
        _watchedPerSeason[s] = watched;
        remaining -= watched;
      }
    }

    _episodesController = TextEditingController(text: '$_watchedEps');
    _scoreController = TextEditingController(
      text: _activeRating == 0.0 ? '' : _activeRating.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _episodesController.dispose();
    _scoreController.dispose();
    super.dispose();
  }

  int get _totalWatchedFromSeasons {
    if (!widget.hasSeasons) return _watchedEps;
    int total = 0;
    for (final s in widget.seasons) {
      total += _watchedPerSeason[s] ?? 0;
    }
    return total;
  }

  void _updateTotalFromSeasons() {
    final total = _totalWatchedFromSeasons;
    setState(() {
      _watchedEps = total;
      _episodesController.text = '$total';
    });
  }

  void _setSeasonWatched(int season, int count) {
    final epsInSeason = widget.episodesBySeason[season]?.length ?? 0;
    setState(() {
      _watchedPerSeason[season] = count.clamp(0, epsInSeason);
    });
    _updateTotalFromSeasons();
  }

  void _updateWatchedEpisodes(int val) {
    final int clamped = val.clamp(0, widget.totalEpisodes);
    setState(() {
      _watchedEps = clamped;
      _episodesController.text = '$clamped';
    });
    // Redistribute across seasons
    if (widget.hasSeasons) {
      int remaining = clamped;
      for (final s in widget.seasons) {
        final epsInSeason = widget.episodesBySeason[s]?.length ?? 0;
        final watched = remaining.clamp(0, epsInSeason);
        _watchedPerSeason[s] = watched;
        remaining -= watched;
      }
      setState(() {});
    }
  }

  void _updateRating(double val) {
    final double clamped = val.clamp(0.0, 10.0);
    setState(() {
      _activeRating = clamped;
      _scoreController.text = clamped == 0.0 ? '' : clamped.toStringAsFixed(1);
    });
  }

  Widget _buildStatusChip(String value, String label, IconData icon) {
    final bool isSelected = _activeStatus == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _activeStatus = value;
          if (value == 'completed') {
            _updateWatchedEpisodes(widget.totalEpisodes);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6.0),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white10,
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.black : Colors.white70,
              size: 18.0,
            ),
            const SizedBox(height: 4.0),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white70,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobileSheet = screenWidth < 650;
    final bool isSeries = widget.format == 'SERIES' && widget.hasSeasons;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: isMobileSheet ? double.infinity : 550.0,
        margin: isMobileSheet
            ? EdgeInsets.zero
            : const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F11),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
          border: Border.all(color: Colors.white10, width: 1.0),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 30, spreadRadius: 2)
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(15.0)),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Header ────────────────────────────────────────
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: isMobileSheet ? 12.0 : 16.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.01),
                        border: const Border(bottom: BorderSide(color: Colors.white10, width: 1.0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Library Entry',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white, fontSize: 15.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                ),
                                const SizedBox(height: 2.0),
                                Text(
                                  widget.mediaTitle,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                            decoration: BoxDecoration(
                              color: widget.format == 'MOVIE'
                                  ? Colors.amber.withValues(alpha: 0.15)
                                  : Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: Text(
                              widget.format,
                              style: TextStyle(
                                color: widget.format == 'MOVIE' ? Colors.amber[400] : Colors.blue[400],
                                fontSize: 10.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white54, size: 22),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    // ── Body ─────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Status Selector
                          const Text('Status', style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit')),
                          const SizedBox(height: 8.0),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(6.0),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: GridView.count(
                              crossAxisCount: isMobileSheet ? 2 : 4,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 6.0,
                              crossAxisSpacing: 6.0,
                              childAspectRatio: isMobileSheet ? 2.5 : 2.0,
                              children: [
                                _buildStatusChip('watching', 'Watching', Icons.play_arrow),
                                _buildStatusChip('planning', 'Planning', Icons.bookmark_border),
                                _buildStatusChip('completed', 'Completed', Icons.done_all),
                                _buildStatusChip('paused_dropped', 'Paused/Dropped', Icons.pause),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20.0),

                          // ── Progress Section ───────────────────────
                          if (isSeries) ...[
                            Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Episode Progress', style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit')),
                                      Text('$_watchedEps / ${widget.totalEpisodes} total', style: const TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit')),
                                    ],
                                  ),
                                  const SizedBox(height: 4.0),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4.0),
                                    child: LinearProgressIndicator(
                                      value: widget.totalEpisodes > 0 ? (_watchedEps / widget.totalEpisodes).clamp(0.0, 1.0) : 0.0,
                                      backgroundColor: Colors.white10,
                                      color: Colors.white,
                                      minHeight: 4.0,
                                    ),
                                  ),
                                  const SizedBox(height: 16.0),
                                  // Per-season rows
                                  ...widget.seasons.map((season) {
                                    final epsInSeason = widget.episodesBySeason[season]?.length ?? 0;
                                    final watchedInSeason = _watchedPerSeason[season] ?? 0;
                                    final isAllWatched = watchedInSeason >= epsInSeason && epsInSeason > 0;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10.0),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 70.0,
                                            child: Text('Season $season', style: const TextStyle(color: Colors.white54, fontSize: 12.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit')),
                                          ),
                                          Expanded(
                                            child: SliderTheme(
                                              data: SliderTheme.of(context).copyWith(
                                                activeTrackColor: isAllWatched ? Colors.green : Colors.white70,
                                                inactiveTrackColor: Colors.white10,
                                                thumbColor: Colors.white,
                                                overlayColor: Colors.white.withValues(alpha: 0.1),
                                                trackHeight: 4.0,
                                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                              ),
                                              child: Slider(
                                                value: watchedInSeason.toDouble(),
                                                min: 0.0,
                                                max: epsInSeason > 0 ? epsInSeason.toDouble() : 1.0,
                                                divisions: epsInSeason > 0 ? epsInSeason : 1,
                                                label: '$watchedInSeason / $epsInSeason',
                                                onChanged: (val) => _setSeasonWatched(season, val.toInt()),
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 50.0,
                                            child: Text(
                                              '$watchedInSeason/$epsInSeason',
                                              textAlign: TextAlign.right,
                                              style: TextStyle(color: isAllWatched ? Colors.green : Colors.white54, fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 4.0),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        icon: const Icon(Icons.clear_all, size: 16.0),
                                        label: const Text('Clear All', style: TextStyle(fontSize: 11.0, fontFamily: 'Outfit')),
                                        style: TextButton.styleFrom(foregroundColor: Colors.white38),
                                        onPressed: () {
                                          for (final s in widget.seasons) { _watchedPerSeason[s] = 0; }
                                          _updateTotalFromSeasons();
                                        },
                                      ),
                                      const SizedBox(width: 8.0),
                                      TextButton.icon(
                                        icon: const Icon(Icons.done_all, size: 16.0),
                                        label: const Text('Mark All', style: TextStyle(fontSize: 11.0, fontFamily: 'Outfit')),
                                        style: TextButton.styleFrom(foregroundColor: Colors.white70),
                                        onPressed: () {
                                          for (final s in widget.seasons) { _watchedPerSeason[s] = widget.episodesBySeason[s]?.length ?? 0; }
                                          _updateTotalFromSeasons();
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // Simple progress for movies or series without season data
                            Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        widget.format == 'MOVIE' ? 'Watched' : 'Episodes Watched',
                                        style: const TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                                      ),
                                      if (widget.format == 'MOVIE')
                                        Switch(
                                          value: _watchedEps >= 1,
                                          activeColor: Colors.white,
                                          onChanged: (val) {
                                            setState(() {
                                              _watchedEps = val ? 1 : 0;
                                              _episodesController.text = '$_watchedEps';
                                            });
                                          },
                                        )
                                      else
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 50.0, height: 20.0,
                                              child: TextField(
                                                controller: _episodesController,
                                                keyboardType: TextInputType.number,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none),
                                                onChanged: (val) {
                                                  final int? parsed = int.tryParse(val);
                                                  if (parsed != null) { setState(() { _watchedEps = parsed.clamp(0, widget.totalEpisodes); }); }
                                                },
                                                onSubmitted: (val) { _updateWatchedEpisodes(int.tryParse(val) ?? _watchedEps); },
                                              ),
                                            ),
                                            Text(' / ${widget.totalEpisodes}', style: const TextStyle(color: Colors.white38, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                                          ],
                                        ),
                                    ],
                                  ),
                                  if (widget.format != 'MOVIE') ...[
                                    const SizedBox(height: 16.0),
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor: Colors.white,
                                        inactiveTrackColor: Colors.white10,
                                        thumbColor: Colors.white,
                                        overlayColor: Colors.white.withValues(alpha: 0.1),
                                      ),
                                      child: Slider(
                                        value: _watchedEps.toDouble(),
                                        min: 0.0,
                                        max: (widget.totalEpisodes > 0 ? widget.totalEpisodes : max(100, _watchedEps + 50)).toDouble(),
                                        divisions: widget.totalEpisodes > 0 ? widget.totalEpisodes : (100 + _watchedEps),
                                        label: '$_watchedEps',
                                        onChanged: (val) => _updateWatchedEpisodes(val.toInt()),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20.0),

                          // ── Rating Section ─────────────────────────
                          Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Your Score', style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit')),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star, color: Colors.amber, size: 16.0),
                                        const SizedBox(width: 4.0),
                                        SizedBox(
                                          width: 50.0, height: 20.0,
                                          child: TextField(
                                            controller: _scoreController,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(color: Colors.amber, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none, hintText: '0.0', hintStyle: TextStyle(color: Colors.white38)),
                                            onChanged: (val) {
                                              final double? parsed = double.tryParse(val);
                                              if (parsed != null) { setState(() { _activeRating = parsed.clamp(0.0, 10.0); }); }
                                            },
                                            onSubmitted: (val) { _updateRating(double.tryParse(val) ?? _activeRating); },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16.0),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: Colors.white,
                                    inactiveTrackColor: Colors.white10,
                                    thumbColor: Colors.white,
                                    overlayColor: Colors.white.withValues(alpha: 0.1),
                                    valueIndicatorColor: Colors.white,
                                    valueIndicatorTextStyle: const TextStyle(color: Colors.black, fontFamily: 'Outfit'),
                                  ),
                                  child: Slider(
                                    value: _activeRating,
                                    min: 0.0,
                                    max: 10.0,
                                    divisions: 100,
                                    label: _activeRating == 0.0 ? 'No Rating' : _activeRating.toStringAsFixed(1),
                                    onChanged: _updateRating,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Footer ────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0C0C0E),
                        border: Border(top: BorderSide(color: Colors.white10, width: 1.0)),
                      ),
                      child: Row(
                        children: [
                          if (widget.savedItem != null)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18.0),
                              label: const Text('Remove', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                              onPressed: () async {
                                await LibraryState().removeItem(widget.libId, 'movies');
                                if (context.mounted) Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                                elevation: 0,
                                side: const BorderSide(color: Colors.redAccent, width: 1.0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                              ),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white38, fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 12.0),
                          ElevatedButton(
                            onPressed: () async {
                              final int finalWatchedEps = isSeries
                                  ? _totalWatchedFromSeasons
                                  : (int.tryParse(_episodesController.text)?.clamp(0, widget.totalEpisodes) ?? _watchedEps);
                              final double finalRating = double.tryParse(_scoreController.text)?.clamp(0.0, 10.0) ?? _activeRating;
                                await LibraryState().saveItem(
                                  id: widget.libId,
                                  mode: 'movies',
                                  format: widget.format,
                                  libraryStatus: _activeStatus,
                                  rating: finalRating,
                                  watchedEpisodes: finalWatchedEps,
                                  totalEpisodes: widget.totalEpisodes,
                                );
                                 if (widget.metaData.isNotEmpty) {
                                   final updatedCache = Map<String, dynamic>.from(widget.metaData);
                                   updatedCache['format'] = widget.format;
                                   await LibraryState().updateMovieCache(widget.libId, updatedCache);
                                 }
                                if (context.mounted) Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                            ),
                            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectPlaybackProgressDialog extends StatefulWidget {
  final Map<String, dynamic> mapping;
  final int episodeNumber;
  final BuildContext parentContext;
  final List<String> titles;
  final int episodeCount;
  final bool isMovie;
  final Map<String, dynamic>? media;
  final List<dynamic> episodes;

  const _DirectPlaybackProgressDialog({
    required this.mapping,
    required this.episodeNumber,
    required this.parentContext,
    required this.titles,
    required this.episodeCount,
    required this.isMovie,
    this.media,
    required this.episodes,
  });

  @override
  State<_DirectPlaybackProgressDialog> createState() => _DirectPlaybackProgressDialogState();
}

class _DirectPlaybackProgressDialogState extends State<_DirectPlaybackProgressDialog> {
  final TorrServerService _torrServerService = TorrServerService();
  String _status = "Checking TorrServer status...";
  bool _hasError = false;
  String _errorMessage = "";
  TorrentFile? _playingFile;
  String? _playingHash;

  @override
  void initState() {
    super.initState();
    _startPlayback();
  }

  Future<void> _startPlayback() async {
    try {
      final bool online = await _torrServerService.ping();
      if (!online) {
        setState(() {
          _status = "TorrServer starting up, waiting...";
        });
        await Future.delayed(const Duration(seconds: 2));
        final bool retryOnline = await _torrServerService.ping();
        if (!retryOnline) {
          final lastError = TorrServerManager.lastStartupError;
          throw Exception("TorrServer is not running. Please restart the app.${lastError != null ? '\n\nDetails:\n$lastError' : ''}");
        }
      }

      setState(() {
        _status = "Adding torrent & loading file...";
      });

      String torrentLink = widget.mapping['torrentLink']?.toString() ?? '';
      if (!torrentLink.contains('&tr=')) {
        final List<String> defaultTrackers = [
          'udp://tracker.coppersurfer.tk:6969/announce',
          'udp://tracker.openittracker.com:80/announce',
          'udp://tracker.opentrackr.org:1337/announce',
          'udp://explodie.org:6969/announce',
          'udp://9.rarbg.to:2710/announce',
          'udp://9.rarbg.me:2780/announce',
          'udp://open.stealth.si:80/announce',
          'udp://tracker.torrent.eu.org:451/announce',
          'udp://opentracker.i2p.rocks:6969/announce',
        ];
        for (final tr in defaultTrackers) {
          torrentLink += '&tr=${Uri.encodeComponent(tr)}';
        }
      }

      final torrentInfo = await _torrServerService.addTorrent(
        torrentLink,
        title: widget.mapping['torrentTitle'] ?? 'Batch Torrent',
      );

      final fileIndex = widget.mapping['fileIndex'] as int;
      final fileExists = torrentInfo.files.any((f) => f.index == fileIndex);
      if (!fileExists) {
        throw Exception("Mapped file index no longer exists in torrent.");
      }

      final file = torrentInfo.files.firstWhere((f) => f.index == fileIndex);

      setState(() {
        _playingFile = file;
        _playingHash = torrentInfo.hash;
        _status = "Starting playback...";
      });

      await _torrServerService.preloadTorrentFile(torrentInfo.hash, file.index).timeout(const Duration(seconds: 4), onTimeout: () {});
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _navigateToPlayer(torrentInfo.hash, file);
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString().replaceAll("Exception: ", "");
        });
      }
    }
  }

  void _navigateToPlayer(String hash, TorrentFile file) {
    final streamUrl = _torrServerService.getStreamUrl(hash, file.index);
    final fileName = file.path.split('/').last.split('\\').last;
    final displayName = fileName.isNotEmpty ? fileName : file.name;

    PlayerState().startPlayback(
      streamUrl: streamUrl,
      title: displayName,
      episodeNumber: widget.episodeNumber,
      isMovie: widget.isMovie,
      media: widget.media,
    );
    
    final navigator = Navigator.of(widget.parentContext);
    navigator.push(
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          streamUrl: streamUrl,
          title: displayName,
          anilistId: null, // Stremio media has no AniList ID
          titles: widget.titles,
          episodeCount: widget.episodeCount,
          episodeNumber: widget.episodeNumber,
          isMovie: widget.isMovie,
          media: widget.media,
          episodes: widget.episodes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: AlertDialog(
        backgroundColor: const Color(0xFF0F0F11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_hasError) ...[
                const SizedBox(
                  width: 36.0,
                  height: 36.0,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                ),
                const SizedBox(height: 24.0),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13.0, height: 1.4),
                ),
                if (_playingFile != null && _playingHash != null) ...[
                  TextButton(
                    onPressed: () {
                      _torrServerService.cancelAllPreloads();
                      if (Navigator.of(context).canPop()) Navigator.pop(context);
                      _navigateToPlayer(_playingHash!, _playingFile!);
                    },
                    child: const Text("Skip Buffering", style: TextStyle(color: Colors.white54, fontSize: 12.0)),
                  ),
                ] else ...[
                  TextButton(
                    onPressed: () {
                      _torrServerService.cancelAllPreloads();
                      if (Navigator.of(context).canPop()) Navigator.pop(context);
                    },
                    child: const Text("Cancel", style: TextStyle(color: Colors.white38, fontSize: 12.0)),
                  ),
                ],
              ] else ...[
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 36.0),
                const SizedBox(height: 16.0),
                const Text(
                  "Playback Failed",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15.0),
                ),
                const SizedBox(height: 12.0),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 24.0),
                SizedBox(
                  width: double.infinity,
                  height: 40.0,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                    ),
                    child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
