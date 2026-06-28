import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../state/navigation_state.dart';
import '../services/stremio_addon_service.dart';
import '../state/player_state.dart';
import '../state/library_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/extension_service.dart';
import '../widgets/torrent_selector_panel.dart';
import '../widgets/movie_stream_selector_panel.dart';

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

    _loadMetadata();
  }

  /// Splits "type:id" into (_type, _realId).
  /// Handles multi-colon IDs like "series:kitsu:47"
  void _parseId() {
    final firstColon = widget.movieId.indexOf(':');
    if (firstColon > 0) {
      _type = widget.movieId.substring(0, firstColon);
      _realId = widget.movieId.substring(firstColon + 1);
    } else {
      _type = 'movie';
      _realId = widget.movieId;
    }
  }

  bool get _hasVideos => _meta['videos'] is List && (_meta['videos'] as List).isNotEmpty;

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
          } catch (e) {
            debugPrint('[meta] Error from ${addon.name}: $e');
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
        } catch (e) {
          debugPrint('[meta] Cinemeta fallback failed: $e');
        }
      }

      // 3. Fall back to placeholder cache
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
          int s = (video['season'] as num?)?.toInt() ?? 1;
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
        'format': videosList.isNotEmpty ? 'SERIES' : 'MOVIE',
        'episodes': videosList.isNotEmpty ? videosList.length : 1,
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
        await _loadPlaybackProgress();
      }
    } catch (e, stack) {
      debugPrint('[MovieDetailsPage] Unhandled error in _loadMetadata: $e\n$stack');
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

  Future<void> _fetchStreamsAndPlay({int? episode, String? episodeId}) async {
    final targetId = episodeId?.isNotEmpty == true ? episodeId! : _realId;

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
        } catch (e) {
          debugPrint('[stream] Error from ${addon.name}: $e');
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No streams found. Install a stream addon like Torrentio.')),
        );
      }
      return;
    }

    if (mounted) _showStreamSheet(allStreams, episode);
  }

  // ── Stream Selector Bottom Sheet ──────────────────────────────────────────

  void _showStreamSheet(List<dynamic> streams, int? episode) {
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
                onStreamSelected: (stream) {
                  Navigator.pop(context); // close bottom sheet
                  _playStream(stream, episode);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  void _playStream(dynamic stream, int? episode) {
    final mediaTitle =
        _meta['name']?.toString() ?? _meta['title']?.toString() ?? 'Media';
    final poster = _meta['poster']?.toString() ?? _meta['coverImage']?.toString() ?? '';
    final rating = double.tryParse(_meta['imdbRating']?.toString() ?? '') ?? 0.0;
    final epCount = _hasVideos ? (_meta['videos'] as List).length : 1;

    final media = {
      'id': _realId,
      'stremioId': _realId,
      'title': mediaTitle,
      'coverImage': poster,
      'averageScore': rating,
      'format': _hasVideos ? 'SERIES' : 'MOVIE',
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
          isMovie: !_hasVideos,
          media: media,
          episodes: _hasVideos ? _meta['videos'] : null,
        ),
      );
      return;
    }

    // Direct URL stream
    final String streamUrl = stream['url']?.toString() ?? '';
    if (streamUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This stream has no playable URL or hash.')),
      );
      return;
    }

    PlayerState().startPlayback(
      streamUrl: streamUrl,
      title: episode != null ? '$mediaTitle — Episode $episode' : mediaTitle,
      movieId: '$_type:$_realId',
      episodeNumber: episode ?? 1,
      isMovie: !_hasVideos,
      media: media,
      episodes: _hasVideos ? _meta['videos'] : null,
      titles: [mediaTitle],
    );
  }

  // ── Stream parsing helpers ─────────────────────────────────────────────────

  int _parseSeeders(dynamic stream) {
    if (stream['seeders'] != null) {
      return int.tryParse(stream['seeders'].toString()) ?? 0;
    }
    final t = stream['title']?.toString() ?? stream['description']?.toString() ?? '';
    final m = RegExp(r'(?:👤|seeders?:?\s*)(\d+)', caseSensitive: false).firstMatch(t);
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

    debugPrint('[MovieDetailsPage] build: movieId=$widget.movieId, title=${_meta['name'] ?? _meta['title'] ?? 'Untitled'}, keys=${_meta.keys.toList()}');

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

          return SingleChildScrollView(
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
                    final totalEps = _hasVideos
                        ? (_meta['videos'] is List ? (_meta['videos'] as List).length : 0)
                        : 1;
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _MovieLibraryEditPanel(
                        libId: libId,
                        mediaTitle: title,
                        format: _hasVideos ? 'SERIES' : 'MOVIE',
                        savedItem: savedItem,
                        totalEpisodes: totalEps,
                        hasSeasons: _hasVideos && _seasons.isNotEmpty,
                        seasons: _seasons,
                        episodesBySeason: _episodesBySeason,
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

                // 3. Episodes Section (TV only)
                if (_hasVideos) _buildEpisodesSection(),

                const SizedBox(height: 64.0),
              ],
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
                    image: NetworkImage(background), fit: BoxFit.cover)
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
              Container(
                height: 180.0,
                width: 125.0,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.white24),
                  image: poster.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(poster), fit: BoxFit.cover)
                      : null,
                  color: Colors.white10,
                ),
                child: poster.isEmpty
                    ? const Center(
                        child: Icon(Icons.movie, color: Colors.white24, size: 32))
                    : null,
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

  Widget _buildPlayButton({
    required String title,
    required String poster,
    required String? rating,
  }) {
    if (!_hasVideos) {
      // Movie — single play button
      if (_hasCheckedContinue && _continueStreamUrl != null) {
        return ElevatedButton.icon(
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
      }
      return ElevatedButton.icon(
        onPressed: () => _fetchStreamsAndPlay(),
        icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24.0),
        label: const Text('Play',
            style: TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16.0)),
        style: _playButtonStyle(Colors.white),
      );
    }

    // TV Series — continue/start button
    if (_hasCheckedContinue) {
      final label = _continueEpisode == 1 &&
              !_continueEpisodeFinished &&
              _continueStreamUrl == null
          ? 'Start Watching'
          : 'Continue — Ep $_continueEpisode';

      return ElevatedButton.icon(
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
                '$_realId:${_selectedSeason}:$_continueEpisode';
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

    return const SizedBox.shrink();
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
                    onTap: () => _fetchStreamsAndPlay(episode: epNum, episodeId: epId),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
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

  const _MovieEpisodeCard({
    required this.movieId,
    required this.epNum,
    required this.title,
    required this.thumbnail,
    required this.onTap,
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
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: AnimatedScale(
                                  scale: _isHovered ? 1.05 : 1.0,
                                  duration: const Duration(milliseconds: 150),
                                  child: widget.thumbnail.isNotEmpty
                                      ? Image.network(
                                          widget.thumbnail,
                                          fit: BoxFit.cover,
                                          cacheWidth: 320,
                                          errorBuilder: (_, __, ___) => _placeholder(),
                                        )
                                      : _placeholder(),
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

  const _MovieLibraryEditPanel({
    required this.libId,
    required this.mediaTitle,
    required this.format,
    required this.savedItem,
    required this.totalEpisodes,
    required this.hasSeasons,
    required this.seasons,
    required this.episodesBySeason,
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
