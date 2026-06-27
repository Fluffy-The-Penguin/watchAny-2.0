import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../state/navigation_state.dart';
import '../services/stremio_addon_service.dart';
import '../state/player_state.dart';
import '../state/library_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/extension_service.dart';
import '../widgets/torrent_selector_panel.dart';

class MovieDetailsPage extends StatefulWidget {
  final String movieId; // Format: "type:imdbId" (e.g. "movie:tt11378946")
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
    _loadMetadata();
  }

  void _parseId() {
    final parts = widget.movieId.split(':');
    if (parts.length >= 2) {
      _type = parts[0];
      _realId = widget.movieId.substring(_type.length + 1);
    } else {
      _realId = widget.movieId;
    }
  }

  bool get _hasVideos => _meta['videos'] != null && (_meta['videos'] as List).isNotEmpty;

  Future<void> _loadMetadata() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final addonService = StremioAddonService();
    await addonService.init();

    final enabledMetaAddons = addonService.addons
        .where((a) => a.isEnabled && a.resources.contains('meta'))
        .toList();

    Map<String, dynamic>? metaData;

    // Fetch meta from user-installed addons
    for (final addon in enabledMetaAddons) {
      try {
        final metaUrl = '${addon.url.replaceAll('/manifest.json', '')}/meta/$_type/$_realId.json';
        final response = await http.get(Uri.parse(metaUrl)).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['meta'] != null) {
            metaData = Map<String, dynamic>.from(data['meta']);
            break;
          }
        }
      } catch (e) {
        debugPrint('Error loading meta from ${addon.name}: $e');
      }
    }

    // Fallback: If no metadata was resolved and it's a mainstream movie/series, query official public Cinemeta
    if (metaData == null && (_type == 'movie' || _type == 'series')) {
      try {
        final fallbackUrl = 'https://v3-cinemeta.strem.io/meta/$_type/$_realId.json';
        final response = await http.get(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['meta'] != null) {
            metaData = Map<String, dynamic>.from(data['meta']);
          }
        }
      } catch (e) {
        debugPrint('Error loading metadata from public Cinemeta fallback: $e');
      }
    }

    if (metaData == null) {
      setState(() {
        _error = 'Failed to load movie details. Check internet or addon connection.';
        _isLoading = false;
      });
      return;
    }

    // Process seasons and episodes if it's a TV series or playlist
    final bool hasVideos = metaData['videos'] != null && (metaData['videos'] as List).isNotEmpty;
    if (hasVideos) {
      final List videos = metaData['videos'];
      final Map<int, List<dynamic>> grouped = {};
      final Set<int> seasonNums = {};

      for (final video in videos) {
        final int s = video['season'] ?? 1;
        seasonNums.add(s);
        grouped.putIfAbsent(s, () => []).add(video);
      }

      // Sort episodes within each season
      for (final s in grouped.keys) {
        grouped[s]!.sort((a, b) => (a['episode'] ?? 0).compareTo(b['episode'] ?? 0));
      }

      final sortedSeasons = seasonNums.toList()..sort();

      _seasons = sortedSeasons;
      _episodesBySeason = grouped;
      _selectedSeason = _seasons.isNotEmpty ? _seasons[0] : 1;
    }

    // Save metadata format for Library usage
    final int parsedIntId = _parseImdbIdToInt(_realId);
    final lightweightMedia = {
      'id': _realId,
      'title': metaData['name'] ?? 'Untitled',
      'coverImage': metaData['poster'] ?? '',
      'averageScore': double.tryParse(metaData['imdbRating']?.toString() ?? '0') ?? 0.0,
      'format': hasVideos ? 'SERIES' : 'MOVIE',
      'episodes': hasVideos ? (metaData['videos']?.length ?? 1) : 1,
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('continue_watching_metadata_$parsedIntId', jsonEncode(lightweightMedia));
    await prefs.setString('continue_watching_metadata_$_realId', jsonEncode(lightweightMedia));

    if (mounted) {
      setState(() {
        _meta = metaData!;
      });
      await _loadPlaybackProgress();
    }
  }

  Future<void> _loadPlaybackProgress() async {
    final prefs = await SharedPreferences.getInstance();
    
    final lastEp = prefs.getInt('continue_watching_last_ep_$_realId') ?? 1;
    final pos = prefs.getInt('playback_pos_${_realId}_$lastEp');
    final dur = prefs.getInt('playback_dur_${_realId}_$lastEp');

    int targetEp = lastEp;
    bool finished = false;
    if (pos != null && dur != null) {
      final ratio = pos / dur;
      if (ratio >= 0.90) {
        finished = true;
        if (_hasVideos && _episodesBySeason.containsKey(_selectedSeason)) {
          final totalCount = _meta['videos']?.length ?? 1;
          if (lastEp < totalCount) {
            targetEp = lastEp + 1;
          }
        }
      }
    }

    final savedStream = prefs.getString('playback_stream_${_realId}_$targetEp');
    final savedTitle = prefs.getString('playback_title_${_realId}_$targetEp');

    final List<int> allEpNums = [];
    if (_hasVideos && _meta['videos'] != null) {
      for (final video in _meta['videos']) {
        final int epNum = video['episode'] ?? 1;
        allEpNums.add(epNum);
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

  int _parseImdbIdToInt(String imdbId) {
    final digits = imdbId.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digits) ?? 0;
  }

  Future<void> _fetchStreamsAndPlay({int? episode, String? episodeId}) async {
    final targetId = episodeId ?? _realId;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    final addonService = StremioAddonService();
    final enabledStreamAddons = addonService.addons
        .where((a) => a.isEnabled && a.resources.contains('stream'))
        .toList();

    List<dynamic> allStreams = [];

    for (final addon in enabledStreamAddons) {
      try {
        final streamUrl = '${addon.url.replaceAll('/manifest.json', '')}/stream/$_type/$targetId.json';
        final response = await http.get(Uri.parse(streamUrl)).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List streams = data['streams'] ?? [];
          for (final s in streams) {
            allStreams.add({
              ...s,
              'addonName': addon.name,
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading stream from ${addon.name}: $e');
      }
    }

    if (mounted) {
      Navigator.pop(context); // Close loading dialog
    }

    if (allStreams.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No streams found. Enable a stream addon (like Torrentio).')),
        );
      }
      return;
    }

    // Show stream selector
    if (mounted) {
      _showStreamSelectorSheet(allStreams, episode);
    }
  }

  void _showStreamSelectorSheet(List<dynamic> streams, int? episode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F11),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Stream ${episode != null ? " - Episode $episode" : ""}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Outfit',
                            fontSize: 16.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${streams.length} links found',
                          style: const TextStyle(color: Colors.white38, fontSize: 12.0),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16.0),
                      itemCount: streams.length,
                      itemBuilder: (context, index) {
                        final stream = streams[index];
                        final String name = stream['name'] ?? stream['addonName'] ?? 'Stremio Addon';
                        final String rawTitle = stream['title'] ?? 'No details.';
                        final String cleanTitle = _cleanStreamTitle(rawTitle);
                        final tags = _getStreamTags(rawTitle);
                        final size = _getStreamSize(stream);
                        final seeders = _getStreamSeeders(stream);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10.0),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            title: Text(
                              cleanTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.0,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Wrap(
                                spacing: 8.0,
                                runSpacing: 4.0,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  // Provider badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(4.0),
                                    ),
                                    child: Text(
                                      name.split('\n').first.toUpperCase(),
                                      style: const TextStyle(color: Colors.white60, fontSize: 8.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  // Size
                                  if (size.isNotEmpty)
                                    Text(
                                      size,
                                      style: const TextStyle(color: Colors.white54, fontSize: 11.0),
                                    ),
                                  // Seeders
                                  if (seeders > 0)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.arrow_upward, color: Colors.green, size: 13.0),
                                        const SizedBox(width: 2.0),
                                        Text(
                                          '$seeders',
                                          style: const TextStyle(color: Colors.green, fontSize: 11.0, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  // Resolution Tags
                                  ...tags.map((tag) {
                                    final is4K = tag == '4K';
                                    final isFHD = tag == '1080p';
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                      decoration: BoxDecoration(
                                        color: is4K
                                            ? Colors.amber.withValues(alpha: 0.15)
                                            : isFHD
                                                ? Colors.blue.withValues(alpha: 0.15)
                                                : Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4.0),
                                      ),
                                      child: Text(
                                        tag,
                                        style: TextStyle(
                                          color: is4K
                                              ? Colors.amber[400]
                                              : isFHD
                                                  ? Colors.blue[400]
                                                  : Colors.white70,
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                _playStream(stream, episode);
                              },
                              child: const Text('Play', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _cleanStreamTitle(String title) {
    final lines = title.split('\n');
    if (lines.isNotEmpty) {
      return lines[0].trim();
    }
    return title;
  }

  List<String> _getStreamTags(String title) {
    final List<String> tags = [];
    final t = title.toLowerCase();
    if (t.contains('2160p') || t.contains('4k') || t.contains('uhd')) tags.add('4K');
    else if (t.contains('1080p') || t.contains('fhd')) tags.add('1080p');
    else if (t.contains('720p') || t.contains('hd')) tags.add('720p');
    else if (t.contains('480p') || t.contains('sd')) tags.add('480p');

    if (t.contains('hdr')) tags.add('HDR');
    if (t.contains('dv') || t.contains('dolby vision')) tags.add('DV');
    if (t.contains('dual') || t.contains('dual-audio') || t.contains('multi')) tags.add('Dual Audio');
    return tags;
  }

  String _getStreamSize(dynamic stream) {
    if (stream['size'] != null) {
      final sizeBytes = int.tryParse(stream['size'].toString()) ?? 0;
      if (sizeBytes > 0) {
        final gb = sizeBytes / (1024 * 1024 * 1024);
        if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
        final mb = sizeBytes / (1024 * 1024);
        return '${mb.toStringAsFixed(0)} MB';
      }
    }
    final title = stream['title']?.toString() ?? '';
    final match = RegExp(r'\b(\d+(?:\.\d+)?\s*(?:GB|MB))\b', caseSensitive: false).firstMatch(title);
    return match?.group(1) ?? '';
  }

  int _getStreamSeeders(dynamic stream) {
    if (stream['seeders'] != null) {
      return int.tryParse(stream['seeders'].toString()) ?? 0;
    }
    final title = stream['title']?.toString() ?? '';
    final match = RegExp(r'(?:👤|seeders:?\s*)(\d+)\b', caseSensitive: false).firstMatch(title);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  void _playStream(dynamic stream, int? episode) {
    if (stream['infoHash'] != null) {
      final String hash = stream['infoHash'];
      final String name = stream['name'] ?? stream['addonName'] ?? 'Torrent Stream';
      final String title = stream['title'] ?? name;

      final torrentStream = TorrentStream(
        title: title,
        link: 'magnet:?xt=urn:btih:$hash',
        seeders: _getStreamSeeders(stream),
        leechers: 0,
        downloads: 0,
        hash: hash,
        size: stream['size'] != null ? (int.tryParse(stream['size'].toString()) ?? 0) : 0,
        accuracy: 'high',
        type: _type,
        extensionName: stream['addonName'] ?? 'Stremio Addon',
      );

      final mediaTitle = _meta['name'] ?? 'Media';
      final int parsedIntId = _parseImdbIdToInt(_realId);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return PlaybackProgressDialog(
            stream: torrentStream,
            parentContext: context,
            anilistId: parsedIntId,
            movieId: _realId,
            episodeNumber: episode ?? 1,
            titles: [mediaTitle],
            episodeCount: _hasVideos ? (_meta['videos']?.length ?? 1) : 1,
            isMovie: !_hasVideos,
            media: {
              'id': _realId,
              'title': mediaTitle,
              'coverImage': _meta['poster'] ?? '',
              'averageScore': double.tryParse(_meta['imdbRating']?.toString() ?? '0') ?? 0.0,
              'format': _hasVideos ? 'SERIES' : 'MOVIE',
              'episodes': _hasVideos ? (_meta['videos']?.length ?? 1) : 1,
            },
            episodes: _hasVideos ? _meta['videos'] : null,
          );
        },
      );
      return;
    }

    String streamUrl = stream['url'] ?? '';
    if (streamUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid stream URL.')),
      );
      return;
    }

    final mediaTitle = _meta['name'] ?? 'Media';

    PlayerState().startPlayback(
      streamUrl: streamUrl,
      title: episode != null ? '$mediaTitle - Episode $episode' : mediaTitle,
      movieId: _realId,
      episodeNumber: episode ?? 1,
      isMovie: !_hasVideos,
      media: {
        'id': _realId,
        'title': mediaTitle,
        'coverImage': _meta['poster'] ?? '',
        'averageScore': double.tryParse(_meta['imdbRating']?.toString() ?? '0') ?? 0.0,
        'format': _hasVideos ? 'SERIES' : 'MOVIE',
        'episodes': _hasVideos ? (_meta['videos']?.length ?? 1) : 1,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
        ),
      );
    }

    if (_error.isNotEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48.0),
              const SizedBox(height: 16.0),
              Text(_error, style: const TextStyle(color: Colors.white70, fontSize: 14.0)),
              const SizedBox(height: 24.0),
              ElevatedButton(
                onPressed: _loadMetadata,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final background = _meta['background'] ?? _meta['poster'] ?? '';
    final poster = _meta['poster'] ?? '';
    final title = _meta['name'] ?? 'Untitled';
    final description = _meta['description'] ?? 'No description available.';
    final rating = _meta['imdbRating']?.toString();
    final releaseInfo = _meta['releaseInfo']?.toString();
    final runtime = _meta['runtime']?.toString();
    final List<dynamic> genres = _meta['genres'] ?? [];

    final int parsedIntId = _parseImdbIdToInt(_realId);

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: LibraryState(),
        builder: (context, _) {
          final isBookmarked = LibraryState().items.any((item) => item.id == parsedIntId && item.mode == 'movies');

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Details Banner Header
                Stack(
                  children: [
                    Container(
                      height: 380.0,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        image: background.isNotEmpty
                            ? DecorationImage(image: NetworkImage(background), fit: BoxFit.cover)
                            : null,
                        color: Colors.white10,
                      ),
                    ),
                    Container(
                      height: 380.0,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black45,
                            Colors.black87,
                            Colors.black,
                          ],
                        ),
                      ),
                    ),
                    // Navigation top row
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
                            onPressed: () {
                              if (isBookmarked) {
                                LibraryState().removeItem(parsedIntId, 'movies');
                              } else {
                                LibraryState().saveItem(
                                  id: parsedIntId,
                                  mode: 'movies',
                                  format: _hasVideos ? 'SERIES' : 'MOVIE',
                                  libraryStatus: 'planning',
                                  rating: double.tryParse(rating ?? '0') ?? 0.0,
                                  watchedEpisodes: 0,
                                  totalEpisodes: _hasVideos ? (_meta['videos']?.length ?? 1) : 1,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    // Banner Information Details
                    Positioned(
                      left: 24.0,
                      right: 24.0,
                      bottom: 0.0,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Small Poster card (Desktop only)
                          Container(
                            height: 180.0,
                            width: 125.0,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Colors.white24),
                              image: poster.isNotEmpty
                                  ? DecorationImage(image: NetworkImage(poster), fit: BoxFit.cover)
                                  : null,
                              color: Colors.white10,
                            ),
                          ),
                          const SizedBox(width: 20.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Title name
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28.0,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                                const SizedBox(height: 8.0),
                                // Metadata Tags
                                Row(
                                  children: [
                                    if (rating != null) ...[
                                      const Icon(Icons.star, color: Colors.amber, size: 14.0),
                                      const SizedBox(width: 4.0),
                                      Text(
                                        rating,
                                        style: const TextStyle(color: Colors.white, fontSize: 13.0, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 12.0),
                                    ],
                                    if (releaseInfo != null) ...[
                                      Text(releaseInfo, style: const TextStyle(color: Colors.white70, fontSize: 13.0)),
                                      const SizedBox(width: 12.0),
                                    ],
                                    if (runtime != null)
                                      Text(runtime, style: const TextStyle(color: Colors.white38, fontSize: 13.0)),
                                  ],
                                ),
                                const SizedBox(height: 12.0),
                                // Genres wrap
                                Wrap(
                                  spacing: 8.0,
                                  runSpacing: 6.0,
                                  children: [
                                    for (final genre in genres)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(4.0),
                                          border: Border.all(color: Colors.white10),
                                        ),
                                        child: Text(
                                          genre.toString(),
                                          style: const TextStyle(color: Colors.white70, fontSize: 11.0),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24.0),

                // 2. Play Actions / Description
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_hasVideos) ...[
                        if (_hasCheckedContinue && _continueStreamUrl != null)
                          ElevatedButton.icon(
                            onPressed: () {
                              PlayerState().startPlayback(
                                streamUrl: _continueStreamUrl!,
                                title: _continueStreamTitle ?? title,
                                movieId: _realId,
                                episodeNumber: 1,
                                isMovie: true,
                                media: {
                                  'id': _realId,
                                  'title': title,
                                  'coverImage': poster,
                                  'averageScore': double.tryParse(rating ?? '0') ?? 0.0,
                                  'format': 'MOVIE',
                                  'episodes': 1,
                                },
                              );
                            },
                            icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24.0),
                            label: const Text('Resume Video', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16.0)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: () => _fetchStreamsAndPlay(),
                            icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24.0),
                            label: const Text('Play Video', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16.0)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                            ),
                          ),
                      ] else if (_hasVideos && _hasCheckedContinue) ...[
                        ElevatedButton.icon(
                          onPressed: () {
                            if (_continueStreamUrl != null && _continueStreamUrl!.isNotEmpty) {
                              PlayerState().startPlayback(
                                streamUrl: _continueStreamUrl!,
                                title: _continueStreamTitle ?? '$title - Episode $_continueEpisode',
                                movieId: _realId,
                                episodeNumber: _continueEpisode,
                                isMovie: false,
                                media: {
                                  'id': _realId,
                                  'title': title,
                                  'coverImage': poster,
                                  'averageScore': double.tryParse(rating ?? '0') ?? 0.0,
                                  'format': 'SERIES',
                                  'episodes': _meta['videos']?.length ?? 1,
                                },
                              );
                            } else {
                              final List videos = _meta['videos'] as List? ?? [];
                              final epObj = videos.firstWhere(
                                (v) => v['episode'] == _continueEpisode,
                                orElse: () => null,
                              );
                              final epId = epObj?['id'] ?? '$_realId:$_selectedSeason:$_continueEpisode';
                              _fetchStreamsAndPlay(episode: _continueEpisode, episodeId: epId);
                            }
                          },
                          icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24.0),
                          label: Text(
                            _continueEpisode == 1 && !_continueEpisodeFinished && _continueStreamUrl == null
                                ? 'Start Watching'
                                : 'Continue Ep $_continueEpisode',
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16.0),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20.0),
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
                        style: const TextStyle(color: Colors.white70, fontSize: 14.0, height: 1.4),
                      ),
                    ],
                  ),
                ),

                // 3. Episodes / Seasons Section (TV Series or playlists)
                if (_hasVideos) ...[
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
                        // Only show Season Selector Dropdown if there are multiple seasons
                        if (_seasons.length > 1)
                          DropdownButton<int>(
                            value: _selectedSeason,
                            dropdownColor: const Color(0xFF0F0F11),
                            underline: const SizedBox.shrink(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                            items: [
                              for (final s in _seasons)
                                DropdownMenuItem(
                                  value: s,
                                  child: Text('Season $s'),
                                ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedSeason = val;
                                });
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  // Episode Grid
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final bool isMobile = constraints.maxWidth < 650;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isMobile ? 2 : 3,
                            crossAxisSpacing: 14.0,
                            mainAxisSpacing: 14.0,
                            childAspectRatio: 1.25,
                          ),
                          itemCount: _episodesBySeason[_selectedSeason]?.length ?? 0,
                          itemBuilder: (context, index) {
                            final ep = _episodesBySeason[_selectedSeason]![index];
                            final String epTitle = ep['title'] ?? ep['name'] ?? 'Episode ${ep['episode']}';
                            final String id = ep['id'] ?? '';
                            final int epNum = ep['episode'] ?? (index + 1);
                            final String thumbnail = ep['thumbnail'] ?? ep['still_path'] ?? '';

                            return _MovieEpisodeCard(
                              movieId: _realId,
                              epNum: epNum,
                              title: epTitle,
                              thumbnail: thumbnail,
                              onTap: () => _fetchStreamsAndPlay(episode: epNum, episodeId: id),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 48.0),
              ],
            ),
          );
        },
      ),
    );
  }
}

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
                        width: 1.0,
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
                            : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
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
                                          errorBuilder: (context, error, stackTrace) =>
                                              _buildPlaceholder(),
                                        )
                                      : _buildPlaceholder(),
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
                                        radius: 18.0,
                                        backgroundColor: Colors.white,
                                        child: Icon(Icons.play_arrow, color: Colors.black, size: 20.0),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8.0,
                                left: 8.0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(4.0),
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
                                      child: Container(
                                        color: Colors.amber,
                                      ),
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
                const SizedBox(height: 2.0),
                Text(
                  'Episode ${widget.epNum}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[950],
      child: const Center(
        child: Icon(Icons.play_circle_outline, color: Colors.white24, size: 28.0),
      ),
    );
  }
}
