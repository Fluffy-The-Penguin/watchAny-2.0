import 'dart:math';
import 'package:flutter/material.dart';
import '../services/anilist_service.dart';
import '../services/extension_service.dart';
import '../services/tmdb_service.dart';
import '../services/batch_mapping_service.dart';
import '../services/torrserver_service.dart';
import '../screens/player_screen.dart';
import '../state/navigation_state.dart';
import '../widgets/torrent_selector_panel.dart';
import '../models/torrent.dart';

class AnimeDetailsPage extends StatefulWidget {
  final int animeId;
  final NavigationState navigationState;

  const AnimeDetailsPage({
    super.key,
    required this.animeId,
    required this.navigationState,
  });

  @override
  State<AnimeDetailsPage> createState() => _AnimeDetailsPageState();
}

class _AnimeDetailsPageState extends State<AnimeDetailsPage> {
  final AnilistService _anilistService = AnilistService();
  final TmdbService _tmdbService = TmdbService();

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _details;
  List<dynamic> _mergedEpisodes = [];
  
  // Tab and Pagination state
  int _activeTab = 0; // 0: About, 1: Characters & Cast, 2: Relations
  int _activeEpisodePage = 0; // Pagination index (groups of 50)
  bool _isDescriptionExpanded = false;

  // TMDB state
  int? _tmdbId;
  List<TmdbSeasonInfo> _tmdbSeasons = [];
  final Map<int, Map<String, dynamic>> _tmdbEpisodesMap = {};
  bool _isTmdbLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void didUpdateWidget(covariant AnimeDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animeId != widget.animeId) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _details = null;
        _mergedEpisodes = [];
        _activeTab = 0;
        _activeEpisodePage = 0;
        _isDescriptionExpanded = false;
        _tmdbId = null;
        _tmdbSeasons = [];
        _tmdbEpisodesMap.clear();
        _isTmdbLoading = false;
      });
      _loadDetails();
    }
  }

  Future<void> _loadDetails() async {
    final mappingsFuture = ExtensionService().getMappings(widget.animeId);
    try {
      final data = await _anilistService.fetchAnimeDetails(widget.animeId);
      final mappings = await mappingsFuture;

      if (mounted) {
        // Merge episodes list
        final List<dynamic> streaming = data['streamingEpisodes'] ?? [];
        int totalCount = data['episodes'] ?? 
            (data['nextAiringEpisode'] != null 
                ? (data['nextAiringEpisode']['episode'] as int) - 1 
                : streaming.length);

        Map<String, dynamic> aniZipEpisodes = {};
        if (mappings != null && mappings['episodes'] != null) {
          aniZipEpisodes = mappings['episodes'] as Map<String, dynamic>;
          final List<int> epKeys = aniZipEpisodes.keys
              .map((k) => int.tryParse(k) ?? 0)
              .where((k) => k > 0)
              .toList();
          if (epKeys.isNotEmpty) {
            final maxEp = epKeys.reduce(max);
            if (maxEp > totalCount) {
              totalCount = maxEp;
            }
          }
        }
        
        if (totalCount < streaming.length) {
          totalCount = streaming.length;
        }

        // Map streaming episodes by their parsed episode number
        final Map<int, dynamic> streamingMap = {};
        for (var i = 0; i < streaming.length; i++) {
          final ep = streaming[i];
          final title = ep['title'] ?? '';
          final epNum = _extractEpNum(title, i + 1);
          streamingMap[epNum] = ep;
        }

        final List<dynamic> merged = [];
        for (var i = 1; i <= totalCount; i++) {
          final epKey = i.toString();
          final zipEp = aniZipEpisodes[epKey] as Map<String, dynamic>?;

          final String zipTitle = zipEp?['title']?['en'] ?? zipEp?['title']?['x-jat'] ?? zipEp?['title']?['ja'] ?? '';
          final String zipThumb = zipEp?['image'] ?? '';
          final String zipOverview = zipEp?['overview'] ?? zipEp?['summary'] ?? '';
          final String zipAirDate = zipEp?['airDate'] ?? zipEp?['airdate'] ?? '';

          if (streamingMap.containsKey(i)) {
            final streamEp = streamingMap[i];
            merged.add({
              'title': streamEp['title'] ?? (zipTitle.isNotEmpty ? zipTitle : 'Episode $i'),
              'thumbnail': (streamEp['thumbnail'] != null && streamEp['thumbnail'].isNotEmpty) 
                  ? streamEp['thumbnail'] 
                  : zipThumb,
              'url': streamEp['url'] ?? '',
              'site': streamEp['site'] ?? '',
              'overview': zipOverview,
              'airDate': zipAirDate,
              'isPlaceholder': false,
            });
          } else {
            merged.add({
              'title': zipTitle.isNotEmpty ? zipTitle : 'Episode $i',
              'thumbnail': zipThumb,
              'url': '',
              'site': '',
              'overview': zipOverview,
              'airDate': zipAirDate,
              'isPlaceholder': zipTitle.isEmpty,
            });
          }
        }

        setState(() {
          _details = data;
          _mergedEpisodes = merged;
          _isLoading = false;
        });

        // Trigger TMDB mapping
        _initTmdbMapping();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initTmdbMapping() async {
    if (_details == null || !_tmdbService.isConfigured) return;

    final String format = _details!['format'] ?? '';
    final String title = _details!['title']?['english'] ?? _details!['title']?['romaji'] ?? '';
    final int? year = _details!['seasonYear'];

    setState(() {
      _isTmdbLoading = true;
    });

    final tmdbId = await _tmdbService.searchShow(title, year: year, format: format);
    if (tmdbId != null && mounted) {
      _tmdbId = tmdbId;
      if (format.toUpperCase() == 'MOVIE') {
        final movieData = await _tmdbService.fetchMovieDetails(tmdbId);
        if (movieData != null && mounted) {
          setState(() {
            _tmdbEpisodesMap[1] = movieData;
            _isTmdbLoading = false;
          });
        }
      } else {
        final seasons = await _tmdbService.fetchTvSeasons(tmdbId);
        if (mounted) {
          setState(() {
            _tmdbSeasons = seasons;
            
            int tmdbTotalCount = 0;
            for (var season in seasons) {
              tmdbTotalCount += season.episodeCount;
            }
            
            if (tmdbTotalCount > _mergedEpisodes.length) {
              final List<dynamic> expanded = List.from(_mergedEpisodes);
              for (var i = _mergedEpisodes.length + 1; i <= tmdbTotalCount; i++) {
                expanded.add({
                  'title': 'Episode $i',
                  'thumbnail': '',
                  'url': '',
                  'site': '',
                  'overview': '',
                  'airDate': '',
                  'isPlaceholder': true,
                });
              }
              _mergedEpisodes = expanded;
            }
          });
          // Load episode details for the initial page
          await _loadTmdbEpisodesForPage(_activeEpisodePage);
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isTmdbLoading = false;
        });
      }
    }
  }

  Future<void> _loadTmdbEpisodesForPage(int pageIndex) async {
    if (_tmdbId == null || _tmdbSeasons.isEmpty || !_tmdbService.isConfigured) return;

    final int itemsPerPage = 50;
    final int startEp = pageIndex * itemsPerPage + 1;
    final int endEp = min(startEp + itemsPerPage - 1, _mergedEpisodes.length);

    // Find which seasons we need to fetch
    final Set<int> seasonsToFetch = {};
    for (var epNum = startEp; epNum <= endEp; epNum++) {
      if (_tmdbEpisodesMap.containsKey(epNum)) continue; // Already cached

      final mapping = _mapAbsoluteToTmdb(epNum, _tmdbSeasons);
      if (mapping != null) {
        seasonsToFetch.add(mapping['seasonNumber']!);
      }
    }

    if (seasonsToFetch.isEmpty) return;

    setState(() {
      _isTmdbLoading = true;
    });

    // Fetch the required seasons
    for (var seasonNum in seasonsToFetch) {
      final seasonEps = await _tmdbService.fetchSeasonEpisodes(_tmdbId!, seasonNum);
      if (!mounted) return;

      final priorCount = _getPriorEpisodesCount(seasonNum, _tmdbSeasons);
      seasonEps.forEach((seasonEpNum, epData) {
        final absoluteEpNum = priorCount + seasonEpNum;
        _tmdbEpisodesMap[absoluteEpNum] = epData;
      });
    }

    if (mounted) {
      setState(() {
        _isTmdbLoading = false;
      });
    }
  }

  Map<String, int>? _mapAbsoluteToTmdb(int absoluteEp, List<TmdbSeasonInfo> seasons) {
    int accumulated = 0;
    for (var season in seasons) {
      if (absoluteEp > accumulated && absoluteEp <= accumulated + season.episodeCount) {
        final seasonEpIndex = absoluteEp - accumulated;
        return {
          'seasonNumber': season.seasonNumber,
          'episodeNumber': seasonEpIndex,
        };
      }
      accumulated += season.episodeCount;
    }
    return null;
  }

  int _getPriorEpisodesCount(int seasonNum, List<TmdbSeasonInfo> seasons) {
    int count = 0;
    for (var season in seasons) {
      if (season.seasonNumber < seasonNum) {
        count += season.episodeCount;
      }
    }
    return count;
  }

  String _cleanDescription(String? htmlDesc) {
    if (htmlDesc == null) return '';
    final regExp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    String clean = htmlDesc.replaceAll(regExp, '');
    clean = clean
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&rsquo;', "'")
        .replaceAll('&amp;', '&');
    return clean;
  }

  int _extractEpNum(String title, int fallback) {
    final match = RegExp(r"(?:Episode|Ep\.?)\s*(\d+)", caseSensitive: false).firstMatch(title) ??
                  RegExp(r"^(\d+)\s*[-.]").firstMatch(title);
    return match != null ? int.parse(match.group(1)!) : fallback;
  }

  String _cleanEpTitle(String title) {
    final cleaned = title.replaceAll(RegExp(r"^Episode\s*\d+\s*[-–—:·]?\s*", caseSensitive: false), '').trim();
    return cleaned.isNotEmpty ? cleaned : title;
  }

  void _showEpisodeDetails({
    required int epNum,
    required String title,
    required String thumbnail,
    required String site,
    required String overview,
    required String airDate,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: Colors.white10, width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black,
                  blurRadius: 20.0,
                  spreadRadius: 2.0,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Backdrop image with overlay close button
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: thumbnail.isNotEmpty
                              ? Image.network(
                                  thumbnail,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        child: const Center(
                                          child: Icon(Icons.broken_image, size: 48.0, color: Colors.white24),
                                        ),
                                      ),
                                )
                              : Container(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  child: const Center(
                                    child: Icon(Icons.movie, size: 64.0, color: Colors.white24),
                                  ),
                                ),
                        ),
                        // Top gradient overlay
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.black54, Colors.transparent],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),
                        // Close button
                        Positioned(
                          top: 12.0,
                          right: 12.0,
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            radius: 16.0,
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 16.0, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Episode Metadata Badge Row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(4.0),
                                ),
                                child: Text(
                                  'EPISODE $epNum',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ),
                              if (airDate.isNotEmpty) ...[
                                const SizedBox(width: 12.0),
                                Text(
                                  'Aired: $airDate',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12.0,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ],
                              if (site.isNotEmpty) ...[
                                const Spacer(),
                                Text(
                                  site,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12.0,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16.0),
                          
                          // Episode Title
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22.0,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          const SizedBox(height: 12.0),
                          
                          // Episode Overview / Synopsis
                          Text(
                            overview.isNotEmpty ? overview : 'No summary available for this episode.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14.0,
                              height: 1.5,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          const SizedBox(height: 24.0),
                          
                          // Play Action Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.play_arrow, color: Colors.black),
                              label: const Text(
                                'Play Episode',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14.0),
                              ),
                              onPressed: () {
                                Navigator.pop(context);

                                if (_details == null) return;

                                final titles = [
                                  _details!['title']?['english'] ?? '',
                                  _details!['title']?['romaji'] ?? '',
                                  _details!['title']?['native'] ?? '',
                                ].where((t) => t.isNotEmpty).map((t) => t.toString()).toList();

                                _onPlayPressed(epNum, titles);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14.0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6.0),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onPlayPressed(int epNum, List<String> titles) {
    final mapping = BatchMappingService().getMapping(widget.animeId, epNum);
    if (mapping != null) {
      showDialog(
        context: context,
        builder: (context) {
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
                  Navigator.pop(context);
                  _openTorrentSelectorPanel(epNum, titles);
                },
                child: const Text("Search Streams", style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _startDirectPlayback(mapping, epNum, titles);
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
    } else {
      _openTorrentSelectorPanel(epNum, titles);
    }
  }

  void _openTorrentSelectorPanel(int epNum, List<String> titles) {
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
            margin: isMobileSheet ? EdgeInsets.zero : const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C0E),
              borderRadius: isMobileSheet
                  ? const BorderRadius.vertical(top: Radius.circular(16.0))
                  : BorderRadius.circular(12.0),
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
              borderRadius: isMobileSheet
                  ? const BorderRadius.vertical(top: Radius.circular(15.0))
                  : BorderRadius.circular(11.0),
              child: TorrentSelectorPanel(
                anilistId: widget.animeId,
                titles: titles,
                episodeCount: _mergedEpisodes.length,
                episodeNumber: epNum,
                isMovie: (_details!['format']?.toString().toUpperCase() == 'MOVIE'),
                media: _details,
                episodes: _mergedEpisodes,
                tmdbEpisodesMap: _tmdbEpisodesMap,
              ),
            ),
          ),
        );
      },
    );
  }

  void _startDirectPlayback(Map<String, dynamic> mapping, int epNum, List<String> titles) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _DirectPlaybackProgressDialog(
          mapping: mapping,
          episodeNumber: epNum,
          parentContext: context,
          anilistId: widget.animeId,
          titles: titles,
          episodeCount: _mergedEpisodes.length,
          isMovie: (_details!['format']?.toString().toUpperCase() == 'MOVIE'),
          media: _details,
          episodes: _mergedEpisodes,
          tmdbEpisodesMap: _tmdbEpisodesMap,
        );
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

    if (_errorMessage != null || _details == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 40.0),
                const SizedBox(height: 16.0),
                Text(
                  'Error loading anime details:\n$_errorMessage',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24.0),
                ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                  onPressed: () => widget.navigationState.selectAnime(null),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final anime = _details!;
    final title = anime['title']?['english'] ?? anime['title']?['romaji'] ?? 'Untitled';
    final nativeTitle = anime['title']?['native'] ?? '';
    final romajiTitle = anime['title']?['romaji'] ?? '';
    final bannerUrl = anime['bannerImage'] ?? anime['coverImage']?['extraLarge'] ?? '';
    final coverUrl = anime['coverImage']?['large'] ?? '';
    final description = _cleanDescription(anime['description']);
    final double? rating = anime['averageScore'] != null ? (anime['averageScore'] as num).toDouble() : null;
    final String format = anime['format'] ?? '';
    final String status = anime['status'] ?? '';
    final List<dynamic> genres = anime['genres'] ?? [];
    final String studio = (anime['studios']?['nodes'] as List?)?.firstOrNull?['name'] ?? '';
    final String season = anime['season'] ?? '';
    final int? seasonYear = anime['seasonYear'];

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Faded Banner Background (Fitted & Cached)
          if (bannerUrl.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 380.0,
              child: Opacity(
                opacity: 0.35,
                child: Image.network(
                  bannerUrl,
                  fit: BoxFit.cover,
                  cacheWidth: 1280, // Restrict memory consumption of large banner
                  errorBuilder: (context, e, s) => Container(color: Colors.black),
                ),
              ),
            ),

          // Banner bottom gradient fade to black
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 382.0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black,
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.2, 0.6, 1.0],
                ),
              ),
            ),
          ),

          // 2. Main Page Layout (Unified scroll view, scrolling columns side-by-side below)
          Positioned.fill(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(top: 40.0, bottom: 40.0), // Give room for transparent drag handle
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back Button Row (placed at the top-left of the entire details page, overlaying the banner)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18.0),
                            onPressed: () => widget.navigationState.selectAnime(null),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(alpha: 0.5), // Semi-transparent dark background for contrast
                              padding: const EdgeInsets.all(10.0),
                            ),
                          ),
                          const SizedBox(width: 16.0),
                          Expanded(
                            child: Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16.0,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ),
                          if (_isTmdbLoading) ...[
                            const SizedBox(width: 16.0),
                            const SizedBox(
                              width: 16.0,
                              height: 16.0,
                              child: CircularProgressIndicator(
                                color: Colors.white60,
                                strokeWidth: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // A spacer to lower the content down, exposing a good clear banner on top
                    const SizedBox(height: 180.0),

                    // Centered 70% width top/middle section (poster cover, title, description, tabs)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16.0 : 0.0),
                        child: SizedBox(
                          width: isMobile ? double.infinity : MediaQuery.of(context).size.width * 0.7,
                          child: Column(
                            crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                            children: [
                            // Media Header Area (Cover + Info card)
                            isMobile
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // Poster Cover
                                      if (coverUrl.isNotEmpty)
                                        Container(
                                          height: 180.0,
                                          width: 125.0,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8.0),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.8),
                                                blurRadius: 12.0,
                                                offset: const Offset(0, 4),
                                              )
                                            ],
                                            border: Border.all(color: Colors.white10, width: 1.0),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(7.0),
                                            child: Image.network(
                                              coverUrl, 
                                              fit: BoxFit.cover,
                                              cacheWidth: 250,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 16.0),
                                      // Title metadata
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          // Native / Romaji names
                                          if (nativeTitle.isNotEmpty)
                                            Text(
                                              nativeTitle,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 13.0,
                                                fontFamily: 'Outfit',
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (romajiTitle.isNotEmpty && romajiTitle != title) ...[
                                            const SizedBox(height: 2.0),
                                            Text(
                                              romajiTitle,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12.0,
                                                fontFamily: 'Outfit',
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 8.0),

                                          // Big Title
                                          Text(
                                            title,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 22.0,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: -0.5,
                                              fontFamily: 'Outfit',
                                              height: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 12.0),

                                          // Metadata badges row
                                          Wrap(
                                            alignment: WrapAlignment.center,
                                            spacing: 8.0,
                                            runSpacing: 8.0,
                                            children: [
                                              if (format.isNotEmpty) _buildBadge(format),
                                              if (status.isNotEmpty) _buildBadge(status.replaceAll('_', ' ')),
                                              if (studio.isNotEmpty) _buildBadge(studio, isAccent: true),
                                              if (rating != null)
                                                _buildBadge('★ ${(rating / 10).toStringAsFixed(1)}', color: Colors.amber[800]!),
                                              if (season.isNotEmpty && seasonYear != null)
                                                _buildBadge('${season.toLowerCase()} $seasonYear'.toUpperCase()),
                                            ],
                                          ),
                                          const SizedBox(height: 12.0),

                                          // Genres list
                                          Wrap(
                                            alignment: WrapAlignment.center,
                                            spacing: 6.0,
                                            runSpacing: 6.0,
                                            children: genres.map((g) => Chip(
                                              label: Text(g, style: const TextStyle(fontSize: 11.0, color: Colors.white70)),
                                              backgroundColor: Colors.white.withValues(alpha: 0.05),
                                              padding: EdgeInsets.zero,
                                              side: BorderSide.none,
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            )).toList(),
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Poster Cover
                                      if (coverUrl.isNotEmpty)
                                        Container(
                                          height: 220.0,
                                          width: 155.0,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8.0),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.8),
                                                blurRadius: 12.0,
                                                offset: const Offset(0, 4),
                                              )
                                            ],
                                            border: Border.all(color: Colors.white10, width: 1.0),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(7.0),
                                            child: Image.network(
                                              coverUrl, 
                                              fit: BoxFit.cover,
                                              cacheWidth: 310, // Optimizes cover RAM caching (155px * 2)
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 24.0),

                                      // Title metadata
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Native / Romaji names
                                            if (nativeTitle.isNotEmpty)
                                              Text(
                                                nativeTitle,
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 14.0,
                                                  fontFamily: 'Outfit',
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            if (romajiTitle.isNotEmpty && romajiTitle != title) ...[
                                              const SizedBox(height: 2.0),
                                              Text(
                                                romajiTitle,
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 13.0,
                                                  fontFamily: 'Outfit',
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 12.0),

                                            // Big Title
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 28.0,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: -0.5,
                                                fontFamily: 'Outfit',
                                                height: 1.2,
                                              ),
                                            ),
                                            const SizedBox(height: 14.0),

                                            // Metadata badges row
                                            Wrap(
                                              spacing: 8.0,
                                              runSpacing: 8.0,
                                              children: [
                                                if (format.isNotEmpty) _buildBadge(format),
                                                if (status.isNotEmpty) _buildBadge(status.replaceAll('_', ' ')),
                                                if (studio.isNotEmpty) _buildBadge(studio, isAccent: true),
                                                if (rating != null)
                                                  _buildBadge('★ ${(rating / 10).toStringAsFixed(1)}', color: Colors.amber[800]!),
                                                if (season.isNotEmpty && seasonYear != null)
                                                  _buildBadge('${season.toLowerCase()} $seasonYear'.toUpperCase()),
                                              ],
                                            ),
                                            const SizedBox(height: 16.0),

                                            // Genres list
                                            Wrap(
                                              spacing: 6.0,
                                              runSpacing: 6.0,
                                              children: genres.map((g) => Chip(
                                                label: Text(g, style: const TextStyle(fontSize: 11.0, color: Colors.white70)),
                                                backgroundColor: Colors.white.withValues(alpha: 0.05),
                                                padding: EdgeInsets.zero,
                                                side: BorderSide.none,
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              )).toList(),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                            const SizedBox(height: 36.0),

                            // Inner Nav Bar Tabs
                            _buildInnerNavbar(isMobile),
                            const SizedBox(height: 16.0),

                            // Active Tab Content (Description, Characters, or Relations)
                            _buildActiveTabContent(description, anime),
                          ],
                        ),
                      ),
                    ),
                  ),
                    
                    const SizedBox(height: 40.0),
                    
                    // Divider separating headers from lists
                    Container(height: 1.0, color: Colors.white10),
                    const SizedBox(height: 24.0),

                    // Dual Column Section - Takes full width
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: isMobile
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildEpisodesSection(title, isMobile),
                                const SizedBox(height: 40.0),
                                Container(height: 1.0, color: Colors.white10),
                                const SizedBox(height: 24.0),
                                const Text(
                                  'Recommended',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18.0,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                                const SizedBox(height: 16.0),
                                _buildRecommendationsList(anime['recommendations']?['nodes'] ?? []),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left column (Episodes section)
                                Expanded(
                                  flex: 7,
                                  child: _buildEpisodesSection(title, isMobile),
                                ),

                                // Spacer / Divider
                                const SizedBox(width: 24.0),
                                Container(
                                  width: 1.0,
                                  color: Colors.white10,
                                ),
                                const SizedBox(width: 24.0),

                                // Right column (Recommendations section)
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Recommended',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18.0,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                      const SizedBox(height: 16.0),
                                      _buildRecommendationsList(anime['recommendations']?['nodes'] ?? []),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, {bool isAccent = false, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: color ?? (isAccent ? Colors.white24 : Colors.white10),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInnerNavbar(bool isMobile) {
    final tabs = ['Description', 'Characters & Cast', 'Relations'];
    final row = Row(
      mainAxisAlignment: isMobile ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
      children: List.generate(tabs.length, (index) {
        final isSelected = _activeTab == index;
        return GestureDetector(
          onTap: () => setState(() => _activeTab = index),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8.0 : 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 2.0,
                ),
              ),
            ),
            child: Text(
              tabs[index],
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: isMobile ? 12.5 : 14.0,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontFamily: 'Outfit',
              ),
            ),
          ),
        );
      }),
    );

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 1.0)),
      ),
      child: isMobile ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row) : row,
    );
  }

  Widget _buildActiveTabContent(String description, Map<String, dynamic> anime) {
    if (_activeTab == 0) {
      // 0. About / Description
      if (description.isEmpty) {
        return const Text(
          'No description available.',
          style: TextStyle(color: Colors.white38, fontSize: 14.0, fontFamily: 'Outfit'),
        );
      }

      final bool isLong = description.length > 250;
      final String displayText = (isLong && !_isDescriptionExpanded)
          ? '${description.substring(0, 250)}...'
          : description;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14.0,
              height: 1.5,
              fontFamily: 'Outfit',
            ),
          ),
          if (isLong) ...[
            const SizedBox(height: 8.0),
            InkWell(
              onTap: () {
                setState(() {
                  _isDescriptionExpanded = !_isDescriptionExpanded;
                });
              },
              child: Text(
                _isDescriptionExpanded ? 'Read Less' : 'Read More',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.0,
                  fontFamily: 'Outfit',
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      );
    } else if (_activeTab == 1) {
      // 1. Characters & Cast - Redesigned to be smaller & more compact
      final characters = anime['characters']?['edges'] as List? ?? [];
      if (characters.isEmpty) {
        return const Text('No character information available.', style: TextStyle(color: Colors.white54));
      }
      final double screenWidth = MediaQuery.of(context).size.width;
      final bool isMobile = screenWidth < 650;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: isMobile ? 1 : 3,
          crossAxisSpacing: 12.0,
          mainAxisSpacing: 10.0,
          childAspectRatio: isMobile ? 3.6 : 3.2,
        ),
        itemCount: characters.length,
        itemBuilder: (context, index) {
          final edge = characters[index];
          final charName = edge['node']?['name']?['full'] ?? 'Unknown';
          final charPic = edge['node']?['image']?['large'] ?? '';
          final role = edge['role'] ?? '';
          
          final va = (edge['voiceActors'] as List?)?.firstOrNull;
          final vaName = va?['name']?['full'] ?? 'Unknown';

          return Container(
            padding: const EdgeInsets.all(6.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(color: Colors.white10, width: 1.0),
            ),
            child: Row(
              children: [
                // Character circular avatar
                if (charPic.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.0),
                    child: Image.network(
                      charPic, 
                      width: 38.0, 
                      height: double.infinity, 
                      fit: BoxFit.cover,
                      cacheWidth: 80, // Optimize character avatar caching
                    ),
                  ),
                const SizedBox(width: 10.0),
                
                // Character name, role, and seiyuu details
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        charName,
                        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        role,
                        style: const TextStyle(color: Colors.white38, fontSize: 9.0),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        'VA: $vaName',
                        style: const TextStyle(color: Colors.white70, fontSize: 10.0),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else {
      // 2. Relations
      final relations = anime['relations']?['edges'] as List? ?? [];
      if (relations.isEmpty) {
        return const Text('No related anime found.', style: TextStyle(color: Colors.white54));
      }
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: relations.length,
        itemBuilder: (context, index) {
          final edge = relations[index];
          final relationType = edge['relationType'] ?? '';
          final node = edge['node'] ?? {};
          final nodeTitle = node['title']?['english'] ?? node['title']?['romaji'] ?? 'Untitled';
          final nodeCover = node['coverImage']?['large'] ?? '';
          final nodeFormat = node['format'] ?? '';
          final nodeStatus = node['status'] ?? '';
          final nodeId = node['id'];

          return Container(
            margin: const EdgeInsets.only(bottom: 8.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.01),
              borderRadius: BorderRadius.circular(6.0),
            ),
            child: ListTile(
              leading: nodeCover.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4.0),
                      child: Image.network(
                        nodeCover, 
                        width: 40.0, 
                        height: double.infinity, 
                        fit: BoxFit.cover,
                        cacheWidth: 80, // Optimize relation thumb caching
                      ),
                    )
                  : null,
              title: Text(nodeTitle, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
              subtitle: Text(
                '${relationType.replaceAll('_', ' ')} · $nodeFormat · $nodeStatus',
                style: const TextStyle(color: Colors.white38, fontSize: 11.0),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white30),
              onTap: node['type'] == 'ANIME' && nodeId != null
                  ? () => widget.navigationState.selectAnime(nodeId)
                  : null,
            ),
          );
        },
      );
    }
  }

  Widget _buildEpisodesSection(String showTitle, bool isMobile) {
    if (_mergedEpisodes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Episodes',
            style: TextStyle(color: Colors.white, fontSize: 20.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          SizedBox(height: 16.0),
          Center(
            child: Text('No episode details available.', style: TextStyle(color: Colors.white38)),
          ),
        ],
      );
    }

    // Pagination calculations
    final int itemsPerPage = 50;
    final int totalPages = (_mergedEpisodes.length / itemsPerPage).ceil();

    // Bound check active page index
    if (_activeEpisodePage >= totalPages) {
      _activeEpisodePage = 0;
    }

    final int startIdx = _activeEpisodePage * itemsPerPage;
    final int endIdx = min(startIdx + itemsPerPage, _mergedEpisodes.length);

    final List<dynamic> pagedList = _mergedEpisodes.sublist(startIdx, endIdx);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Episodes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
            Text(
              '${_mergedEpisodes.length} Episodes total',
              style: const TextStyle(color: Colors.white38, fontSize: 12.0),
            ),
          ],
        ),
        const SizedBox(height: 16.0),

        // Render Pagination selector row if we have multiple pages
        if (totalPages > 1) ...[
          SizedBox(
            height: 38.0,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: totalPages,
              itemBuilder: (context, index) {
                final int pageStart = index * itemsPerPage + 1;
                final int pageEnd = min((index + 1) * itemsPerPage, _mergedEpisodes.length);
                final isSelected = _activeEpisodePage == index;

                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _activeEpisodePage = index;
                      });
                      // Lazy-load TMDB metadata for this new page
                      _loadTmdbEpisodesForPage(index);
                    },
                    borderRadius: BorderRadius.circular(4.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4.0),
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.white10,
                          width: 1.0,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$pageStart-$pageEnd',
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontSize: 12.0,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20.0),
        ],

        // Grid View of Paged Episodes
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isMobile ? 2 : 3,
            crossAxisSpacing: isMobile ? 10.0 : 14.0,
            mainAxisSpacing: isMobile ? 10.0 : 14.0,
            childAspectRatio: 1.45,
          ),
          itemCount: pagedList.length,
          itemBuilder: (context, index) {
            final ep = pagedList[index];
            final String epTitle = ep['title'] ?? '';
            final String thumbnail = ep['thumbnail'] ?? '';
            final int epNum = ep['isPlaceholder'] == true ? (startIdx + index + 1) : _extractEpNum(epTitle, startIdx + index + 1);
            final String cleanTitle = ep['isPlaceholder'] == true ? epTitle : _cleanEpTitle(epTitle);
            final String site = ep['site'] ?? '';

            // Check TMDB overrides
            final tmdbEp = _tmdbEpisodesMap[epNum];
            final String finalTitle = tmdbEp?['name'] ?? cleanTitle;
            final String finalThumbnail = tmdbEp?['still_path'] ?? thumbnail;
            final String finalSite = site;

            return _EpisodeCard(
              epNum: epNum,
              title: finalTitle,
              thumbnail: finalThumbnail,
              site: finalSite,
              onTap: () {
                final String overview = tmdbEp?['overview'] ?? '';
                final String airDate = tmdbEp?['air_date'] ?? '';
                _showEpisodeDetails(
                  epNum: epNum,
                  title: finalTitle,
                  thumbnail: finalThumbnail,
                  site: finalSite,
                  overview: overview,
                  airDate: airDate,
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecommendationsList(List<dynamic> list) {
    final List<dynamic> recs = list
        .where((r) => r['mediaRecommendation'] != null && r['mediaRecommendation']['type'] == 'ANIME')
        .toList();

    if (recs.isEmpty) {
      return const Text('No recommendations found.', style: TextStyle(color: Colors.white38));
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recs.length,
      itemBuilder: (context, index) {
        final rec = recs[index]['mediaRecommendation'];
        final String recTitle = rec['title']?['english'] ?? rec['title']?['romaji'] ?? 'Untitled';
        final String cover = rec['coverImage']?['large'] ?? '';
        final double? score = rec['averageScore'] != null ? (rec['averageScore'] as num).toDouble() : null;
        final String format = rec['format'] ?? '';
        final int recId = rec['id'];

        return _RecommendationTile(
          id: recId,
          title: recTitle,
          coverUrl: cover,
          score: score,
          format: format,
          onTap: () => widget.navigationState.selectAnime(recId),
        );
      },
    );
  }
}

class _EpisodeCard extends StatefulWidget {
  final int epNum;
  final String title;
  final String thumbnail;
  final String site;
  final VoidCallback onTap;

  const _EpisodeCard({
    required this.epNum,
    required this.title,
    required this.thumbnail,
    required this.site,
    required this.onTap,
  });

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
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
                  child: Stack(
                    children: [
                      // Thumbnail image
                      Positioned.fill(
                        child: AnimatedScale(
                          scale: _isHovered ? 1.05 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: widget.thumbnail.isNotEmpty
                              ? Image.network(
                                  widget.thumbnail,
                                  fit: BoxFit.cover,
                                  cacheWidth: 320, // Optimize episode thumbnail caching (width is ~160px)
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return Container(color: Colors.grey[950]);
                                  },
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildEpisodePlaceholder(),
                                )
                              : _buildEpisodePlaceholder(),
                        ),
                      ),
                      
                      // Play Icon overlay
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

                      // Episode Number Badge (Top-Left)
                      Positioned(
                        top: 8.0,
                        left: 8.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: Text(
                            'EP ${widget.epNum}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      // Site badge (Bottom-Right)
                      if (widget.site.isNotEmpty)
                        Positioned(
                          bottom: 6.0,
                          right: 6.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(3.0),
                            ),
                            child: Text(
                              widget.site,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 8.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6.0),
            
            // Episode Title under card
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _isHovered ? Colors.white : Colors.white70,
                fontSize: 12.0,
                fontWeight: FontWeight.w500,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodePlaceholder() {
    return Container(
      color: Colors.grey[950],
      child: Center(
        child: Text(
          '${widget.epNum}',
          style: const TextStyle(
            color: Colors.white12,
            fontSize: 40.0,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _RecommendationTile extends StatefulWidget {
  final int id;
  final String title;
  final String coverUrl;
  final double? score;
  final String format;
  final VoidCallback onTap;

  const _RecommendationTile({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.score,
    required this.format,
    required this.onTap,
  });

  @override
  State<_RecommendationTile> createState() => _RecommendationTileState();
}

class _RecommendationTileState extends State<_RecommendationTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 12.0),
          padding: const EdgeInsets.all(6.0),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
            borderRadius: BorderRadius.circular(6.0),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover thumbnail
              if (widget.coverUrl.isNotEmpty)
                Container(
                  width: 55.0,
                  height: 75.0,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4.0),
                    border: Border.all(color: Colors.white10, width: 1.0),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3.0),
                    child: Image.network(
                      widget.coverUrl, 
                      fit: BoxFit.cover,
                      cacheWidth: 110, // Optimizes RAM of recommendation thumb
                    ),
                  ),
                ),
              const SizedBox(width: 12.0),

              // Title and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _isHovered ? Colors.white : Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Outfit',
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    Row(
                      children: [
                        if (widget.format.isNotEmpty)
                          Text(
                            widget.format,
                            style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                          ),
                        if (widget.format.isNotEmpty && widget.score != null)
                          const Text(' · ', style: TextStyle(color: Colors.white38)),
                        if (widget.score != null) ...[
                          const Icon(Icons.star, color: Colors.amber, size: 10.0),
                          const SizedBox(width: 2.0),
                          Text(
                            (widget.score! / 10).toStringAsFixed(1),
                            style: const TextStyle(color: Colors.amber, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
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
  final int anilistId;
  final List<String> titles;
  final int episodeCount;
  final bool isMovie;
  final Map<String, dynamic>? media;
  final List<dynamic> episodes;
  final Map<int, dynamic> tmdbEpisodesMap;

  const _DirectPlaybackProgressDialog({
    required this.mapping,
    required this.episodeNumber,
    required this.parentContext,
    required this.anilistId,
    required this.titles,
    required this.episodeCount,
    required this.isMovie,
    this.media,
    required this.episodes,
    required this.tmdbEpisodesMap,
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
          throw Exception("TorrServer is not running. Please restart the app.");
        }
      }

      setState(() {
        _status = "Adding torrent & loading file...";
      });

      final torrentInfo = await _torrServerService.addTorrent(
        widget.mapping['torrentLink'],
        title: widget.mapping['torrentTitle'] ?? 'Batch Torrent',
      );

      final fileIndex = widget.mapping['fileIndex'] as int;
      final fileExists = torrentInfo.files.any((f) => f.index == fileIndex);
      if (!fileExists) {
        throw Exception("Mapped file index no longer exists in torrent.");
      }

      final file = torrentInfo.files.firstWhere((f) => f.index == fileIndex);

      _playingFile = file;
      _playingHash = torrentInfo.hash;

      if (!mounted) return;

      // Prebuffering phase inside the dialog
      setState(() {
        _status = "Preloading stream...";
      });

      await _torrServerService.preloadTorrentFile(torrentInfo.hash, file.index);

      int secondsElapsed = 0;
      bool isReady = false;
      while (secondsElapsed < 20 && !isReady) {
        await Future.delayed(const Duration(seconds: 1));
        secondsElapsed++;
        if (!mounted) return;

        try {
          final updatedInfo = await _torrServerService.getTorrent(torrentInfo.hash);
          final speedMb = updatedInfo.downloadSpeed / (1024 * 1024);
          setState(() {
            _status = "Prebuffering stream...\n"
                "${speedMb.toStringAsFixed(1)} MB/s • ${updatedInfo.activePeers} peers\n"
                "State: ${updatedInfo.stat.isNotEmpty ? updatedInfo.stat : 'Buffering'}";
          });

          if (updatedInfo.statCode >= 5) {
            isReady = true;
          }
        } catch (e) {
          debugPrint("Error polling prebuffer: $e");
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(); // pop progress dialog
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
    
    final navigator = Navigator.of(widget.parentContext);
    navigator.push(
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          streamUrl: streamUrl,
          title: fileName.isNotEmpty ? fileName : file.name,
          anilistId: widget.anilistId,
          titles: widget.titles,
          episodeCount: widget.episodeCount,
          episodeNumber: widget.episodeNumber,
          isMovie: widget.isMovie,
          media: widget.media,
          episodes: widget.episodes,
          tmdbEpisodesMap: widget.tmdbEpisodesMap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0F11),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_hasError) ...[
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Outfit', height: 1.4),
              ),
              if (_playingFile != null && _playingHash != null) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // pop dialog
                    _navigateToPlayer(_playingHash!, _playingFile!);
                  },
                  child: const Text("Skip Buffering", style: TextStyle(color: Colors.white54, fontSize: 12.0)),
                ),
              ],
            ] else ...[
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text(
                "Direct Playback Failed",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Close", style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _errorMessage = "";
                        _playingFile = null;
                        _playingHash = null;
                      });
                      _startPlayback();
                    },
                    child: const Text("Retry"),
                  ),
                ],
              )
            ],
          ],
        ),
      ),
    );
  }
}

