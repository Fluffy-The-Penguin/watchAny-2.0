import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../state/navigation_state.dart';
import '../services/stremio_addon_service.dart';
import '../state/player_state.dart';
import '../state/library_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      _realId = parts[1];
    } else {
      _realId = widget.movieId;
    }
  }

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

    // Process seasons and episodes if it's a TV series
    if (_type == 'series' && metaData['videos'] != null) {
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
      'format': _type == 'movie' ? 'MOVIE' : 'SERIES',
      'episodes': _type == 'movie' ? 1 : (metaData['videos']?.length ?? 1),
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('continue_watching_metadata_$parsedIntId', jsonEncode(lightweightMedia));
    await prefs.setString('continue_watching_metadata_$_realId', jsonEncode(lightweightMedia));

    if (mounted) {
      setState(() {
        _meta = metaData!;
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
      builder: (context) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Select Stream ${episode != null ? " - Episode $episode" : ""}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Outfit',
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: streams.length,
                  itemBuilder: (context, index) {
                    final stream = streams[index];
                    final String name = stream['name'] ?? stream['addonName'] ?? 'Unknown Stream';
                    final String title = stream['title'] ?? 'No stream details.';

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                      title: Text(
                        name,
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14.0),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          title,
                          style: const TextStyle(color: Colors.white70, fontSize: 12.0),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _playStream(stream, episode);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _playStream(dynamic stream, int? episode) {
    String streamUrl = stream['url'] ?? '';
    if (streamUrl.isEmpty && stream['infoHash'] != null) {
      final String hash = stream['infoHash'];
      final int fileIdx = stream['fileIdx'] ?? 0;
      streamUrl = 'http://127.0.0.1:8090/stream?link=$hash&index=${fileIdx + 1}&play';
    }

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
      isMovie: _type == 'movie',
      media: {
        'id': _realId,
        'title': mediaTitle,
        'coverImage': _meta['poster'] ?? '',
        'averageScore': double.tryParse(_meta['imdbRating']?.toString() ?? '0') ?? 0.0,
        'format': _type == 'movie' ? 'MOVIE' : 'SERIES',
        'episodes': _type == 'movie' ? 1 : (_meta['videos']?.length ?? 1),
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
                                  format: _type == 'movie' ? 'MOVIE' : 'SERIES',
                                  libraryStatus: 'planning',
                                  rating: double.tryParse(rating ?? '0') ?? 0.0,
                                  watchedEpisodes: 0,
                                  totalEpisodes: _type == 'movie' ? 1 : (_meta['videos']?.length ?? 1),
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
                      if (_type == 'movie')
                        ElevatedButton.icon(
                          onPressed: () => _fetchStreamsAndPlay(),
                          icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24.0),
                          label: const Text('Play Movie', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16.0)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                        ),
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

                // 3. Episodes / Seasons Section (TV Series only)
                if (_type == 'series') ...[
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
                        // Season Selector Dropdown
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
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14.0,
                        mainAxisSpacing: 14.0,
                        childAspectRatio: 2.2,
                      ),
                      itemCount: _episodesBySeason[_selectedSeason]?.length ?? 0,
                      itemBuilder: (context, index) {
                        final ep = _episodesBySeason[_selectedSeason]![index];
                        final String epTitle = ep['title'] ?? 'Episode ${ep['episode']}';
                        final String id = ep['id'] ?? '';
                        final int epNum = ep['episode'] ?? (index + 1);

                        return GestureDetector(
                          onTap: () => _fetchStreamsAndPlay(episode: epNum, episodeId: id),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Colors.white10),
                            ),
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                Container(
                                  width: 32.0,
                                  height: 32.0,
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$epNum',
                                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13.0),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14.0),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        epTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.0),
                                      ),
                                      const SizedBox(height: 2.0),
                                      const Text(
                                        'Play Episode',
                                        style: TextStyle(color: Colors.white38, fontSize: 11.0),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
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
