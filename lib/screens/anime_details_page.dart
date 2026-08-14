import '../services/notification_service.dart';
import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../services/anilist_service.dart';
import '../services/extension_service.dart';
import '../services/tmdb_service.dart';
import '../services/tvdb_service.dart';
import '../services/filler_service.dart';
import '../services/batch_mapping_service.dart';
import '../services/torrserver_service.dart';
import '../services/torrserver_manager.dart';
import '../services/download_service.dart';
import '../screens/player_screen.dart';
import '../state/navigation_state.dart';
import '../state/player_state.dart';
import '../widgets/torrent_selector_panel.dart';
import '../services/hstream_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/torrent.dart';
import '../widgets/poster_image_viewer.dart';
import '../widgets/smooth_scroll_area.dart';
import '../state/library_state.dart';

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

  // Continue watching state
  int _continueEpisode = 1;
  bool _continueEpisodeFinished = false;
  String? _continueStreamUrl;
  String? _continueStreamTitle;
  bool _hasCheckedContinue = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadDetails();
      }
    });
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

        final bool isHentai = (data['genres'] as List<dynamic>? ?? []).contains('Hentai');
        int hstreamMaxEp = 0;
        if (isHentai) {
          final titlesList = <String>[];
          if (data['title']['english'] != null) titlesList.add(data['title']['english']);
          if (data['title']['romaji'] != null) titlesList.add(data['title']['romaji']);
          if (data['title']['native'] != null) titlesList.add(data['title']['native']);
          if (data['synonyms'] != null) {
            titlesList.addAll((data['synonyms'] as List<dynamic>).map((s) => s.toString()));
          }
          
          final service = HstreamService();
          final searchTerms = service.generateSearchTerms(titlesList);
          
          int maxEp = 1;
          List<HstreamResult> results = [];
          for (final term in searchTerms) {
            results = await service.search(term);
            if (results.isNotEmpty) break;
          }
          
          for (final r in results) {
            final path = Uri.tryParse(r.url)?.pathSegments.lastOrNull ?? '';
            final lastPart = path.split('-').lastOrNull ?? '';
            final epNum = int.tryParse(lastPart);
            if (epNum != null && epNum > maxEp) {
              maxEp = epNum;
            }
          }
          if (maxEp > totalCount) {
            totalCount = maxEp;
          }
          hstreamMaxEp = maxEp;
        }

        final Map<int, Map<String, dynamic>> localAniZipMap = {};
        if (mappings != null && mappings['episodes'] != null) {
          final rawEpisodes = mappings['episodes'] as Map<String, dynamic>;
          rawEpisodes.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              final epNumStr = value['episode']?.toString() ?? value['episodeNumber']?.toString() ?? key;
              final epNum = int.tryParse(epNumStr);
              if (epNum != null) {
                localAniZipMap[epNum] = value;
              }
            }
          });
        }

        int? maxAiredEp;
        if (data['nextAiringEpisode'] != null && data['nextAiringEpisode']['episode'] != null) {
          maxAiredEp = (data['nextAiringEpisode']['episode'] as int) - 1;
        }

        totalCount = data['episodes'] ?? (maxAiredEp ?? 0);
        if (localAniZipMap.isNotEmpty) {
          final maxZip = localAniZipMap.keys.reduce(max);
          if (maxZip > totalCount && maxAiredEp == null) {
            totalCount = maxZip;
          }
        }
        if (maxAiredEp != null && maxAiredEp > 0) {
          totalCount = maxAiredEp;
        }
        if (totalCount == 0 && streaming.isNotEmpty) {
          totalCount = streaming.length;
        }
        if (totalCount == 0) {
          totalCount = 1;
        }

        // Re-apply hentai episode count — must come AFTER the step C reassignment
        if (isHentai && hstreamMaxEp > totalCount) {
          totalCount = hstreamMaxEp;
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
          final zipEp = localAniZipMap[i];
          final int? absEpNum = zipEp != null
              ? int.tryParse(zipEp['absoluteEpisodeNumber']?.toString() ?? '')
              : null;

          final String zipTitle = zipEp?['title']?['en'] ?? zipEp?['title']?['x-jat'] ?? zipEp?['title']?['ja'] ?? '';
          final String zipThumb = zipEp?['image'] ?? '';
          final String zipOverview = zipEp?['overview'] ?? zipEp?['summary'] ?? '';
          final String zipAirDate = zipEp?['airDate'] ?? zipEp?['airdate'] ?? '';

          if (streamingMap.containsKey(i)) {
            final streamEp = streamingMap[i];
            final String streamRawTitle = streamEp['title'] ?? '';
            final String streamTitle = (streamRawTitle.isEmpty || streamRawTitle.toLowerCase() == 'untitled')
                ? ''
                : streamRawTitle;
            merged.add({
              'title': streamTitle.isNotEmpty
                  ? streamTitle
                  : (zipTitle.isNotEmpty ? zipTitle : 'Episode $i'),
              'thumbnail': (streamEp['thumbnail'] != null && streamEp['thumbnail'].isNotEmpty) 
                  ? streamEp['thumbnail'] 
                  : zipThumb,
              'url': streamEp['url'] ?? '',
              'site': streamEp['site'] ?? '',
              'overview': zipOverview,
              'airDate': zipAirDate,
              'isPlaceholder': false,
              'absoluteEpisodeNumber': absEpNum,
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
              'absoluteEpisodeNumber': absEpNum,
            });
          }
        }

        setState(() {
          _details = data;
          _mergedEpisodes = merged;
          _isLoading = false;
        });

        // Cache details and merged episodes list if in library
        if (LibraryState().isSaved(widget.animeId, 'anime')) {
          data['cachedEpisodes'] = merged;
          LibraryState().updateAnimeCache(widget.animeId, data);
        }

        // Trigger TMDB mapping
        _initTmdbMapping();
        _loadPlaybackProgress();

        // Load filler details
        final List<String> fillerTitles = [];
        if (data['title'] != null) {
          if (data['title']['english'] != null) fillerTitles.add(data['title']['english']);
          if (data['title']['romaji'] != null) fillerTitles.add(data['title']['romaji']);
          if (data['title']['native'] != null) fillerTitles.add(data['title']['native']);
        }
        if (data['synonyms'] != null) {
          fillerTitles.addAll((data['synonyms'] as List<dynamic>).map((s) => s.toString()));
        }
        FillerService().loadFillerData(widget.animeId, fillerTitles).then((_) {
          if (mounted) {
            setState(() {});
          }
        });
      }
    } catch (e) {
      final cached = LibraryState().animeCache[widget.animeId];
      if (cached != null) {
        final List<dynamic> merged = cached['cachedEpisodes'] as List<dynamic>? ?? [];
        if (merged.isEmpty) {
          final int episodesCount = cached['episodes'] ?? 0;
          for (var i = 1; i <= episodesCount; i++) {
            merged.add({
              'title': 'Episode $i',
              'thumbnail': '',
              'url': '',
              'site': '',
              'overview': 'Offline mode: details loaded from cache.',
              'airDate': '',
              'isPlaceholder': true,
            });
          }
        }
        if (mounted) {
          setState(() {
            _details = cached;
            _mergedEpisodes = merged;
            _isLoading = false;
            _errorMessage = null;
          });
          _loadPlaybackProgress();
        }
        return;
      }
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPlaybackProgress() async {
    if (_mergedEpisodes.isEmpty) return;
    final List<int> epNums = [];
    for (var i = 0; i < _mergedEpisodes.length; i++) {
      final ep = _mergedEpisodes[i];
      final String epTitle = ep['title'] ?? '';
      final int epNum = ep['isPlaceholder'] == true ? (i + 1) : _extractEpNum(epTitle, i + 1);
      epNums.add(epNum);
    }
    await PlayerState().loadProgressForAnime(widget.animeId, epNums);

    // Determine the Continue Watching details
    final prefs = await SharedPreferences.getInstance();
    final int lastEp = prefs.getInt('anime_continue_watching_last_ep_${widget.animeId}') ?? 1;
    final pb = PlayerState().getProgress(widget.animeId, lastEp);
    final pos = pb?.position ?? prefs.getInt('anime_playback_pos_${widget.animeId}_$lastEp');
    final dur = pb?.duration ?? prefs.getInt('anime_playback_dur_${widget.animeId}_$lastEp');

    int targetEp = lastEp;
    bool finished = false;
    if (pos != null && dur != null && dur > 0) {
      final ratio = pos / dur;
      if (ratio >= 0.90) {
        finished = true;
        if (lastEp < _mergedEpisodes.length) {
          targetEp = lastEp + 1;
        }
      }
    }

    final savedStream = prefs.getString('playback_stream_${widget.animeId}_$targetEp');
    final savedTitle = prefs.getString('playback_title_${widget.animeId}_$targetEp');

    if (mounted) {
      setState(() {
        _continueEpisode = targetEp;
        _continueEpisodeFinished = finished;
        _continueStreamUrl = savedStream;
        _continueStreamTitle = savedTitle;
        _hasCheckedContinue = true;
      });
    }
  }

  Future<void> _toggleEpisodeWatchedStatus(int epNum, bool currentlyWatched) async {
    final library = LibraryState();
    final item = library.getItem(widget.animeId, 'anime');

    if (!currentlyWatched) {
      await PlayerState().markEpisodeWatched(widget.animeId, epNum);

      final int currentWatched = item?.watchedEpisodes ?? 0;
      final int newWatched = max<int>(currentWatched, epNum);
      if (item != null) {
        await library.saveItem(
          id: item.id,
          mode: item.mode,
          format: item.format,
          libraryStatus: item.libraryStatus,
          rating: item.rating,
          watchedEpisodes: newWatched,
          totalEpisodes: item.totalEpisodes,
          categoryIds: item.categoryIds,
        );
      }
    } else {
      await PlayerState().clearEpisodeProgress(widget.animeId, epNum);

      if (item != null && item.watchedEpisodes >= epNum) {
        await library.saveItem(
          id: item.id,
          mode: item.mode,
          format: item.format,
          libraryStatus: item.libraryStatus,
          rating: item.rating,
          watchedEpisodes: max<int>(0, epNum - 1),
          totalEpisodes: item.totalEpisodes,
          categoryIds: item.categoryIds,
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _markEpisodesUpToWatched(int epNum) async {
    final library = LibraryState();
    final item = library.getItem(widget.animeId, 'anime');

    final List<int> epNums = List.generate(epNum, (i) => i + 1);
    await PlayerState().markMultipleEpisodesWatched(widget.animeId, epNums);

    if (item != null) {
      final int currentWatched = item.watchedEpisodes;
      final int newWatched = max<int>(currentWatched, epNum);
      await library.saveItem(
        id: item.id,
        mode: item.mode,
        format: item.format,
        libraryStatus: item.libraryStatus,
        rating: item.rating,
        watchedEpisodes: newWatched,
        totalEpisodes: item.totalEpisodes,
        categoryIds: item.categoryIds,
      );
    }
    if (mounted) setState(() {});
  }

  Widget _buildContinueButton(bool isMobile) {
    if (!_hasCheckedContinue) return const SizedBox.shrink();
    
    final labelText = _continueEpisode == 1 && !_continueEpisodeFinished && _continueStreamUrl == null
        ? 'Start Watching'
        : 'Continue Ep $_continueEpisode';
        
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Row(
        mainAxisAlignment: isMobile ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow, color: Colors.black, size: 20.0),
            label: Text(
              labelText,
              style: const TextStyle(
                color: Colors.black, 
                fontWeight: FontWeight.bold, 
                fontFamily: 'Outfit',
                fontSize: 13.5,
              ),
            ),
            onPressed: _onContinuePressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              elevation: 4.0,
            ),
          ),
        ],
      ),
    );
  }

  void _onContinuePressed() {
    if (_details == null) return;
    
    final titles = [
      _details!['title']?['english'] ?? '',
      _details!['title']?['romaji'] ?? '',
      _details!['title']?['native'] ?? '',
    ].where((t) => t.isNotEmpty).map((t) => t.toString()).toList();
    if (_details!['synonyms'] != null) {
      titles.addAll((_details!['synonyms'] as List<dynamic>).map((s) => s.toString()));
    }
    
    if (_continueStreamUrl != null && _continueStreamUrl!.isNotEmpty) {
      PlayerState().startPlayback(
        streamUrl: _continueStreamUrl!,
        title: _continueStreamTitle ?? 'Episode $_continueEpisode',
        anilistId: widget.animeId,
        titles: titles,
        episodeCount: _mergedEpisodes.length,
        episodeNumber: _continueEpisode,
        isMovie: (_details!['format']?.toString().toUpperCase() == 'MOVIE'),
        media: _details,
        episodes: _mergedEpisodes,
      );
    } else {
      _onPlayPressed(_continueEpisode, titles);
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

    // Prefer AniZip's direct themoviedb_id mapping (accurate) over TMDB title search (may mismatch)
    int? tmdbId;
    final mappings = await ExtensionService().getMappings(widget.animeId);
    if (mappings != null && mappings['mappings'] != null) {
      final tmdbIdVal = mappings['mappings']['themoviedb_id'];
      tmdbId = tmdbIdVal != null ? int.tryParse(tmdbIdVal.toString()) : null;
    }
    // Fallback to title search if AniZip has no TMDB ID
    tmdbId ??= await _tmdbService.searchShow(title, year: year, format: format);
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
        final seasons = await _tmdbService.fetchTvSeasons(tmdbId);
        if (mounted) {
          setState(() {
            _tmdbSeasons = seasons;
            
            int tmdbTotalCount = 0;
            for (var season in seasons) {
              tmdbTotalCount += season.episodeCount;
            }
            
            final int aniListEpCount = _details!['episodes'] ?? 0;
            final List<dynamic> expanded = List.from(_mergedEpisodes);
            
            if (aniListEpCount == 0 && tmdbTotalCount > _mergedEpisodes.length) {
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
            }
            
            for (var i = 0; i < expanded.length; i++) {
              final ep = expanded[i];
              final int absEp = ep['absoluteEpisodeNumber'] as int? ?? (i + 1);
              final mapping = _mapAbsoluteToTmdb(absEp, seasons);
              if (mapping != null) {
                expanded[i] = Map<String, dynamic>.from(ep)
                  ..['seasonNumber'] = mapping['seasonNumber']
                  ..['episodeNumber'] = mapping['episodeNumber']
                  ..['absoluteEpisodeNumber'] = absEp;
              }
            }
            
            _mergedEpisodes = expanded;
          });
          _loadPlaybackProgress();
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

        if (absoluteEpNum >= 1 && absoluteEpNum <= _mergedEpisodes.length) {
          final ep = _mergedEpisodes[absoluteEpNum - 1];
          final Map<String, dynamic> updatedEp = Map<String, dynamic>.from(ep);

          updatedEp['seasonNumber'] = seasonNum;
          updatedEp['episodeNumber'] = seasonEpNum;
          updatedEp['absoluteEpisodeNumber'] = absoluteEpNum;

          final stillPath = epData['still_path'] as String? ?? '';
          if (stillPath.isNotEmpty) {
            final existingThumb = ep['thumbnail'] as String? ?? '';
            final isFallback = existingThumb.isEmpty ||
                existingThumb.contains('anilist.co/img') ||
                existingThumb.contains('/cover/') ||
                existingThumb.contains('/banners/') ||
                existingThumb.contains('thetvdb.com');
            if (isFallback) {
              updatedEp['thumbnail'] = stillPath;
            }
          }

          final String epTitle = epData['name'] as String? ?? '';
          final String existingTitle = ep['title'] as String? ?? '';
          if (epTitle.isNotEmpty && (existingTitle.isEmpty || existingTitle.startsWith('Episode '))) {
            updatedEp['title'] = epTitle;
          }

          final String epOverview = epData['overview'] as String? ?? '';
          final String existingOverview = ep['overview'] as String? ?? '';
          if (epOverview.isNotEmpty && existingOverview.isEmpty) {
            updatedEp['overview'] = epOverview;
          }

          updatedEp['isPlaceholder'] = false;
          _mergedEpisodes[absoluteEpNum - 1] = updatedEp;
        }
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

  String _cleanEpTitle(String title, [int? epNum]) {
    if (title.isEmpty || title.toLowerCase() == 'untitled' || title.toLowerCase() == 'tba') {
      return epNum != null ? 'Episode $epNum' : title;
    }
    final cleaned = title.replaceAll(RegExp(r"^Episode\s*\d+\s*[-–—:·]?\s*", caseSensitive: false), '').trim();
    if (cleaned.isEmpty || cleaned.toLowerCase() == 'untitled' || cleaned.toLowerCase() == 'tba') {
      return epNum != null ? 'Episode $epNum' : title;
    }
    return cleaned;
  }

  void _showEpisodeDetails({
    required int epNum,
    required String title,
    required String thumbnail,
    required String site,
    required String overview,
    required String airDate,
    required bool isWatched,
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
                              ? CachedNetworkImage(
                                  imageUrl: thumbnail,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 640,
                                  placeholder: (context, url) => Container(color: Colors.white.withValues(alpha: 0.05)),
                                  errorWidget: (context, error, stackTrace) =>
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
                                    child: Icon(Icons.broken_image, size: 48.0, color: Colors.white24),
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
                                if (_details!['synonyms'] != null) {
                                  titles.addAll((_details!['synonyms'] as List<dynamic>).map((s) => s.toString()));
                                }

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
                          const SizedBox(height: 12.0),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.download, color: Colors.white),
                              label: const Text(
                                'Download Episode',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.0),
                              ),
                              onPressed: () {
                                Navigator.pop(context);

                                if (_details == null) return;

                                final titles = [
                                  _details!['title']?['english'] ?? '',
                                  _details!['title']?['romaji'] ?? '',
                                  _details!['title']?['native'] ?? '',
                                ].where((t) => t.isNotEmpty).map((t) => t.toString()).toList();
                                if (_details!['synonyms'] != null) {
                                  titles.addAll((_details!['synonyms'] as List<dynamic>).map((s) => s.toString()));
                                }

                                if (_isHentai) {
                                  _downloadHstreamEpisode(epNum, titles);
                                } else {
                                  _openTorrentSelectorPanel(epNum, titles, isDownload: true);
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24),
                                padding: const EdgeInsets.symmetric(vertical: 14.0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6.0),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12.0),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: Icon(
                                isWatched ? Icons.remove_done : Icons.check_circle_outline,
                                color: isWatched ? const Color(0xFFFF9F1C) : const Color(0xFF2EC4B6),
                              ),
                              label: Text(
                                isWatched ? 'Mark as Unwatched' : 'Mark as Watched',
                                style: TextStyle(
                                  color: isWatched ? const Color(0xFFFF9F1C) : const Color(0xFF2EC4B6),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.0,
                                ),
                              ),
                              onPressed: () async {
                                Navigator.pop(context);
                                await _toggleEpisodeWatchedStatus(epNum, isWatched);
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: (isWatched ? const Color(0xFFFF9F1C) : const Color(0xFF2EC4B6)).withValues(alpha: 0.5),
                                ),
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

  void _playLocalFile(DownloadTask task) {
    final file = File(task.savePath);
    if (!file.existsSync()) {
      NotificationService().show(context, "Local download file not found! It might have been deleted from storage.", isError: true);
      return;
    }

    PlayerState().startPlayback(
      streamUrl: task.savePath,
      title: task.title,
      anilistId: task.anilistId,
      titles: task.titles ?? const [],
      episodeCount: task.episodeCount ?? 0,
      episodeNumber: task.episodeNumber ?? 1,
      isMovie: task.isMovie ?? false,
      media: task.mediaJson != null ? jsonDecode(task.mediaJson!) : null,
      episodes: task.episodesJson != null ? jsonDecode(task.episodesJson!) : null,
    );
  }

  void _onPlayPressed(int epNum, List<String> titles) {
    DownloadTask? downloadedTask;
    for (var task in DownloadService().tasks) {
      if (task.anilistId == widget.animeId &&
          task.episodeNumber == epNum &&
          task.status == DownloadStatus.completed) {
        downloadedTask = task;
        break;
      }
    }

    if (downloadedTask != null) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0F0F11),
            title: const Text(
              "Play Downloaded Episode?",
              style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 16.0, fontWeight: FontWeight.bold),
            ),
            content: Text(
              "A downloaded version of Episode $epNum is available locally.\n\nWould you like to play the downloaded file offline or stream it online?",
              style: const TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit', height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _proceedToPlayFlow(epNum, titles);
                },
                child: const Text("Stream Online", style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _playLocalFile(downloadedTask!);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                child: const Text("Play Offline", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    } else {
      _proceedToPlayFlow(epNum, titles);
    }
  }

  /// Returns true if the loaded anime has the 'Hentai' genre.
  bool get _isHentai {
    final genres = (_details?['genres'] as List<dynamic>? ?? []);
    return genres.any((g) => g.toString().toLowerCase() == 'hentai');
  }

  void _proceedToPlayFlow(int epNum, List<String> titles) {
    // Hentai titles use hstream.moe directly — no torrent panel needed.
    if (_isHentai) {
      _playHstream(epNum, titles);
      return;
    }

    final mapping = BatchMappingService().getMapping(widget.animeId.toString(), epNum);
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

  /// Searches hstream.moe and plays the best matching source directly.
  Future<void> _playHstream(int epNum, List<String> titles) async {
    if (!mounted) return;

    // Show a loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _HstreamLoadingDialog(),
    );

    try {
      final service = HstreamService();

      // Search using each title variant until we get results
      final searchTerms = service.generateSearchTerms(titles);
      List<HstreamResult> results = [];
      for (final term in searchTerms) {
        results = await service.search(term);
        if (results.isNotEmpty) break;
      }

      if (!mounted) return;

      if (results.isEmpty) {
        Navigator.pop(context); // close loading
        NotificationService().show(
          context,
          'No streams found for this title.',
          isError: true,
        );
        return;
      }

      // Pick best result matching the episode number
      HstreamResult? best;
      for (final r in results) {
        final lastSeg = Uri.tryParse(r.url)?.pathSegments.lastOrNull ?? '';
        // Try: trailing number after last dash
        if (int.tryParse(lastSeg.split('-').lastOrNull ?? '') == epNum) {
          best = r;
          break;
        }
        // Try: any trailing digit sequence (e.g. 'natsuzuma-ep2' -> '2')
        final trailingNum = RegExp(r'(\d+)$').firstMatch(lastSeg)?.group(1);
        if (trailingNum != null && int.tryParse(trailingNum) == epNum) {
          best = r;
          break;
        }
      }

      if (best == null) {
        for (final r in results) {
          final title = r.title.toLowerCase();
          final regex = RegExp(r'(?:^|\b|[-_])' + epNum.toString() + r'(?:\b|$)', caseSensitive: false);
          if (regex.hasMatch(title)) {
            best = r;
            break;
          }
        }
      }

      if (best == null) {
        // Only use first result as fallback if it has a strong enough title match
        final topResult = results.first;
        if (topResult.score >= 0.6) {
          best = topResult;
        } else {
          if (mounted) Navigator.pop(context);
          NotificationService().show(
            context,
            'Could not find a confident match on HStream for this title.',
            isError: true,
          );
          return;
        }
      }
      final streams = await service.getStreams(best.url);

      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (streams == null || streams.sources.isEmpty) {
        NotificationService().show(
          context,
          'Could not fetch stream. Please try again.',
          isError: true,
        );
        return;
      }

      // Pick best quality source: prefer MP4 (for compatibility on Windows where DASH libxml2 is missing), fallback to first available
      final preferred = streams.sources.firstWhere(
        (s) => s.type == 'video/mp4',
        orElse: () => streams.sources.first,
      );

      final episodeTitle = streams.title.isNotEmpty
          ? streams.title
          : (titles.isNotEmpty ? '${titles.first} — Episode $epNum' : 'Episode $epNum');

      PlayerState().startPlayback(
        streamUrl: preferred.url,
        title: episodeTitle,
        anilistId: widget.animeId,
        titles: titles,
        episodeCount: _mergedEpisodes.length,
        episodeNumber: epNum,
        isMovie: (_details?['format']?.toString().toUpperCase() == 'MOVIE'),
        media: _details,
        episodes: _mergedEpisodes,
        hstreamSources: streams.sources,
        hstreamSubtitleTracks: streams.tracks,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
          'Referer': 'https://hstream.moe/',
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loading
      NotificationService().show(
        context,
        'Stream error: ${e.toString()}',
        isError: true,
      );
    }
  }

  Future<void> _downloadHstreamEpisode(int epNum, List<String> titles) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _HstreamLoadingDialog(),
    );

    try {
      final service = HstreamService();
      final searchTerms = service.generateSearchTerms(titles);
      List<HstreamResult> results = [];
      for (final term in searchTerms) {
        results = await service.search(term);
        if (results.isNotEmpty) break;
      }

      if (!mounted) return;

      if (results.isEmpty) {
        Navigator.pop(context); // close loading
        NotificationService().show(
          context,
          'No streams found for this title.',
          isError: true,
        );
        return;
      }

      // Pick best result matching the episode number
      HstreamResult? best;
      for (final r in results) {
        final path = Uri.tryParse(r.url)?.pathSegments.lastOrNull ?? '';
        final lastPart = path.split('-').lastOrNull;
        if (lastPart != null && int.tryParse(lastPart) == epNum) {
          best = r;
          break;
        }
      }

      if (best == null) {
        for (final r in results) {
          final title = r.title.toLowerCase();
          final regex = RegExp(r'(?:^|\b|[-_])' + epNum.toString() + r'(?:\b|$)', caseSensitive: false);
          if (regex.hasMatch(title)) {
            best = r;
            break;
          }
        }
      }

      best ??= results.first;
      final streams = await service.getStreams(best.url);

      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (streams == null || streams.sources.isEmpty) {
        NotificationService().show(
          context,
          'Could not fetch streams. Please try again.',
          isError: true,
        );
        return;
      }

      // Filter only MP4 qualities for downloading (as DASH manifests can't be downloaded directly)
      final mp4Sources = streams.sources.where((s) => s.type == 'video/mp4' || s.url.contains('.mp4')).toList();
      if (mp4Sources.isEmpty) {
        NotificationService().show(
          context,
          'No downloadable MP4 qualities found.',
          isError: true,
        );
        return;
      }

      // Show quality selector dialog
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogCtx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0F0F11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
              side: const BorderSide(color: Colors.white10),
            ),
            title: const Text(
              'Select Download Quality',
              style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: mp4Sources.map((source) {
                return ListTile(
                  title: Text(
                    source.name,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
                  ),
                  onTap: () async {
                    Navigator.pop(dialogCtx);
                    final displayName = _details!['title']?['english'] ?? _details!['title']?['romaji'] ?? 'Hentai';
                    final taskTitle = '$displayName - Episode $epNum (${source.name})';
                    
                    await DownloadService().addDownloadTask(
                      hash: 'hstream_${best!.url.hashCode}_$epNum',
                      fileIndex: epNum,
                      title: taskTitle,
                      streamUrl: source.url,
                      anilistId: widget.animeId,
                      titles: titles,
                      episodeCount: _mergedEpisodes.length,
                      episodeNumber: epNum,
                      isMovie: (_details?['format']?.toString().toUpperCase() == 'MOVIE'),
                      mediaJson: jsonEncode(_details),
                      episodesJson: jsonEncode(_mergedEpisodes),
                    );
                    
                    if (mounted) {
                      NotificationService().show(context, 'Added "$taskTitle" to download queue.');
                    }
                  },
                );
              }).toList(),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loading
      NotificationService().show(
        context,
        'Error: ${e.toString()}',
        isError: true,
      );
    }
  }

  void _openTorrentSelectorPanel(int epNum, List<String> titles, {bool isDownload = false}) {
    final Size size = MediaQuery.of(context).size;
    final bool isLandscape = size.width > size.height;
    final bool isMobileWidth = size.width < 600;

    final double sheetWidth = isMobileWidth ? double.infinity : 800.0;
    final double sheetHeight = isLandscape
        ? size.height * 0.94
        : (isMobileWidth ? size.height * 0.85 : size.height * 0.85);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: sheetWidth,
            height: sheetHeight,
            margin: isLandscape
                ? const EdgeInsets.only(top: 8.0)
                : (isMobileWidth
                    ? EdgeInsets.zero
                    : const EdgeInsets.only(left: 24.0, right: 24.0, top: 16.0)),
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
              child: TorrentSelectorPanel(
                anilistId: widget.animeId,
                titles: titles,
                episodeCount: _mergedEpisodes.length,
                episodeNumber: epNum,
                isMovie: (_details!['format']?.toString().toUpperCase() == 'MOVIE'),
                media: _details,
                episodes: _mergedEpisodes,
                isDownload: isDownload,
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
        );
      },
    );
  }

  void _showLibraryEditDialog(BuildContext context) {
    const String modeStr = 'anime';
    final savedItem = LibraryState().getItem(widget.animeId, modeStr);
    final int? totalEpisodes = _details?['episodes'] ?? 
        (_mergedEpisodes.isNotEmpty ? _mergedEpisodes.length : null);
    final String titleStr = _details?['title']?['english'] ?? _details?['title']?['romaji'] ?? _details?['title']?['userPreferred'] ?? 'Anime Details';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return _LibraryEditPanel(
          animeId: widget.animeId,
          modeStr: modeStr,
          savedItem: savedItem,
          totalEpisodes: totalEpisodes,
          mediaTitle: titleStr,
          details: _details,
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
          // 1. Background Banner Backdrop Image
          if (bannerUrl.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 300.0,
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: bannerUrl,
                    width: double.infinity,
                    height: 300.0,
                    fit: BoxFit.cover,
                    memCacheWidth: 1200,
                    placeholder: (context, url) => const SizedBox(),
                    errorWidget: (context, url, error) => const SizedBox(),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black26,
                          Colors.black87,
                          Colors.black,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 2. Main Page Layout (Unified scroll view, scrolling columns side-by-side below)
          Positioned.fill(
            child: SmoothScrollArea(
              builder: (controller, physics) => SingleChildScrollView(
                controller: controller,
                physics: physics,
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
                          const SizedBox(width: 16.0),
                          ListenableBuilder(
                            listenable: LibraryState(),
                            builder: (context, _) {
                              const String modeStr = 'anime';
                              final bool isSaved = LibraryState().isSaved(widget.animeId, modeStr);
                              return IconButton(
                                icon: Icon(
                                  isSaved ? Icons.bookmark : Icons.bookmark_border,
                                  color: isSaved ? Colors.amber : Colors.white,
                                  size: 18.0,
                                ),
                                onPressed: () => _showLibraryEditDialog(context),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                                  padding: const EdgeInsets.all(10.0),
                                ),
                              );
                            },
                          ),
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
                                        GestureDetector(
                                          onTap: () => showPosterImageViewerDialog(context, imageUrl: coverUrl, title: title),
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: Container(
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
                                                child: CachedNetworkImage(
                                                  imageUrl: coverUrl, 
                                                  fit: BoxFit.cover,
                                                  memCacheWidth: 250,
                                                  placeholder: (context, url) => Container(color: Colors.grey[950]),
                                                  errorWidget: (context, url, error) => Container(color: Colors.grey[950]),
                                                ),
                                              ),
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
                                            child: CachedNetworkImage(
                                              imageUrl: coverUrl, 
                                              fit: BoxFit.cover,
                                              memCacheWidth: 310,
                                              placeholder: (context, url) => Container(color: Colors.grey[950]),
                                              errorWidget: (context, url, error) => Container(color: Colors.grey[950]),
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
                                              _buildContinueButton(false),
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

          return RepaintBoundary(
            child: Container(
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
                      child: CachedNetworkImage(
                        imageUrl: charPic, 
                        width: 38.0, 
                        height: double.infinity, 
                        fit: BoxFit.cover,
                        memCacheWidth: 80,
                        placeholder: (context, url) => Container(color: Colors.grey[950]),
                        errorWidget: (context, url, error) => Container(color: Colors.grey[950]),
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

          return RepaintBoundary(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.01),
                borderRadius: BorderRadius.circular(6.0),
              ),
              child: ListTile(
                leading: nodeCover.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4.0),
                        child: CachedNetworkImage(
                          imageUrl: nodeCover, 
                          width: 40.0, 
                          height: double.infinity, 
                          fit: BoxFit.cover,
                          memCacheWidth: 80,
                          placeholder: (context, url) => Container(color: Colors.grey[950]),
                          errorWidget: (context, url, error) => Container(color: Colors.grey[950]),
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
        ListenableBuilder(
          listenable: Listenable.merge([PlayerState(), DownloadService(), LibraryState()]),
          builder: (context, _) {
            final downloadedEps = DownloadService()
                .tasks
                .where((t) => t.anilistId == widget.animeId && t.status == DownloadStatus.completed)
                .map((t) => t.episodeNumber)
                .toSet();

            final savedItem = LibraryState().getItem(widget.animeId, 'anime');
            final int libraryWatchedEps = savedItem?.watchedEpisodes ?? 0;

            return GridView.builder(
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
                final String cleanTitle = ep['isPlaceholder'] == true ? epTitle : _cleanEpTitle(epTitle, epNum);
                final String site = ep['site'] ?? '';

                // Check TMDB overrides
                final tmdbEp = _tmdbEpisodesMap[epNum];
                final String tmdbTitle = tmdbEp?['name'] ?? '';
                final String finalTitle = (tmdbTitle.isNotEmpty && tmdbTitle.toLowerCase() != 'untitled')
                    ? tmdbTitle
                    : cleanTitle;
                final String tmdbThumb = tmdbEp?['still_path'] ?? '';
                final String finalThumbnail = tmdbThumb.isNotEmpty ? tmdbThumb : thumbnail;
                final String finalSite = site;

                final progress = PlayerState().getProgress(widget.animeId, epNum);
                final double ratio = progress != null && progress.duration > 0
                    ? (progress.position / progress.duration).clamp(0.0, 1.0)
                    : 0.0;
                final bool isWatched = ratio >= 0.90;
                final bool isDownloaded = downloadedEps.contains(epNum);

                final String showBanner = _details?['bannerImage'] ?? _details?['coverImage']?['extraLarge'] ?? '';

                return _EpisodeCard(
                  animeId: widget.animeId,
                  epNum: epNum,
                  title: finalTitle,
                  thumbnail: finalThumbnail,
                  showBanner: showBanner,
                  site: finalSite,
                  isDownloaded: isDownloaded,
                  isWatched: isWatched,
                  ratio: ratio,
                  onToggleWatched: () => _toggleEpisodeWatchedStatus(epNum, isWatched),
                  onMarkUpToWatched: () => _markEpisodesUpToWatched(epNum),
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
                      isWatched: isWatched,
                    );
                  },
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
  final int animeId;
  final int epNum;
  final String title;
  final String thumbnail;
  final String showBanner;
  final String site;
  final bool isDownloaded;
  final bool isWatched;
  final double ratio;
  final VoidCallback onTap;
  final VoidCallback? onToggleWatched;
  final VoidCallback? onMarkUpToWatched;

  const _EpisodeCard({
    required this.animeId,
    required this.epNum,
    required this.title,
    required this.thumbnail,
    required this.showBanner,
    required this.site,
    required this.isDownloaded,
    required this.isWatched,
    required this.ratio,
    required this.onTap,
    this.onToggleWatched,
    this.onMarkUpToWatched,
  });

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _isHovered = false;
  // Local disk-cached file path for the thumbnail.
  // Null = not yet resolved; empty string = resolved but no thumbnail available.
  String? _localPath;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _resolveThumbnail();
  }

  @override
  void didUpdateWidget(covariant _EpisodeCard old) {
    super.didUpdateWidget(old);
    // Re-resolve if the thumbnail URL changed (e.g. TMDB patch arrived)
    if (old.thumbnail != widget.thumbnail && widget.thumbnail.isNotEmpty) {
      _localPath = null;
      _resolveThumbnail();
    }
  }

  Future<void> _resolveThumbnail() async {
    if (_resolving || widget.thumbnail.isEmpty) return;
    _resolving = true;
    try {
      // 1. Check disk cache first (instant, no network)
      final cached = await TvdbService().getCachedPath(widget.thumbnail);
      if (cached != null) {
        if (mounted) setState(() => _localPath = cached);
        return;
      }
      // 2. Download and cache (handles TVDB auth automatically)
      final downloaded = await TvdbService().downloadAndCache(widget.thumbnail);
      if (mounted) setState(() => _localPath = downloaded ?? '');
    } catch (_) {
      if (mounted) setState(() => _localPath = '');
    } finally {
      _resolving = false;
    }
  }

  void _showEpisodeContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                width: 36.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'Episode ${widget.epNum} Options',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                    fontSize: 16.0,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  widget.isWatched ? Icons.remove_done : Icons.check_circle_outline,
                  color: widget.isWatched ? const Color(0xFFFF9F1C) : const Color(0xFF2EC4B6),
                ),
                title: Text(
                  widget.isWatched ? 'Mark as Unwatched' : 'Mark as Watched',
                  style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
                ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onToggleWatched?.call();
                },
              ),
              if (!widget.isWatched)
                ListTile(
                  leading: const Icon(Icons.done_all, color: Colors.blueAccent),
                  title: Text(
                    'Mark 1 to ${widget.epNum} as Watched',
                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onMarkUpToWatched?.call();
                  },
                ),
              const SizedBox(height: 8.0),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWatched = widget.isWatched;
    final isDownloaded = widget.isDownloaded;
    final ratio = widget.ratio;

    final String? fillerType = FillerService().getFillerType(widget.animeId, widget.epNum);
    Color? fillerColor;
    String? fillerLabel;
    if (fillerType != null) {
      final typeLower = fillerType.toLowerCase();
      if (typeLower == 'filler') {
        fillerColor = const Color(0xFFF1C40F); // Yellow
        fillerLabel = 'Filler';
      } else if (typeLower == 'mixed canon/filler' || typeLower.contains('mixed')) {
        fillerColor = const Color(0xFF81C784); // Light Green
        fillerLabel = 'Mixed';
      } else if (typeLower.contains('canon')) {
        fillerColor = const Color(0xFF2ECC71); // Green
        fillerLabel = 'Canon';
      }
    }


    Color borderColor = _isHovered ? Colors.white30 : Colors.white10;
    double borderWidth = 1.0;
    List<BoxShadow> cardShadows = _isHovered
        ? [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.05),
              blurRadius: 6.0,
              spreadRadius: 1.0,
            )
          ]
        : [];

    if (fillerLabel == 'Filler' || fillerLabel == 'Mixed') {
      final brightColor = fillerLabel == 'Filler' 
          ? const Color(0xFFFFD700) 
          : const Color(0xFF00FF7F); 
      
      borderColor = brightColor.withValues(alpha: _isHovered ? 1.0 : 0.8);
      borderWidth = 2.2;
      
      cardShadows = [
        BoxShadow(
          color: brightColor.withValues(alpha: _isHovered ? 0.35 : 0.15),
          blurRadius: _isHovered ? 8.0 : 4.0,
          spreadRadius: _isHovered ? 2.0 : 0.5,
        ),
      ];
    }

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: () => _showEpisodeContextMenu(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image area
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(
                    color: borderColor,
                    width: borderWidth,
                  ),
                  boxShadow: cardShadows,
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
                              : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                          child: Opacity(
                            opacity: isWatched ? 0.5 : 1.0,
                            child: AnimatedScale(
                              scale: _isHovered ? 1.05 : 1.0,
                              duration: const Duration(milliseconds: 150),
                              child: _buildThumbnailImage(isWatched),
                            ),
                          ),
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
                      if (isWatched)
                        Positioned(
                          top: 8.0,
                          right: isDownloaded ? 28.0 : 8.0,
                          child: Container(
                            padding: const EdgeInsets.all(3.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2EC4B6).withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 11.0,
                            ),
                          ),
                        ),
                      if (isDownloaded)
                        Positioned(
                          top: 8.0,
                          right: 8.0,
                          child: Container(
                            padding: const EdgeInsets.all(4.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2EC4B6).withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.download_done,
                              color: Colors.white,
                              size: 11.0,
                            ),
                          ),
                        ),

                      // Filler Badge (Bottom-Left)
                      if (fillerLabel != null && fillerColor != null)
                        Positioned(
                          bottom: 8.0,
                          left: 8.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: fillerColor.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(3.0),
                            ),
                            child: Text(
                              fillerLabel,
                              style: TextStyle(
                                color: fillerLabel == 'Filler' ? Colors.black87 : Colors.white,
                                fontSize: 8.5,
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

                      // Progress Bar overlay
                      if (ratio > 0)
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
                                color: Colors.white,
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
    ),
    );
  }

  /// Builds the thumbnail image widget.
  /// Priority: disk-cached file → network (while caching) → placeholder.
  Widget _buildThumbnailImage(bool isWatched) {
    final thumb = widget.thumbnail;

    // No URL at all — show placeholder immediately
    if (thumb.isEmpty) return _buildEpisodePlaceholder();

    // _localPath == null means still resolving; show a subtle shimmer
    if (_localPath == null) {
      return Container(color: Colors.grey[950]);
    }

    // _localPath == '' means resolution failed; fall back to network (may still work for non-TVDB)
    if (_localPath!.isEmpty) {
      return CachedNetworkImage(
        imageUrl: thumb,
        fit: BoxFit.cover,
        memCacheWidth: 800,
        placeholder: (_, __) => Container(color: Colors.grey[950]),
        errorWidget: (_, __, ___) => _buildEpisodePlaceholder(),
      );
    }

    // Disk-cached — instant load, no network call
    return Image.file(
      File(_localPath!),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildEpisodePlaceholder(),
    );
  }

  Widget _buildEpisodePlaceholder() {
    final banner = widget.showBanner;
    if (banner.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: banner,
        fit: BoxFit.cover,
        memCacheWidth: 1200,
        placeholder: (_, __) => _buildSolidPlaceholder(),
        errorWidget: (_, __, ___) => _buildSolidPlaceholder(),
      );
    }
    return _buildSolidPlaceholder();
  }

  Widget _buildSolidPlaceholder() {
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
    return RepaintBoundary(
      child: MouseRegion(
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
                      child: CachedNetworkImage(
                        imageUrl: widget.coverUrl, 
                        fit: BoxFit.cover,
                        memCacheWidth: 110,
                        placeholder: (context, url) => Container(color: Colors.grey[950]),
                        errorWidget: (context, url, error) => Container(color: Colors.grey[950]),
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

      _playingFile = file;
      _playingHash = torrentInfo.hash;

      if (!mounted) return;

      // Prebuffering phase inside the dialog
      setState(() {
        _status = "Starting playback...";
      });

      await _torrServerService.preloadTorrentFile(torrentInfo.hash, file.index);
      await Future.delayed(const Duration(milliseconds: 800));

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

class _LibraryEditPanel extends StatefulWidget {
  final int animeId;
  final String modeStr;
  final LibraryItem? savedItem;
  final int? totalEpisodes;
  final String mediaTitle;
  final Map<String, dynamic>? details;

  const _LibraryEditPanel({
    required this.animeId,
    required this.modeStr,
    required this.savedItem,
    required this.totalEpisodes,
    required this.mediaTitle,
    required this.details,
  });

  @override
  State<_LibraryEditPanel> createState() => _LibraryEditPanelState();
}

class _LibraryEditPanelState extends State<_LibraryEditPanel> {
  late String _activeStatus;
  late double _activeRating;
  late int _watchedEps;
  late List<String> _selectedCategoryIds;

  late final TextEditingController _episodesController;
  late final TextEditingController _scoreController;

  @override
  void initState() {
    super.initState();
    _activeStatus = widget.savedItem?.libraryStatus ?? 'watching';
    _activeRating = widget.savedItem?.rating ?? 0.0;
    _watchedEps = widget.savedItem?.watchedEpisodes ?? 0;
    _selectedCategoryIds = List<String>.from(widget.savedItem?.categoryIds ?? <String>[]);

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

  void _updateWatchedEpisodes(int val) {
    final int clamped = val.clamp(0, widget.totalEpisodes ?? 99999);
    setState(() {
      _watchedEps = clamped;
      _episodesController.text = '$clamped';
    });
  }

  void _updateRating(double val) {
    final double clamped = val.clamp(0.0, 10.0);
    setState(() {
      _activeRating = clamped;
      _scoreController.text = clamped == 0.0 ? '' : clamped.toStringAsFixed(1);
    });
  }



  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobileSheet = screenWidth < 650;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: isMobileSheet ? double.infinity : 550.0,
        margin: isMobileSheet
            ? EdgeInsets.zero
            : const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F11),
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
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
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
                                'Library Entry Settings',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.0,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Outfit',
                                ),
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
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54, size: 22),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  
                  // Body
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Status Selection
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
                              Text(
                                widget.modeStr == 'manga' ? 'Reading Status' : 'Watch Status',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13.0,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                              const SizedBox(height: 12.0),
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _activeStatus,
                                  dropdownColor: const Color(0xFF0F0F11),
                                  isExpanded: true,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Outfit',
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                                  items: [
                                    DropdownMenuItem(
                                      value: 'watching',
                                      child: Text(widget.modeStr == 'manga' ? 'Reading' : 'Watching'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'planning',
                                      child: const Text('Plan to Watch'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'completed',
                                      child: const Text('Completed'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'paused_dropped',
                                      child: const Text('Dropped / Paused'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _activeStatus = value;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20.0),

                        
                        // Episodes progress input with slider
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
                                  Row(
                                    children: [
                                      Text(
                                        widget.modeStr == 'manga' ? 'Chapters Read' : 'Episodes Watched',
                                        style: const TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                                      ),
                                      const SizedBox(width: 8.0),
                                      SizedBox(
                                        width: 50.0,
                                        height: 20.0,
                                        child: TextField(
                                          controller: _episodesController,
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            border: InputBorder.none,
                                          ),
                                          onChanged: (val) {
                                            final int? parsed = int.tryParse(val);
                                            if (parsed != null) {
                                              final int clamped = parsed.clamp(0, widget.totalEpisodes ?? 99999);
                                              setState(() {
                                                _watchedEps = clamped;
                                              });
                                            }
                                          },
                                          onSubmitted: (val) {
                                            final int? parsed = int.tryParse(val);
                                            _updateWatchedEpisodes(parsed ?? _watchedEps);
                                          },
                                        ),
                                      ),
                                      if (widget.totalEpisodes != null)
                                        Text(
                                          ' / ${widget.totalEpisodes}',
                                          style: const TextStyle(color: Colors.white38, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                        ),
                                    ],
                                  ),
                                  if (widget.totalEpisodes != null)
                                    Text(
                                      '${((widget.totalEpisodes! > 0 ? _watchedEps / widget.totalEpisodes! : 0.0) * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
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
                                  value: _watchedEps.toDouble(),
                                  min: 0.0,
                                  max: (widget.totalEpisodes ?? max(100, _watchedEps + 50)).toDouble(),
                                  divisions: widget.totalEpisodes ?? (100 + _watchedEps),
                                  label: '$_watchedEps',
                                  onChanged: (val) {
                                    _updateWatchedEpisodes(val.toInt());
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20.0),
                        
                        // Rating Score input
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
                                  const Text(
                                    'Your Score',
                                    style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 16.0),
                                      const SizedBox(width: 4.0),
                                      SizedBox(
                                        width: 50.0,
                                        height: 20.0,
                                        child: TextField(
                                          controller: _scoreController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(color: Colors.amber, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            border: InputBorder.none,
                                            hintText: '0.0',
                                            hintStyle: TextStyle(color: Colors.white38),
                                          ),
                                          onChanged: (val) {
                                            final double? parsed = double.tryParse(val);
                                            if (parsed != null) {
                                              final double clamped = parsed.clamp(0.0, 10.0);
                                              setState(() {
                                                _activeRating = clamped;
                                              });
                                            }
                                          },
                                          onSubmitted: (val) {
                                            final double? parsed = double.tryParse(val);
                                            _updateRating(parsed ?? _activeRating);
                                          },
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
                  
                  // Footer
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
                              await LibraryState().removeItem(widget.animeId, widget.modeStr);
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
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
                            final String formatVal = widget.details?['format'] ?? '';
                            final int finalWatchedEps = int.tryParse(_episodesController.text)?.clamp(0, widget.totalEpisodes ?? 99999) ?? _watchedEps;
                            final double finalRating = double.tryParse(_scoreController.text)?.clamp(0.0, 10.0) ?? _activeRating;
                            
                            await LibraryState().saveItem(
                              id: widget.animeId,
                              mode: widget.modeStr,
                              format: formatVal,
                              libraryStatus: _activeStatus,
                              rating: finalRating,
                              watchedEpisodes: finalWatchedEps,
                              totalEpisodes: widget.totalEpisodes,
                              categoryIds: _selectedCategoryIds,
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                          ),
                          child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading dialog shown while hstream.moe is being searched
// ─────────────────────────────────────────────────────────────────────────────

class _HstreamLoadingDialog extends StatelessWidget {
  const _HstreamLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F0F11),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 28.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
              ),
            ),
            const SizedBox(width: 18.0),
            const Flexible(
              child: Text(
                'Fetching streams…',
                style: TextStyle(
                  color: Colors.white70,
                  fontFamily: 'Outfit',
                  fontSize: 14.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
