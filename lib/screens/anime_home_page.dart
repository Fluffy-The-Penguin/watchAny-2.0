import 'dart:async';
import 'dart:ui';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/anilist_service.dart';
import '../state/navigation_state.dart';
import '../state/player_state.dart';
import '../widgets/smooth_scroll_area.dart';
import '../state/app_settings.dart';
import '../state/library_state.dart';
import '../services/download_service.dart';
import '../services/notification_service.dart';
import '../widgets/item_details_preview_popover.dart';
import '../widgets/dark_cloud_hero_background.dart';
import '../services/banner_resolver_service.dart';


class AnimeHomePage extends StatefulWidget {
  final NavigationState navigationState;

  const AnimeHomePage({
    super.key,
    required this.navigationState,
  });

  @override
  State<AnimeHomePage> createState() => _AnimeHomePageState();
}

class _AnimeHomePageState extends State<AnimeHomePage> {
  final AnilistService _anilistService = AnilistService();
  bool _isLoading = true;
  String? _errorMessage;

  // Dashboard datasets
  List<dynamic> _trending = [];
  List<dynamic> _popularThisSeason = [];
  List<dynamic> _newlyReleased = [];
  List<dynamic> _upcoming = [];
  List<dynamic> _action = [];
  List<dynamic> _adventure = [];
  List<dynamic> _romance = [];
  List<dynamic> _fantasy = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (AppSettings().offlineMode) {
      if (mounted) {
        setState(() {
          final library = LibraryState();
          
          List<dynamic> getLocalAnimeItems(String status) {
            return library.items
                .where((i) => i.mode == 'anime' && i.libraryStatus == status)
                .map((item) {
                  final cache = library.animeCache[item.id];
                  if (cache != null) return cache;
                  return {
                    'id': item.id,
                    'title': {'userPreferred': 'Anime #${item.id}'},
                    'coverImage': {'large': ''},
                    'format': item.format,
                    'episodes': item.totalEpisodes,
                  };
                })
                .toList();
          }

          _trending = getLocalAnimeItems('watching');
          _popularThisSeason = getLocalAnimeItems('completed');
          _newlyReleased = getLocalAnimeItems('planning');

          final completedDownloads = DownloadService().tasks
              .where((t) => t.isMovie != true && t.status == DownloadStatus.completed)
              .toList();
          
          final List<dynamic> downloadedMapped = [];
          for (final task in completedDownloads) {
            if (task.anilistId != null) {
              final cache = library.animeCache[task.anilistId!];
              if (cache != null) {
                if (!downloadedMapped.any((m) => m['id'] == task.anilistId)) {
                  downloadedMapped.add(cache);
                }
              } else {
                if (!downloadedMapped.any((m) => m['id'] == task.anilistId)) {
                  downloadedMapped.add({
                    'id': task.anilistId,
                    'title': {'userPreferred': task.title},
                    'coverImage': {'large': ''},
                    'format': 'TV',
                    'episodes': task.episodeCount,
                  });
                }
              }
            }
          }
          _upcoming = downloadedMapped;

          _action = [];
          _adventure = [];
          _romance = [];
          _fantasy = [];
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final data = await _anilistService.fetchDashboardData(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _trending = data['trending']?['media'] ?? [];
          _popularThisSeason = data['popularThisSeason']?['media'] ?? [];
          _newlyReleased = data['newlyReleased']?['media'] ?? [];
          _upcoming = data['upcoming']?['media'] ?? [];
          _action = data['action']?['media'] ?? [];
          _adventure = data['adventure']?['media'] ?? [];
          _romance = data['romance']?['media'] ?? [];
          _fantasy = data['fantasy']?['media'] ?? [];
          _isLoading = false;
        });
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

  // Load more paginated category results for railways
  Future<List<dynamic>> _loadMoreCategoryData({
    required String category,
    required int page,
  }) async {
    final now = DateTime.now();
    final season = AnilistService.getCurrentSeason(now);
    final year = now.year;

    Map<String, dynamic> response;

    if (category == 'trending') {
      response = await _anilistService.search(
        page: page,
        perPage: 12,
        type: 'ANIME',
        sort: 'TRENDING_DESC',
      );
    } else if (category == 'popular') {
      response = await _anilistService.search(
        page: page,
        perPage: 12,
        type: 'ANIME',
        season: season,
        year: year,
        sort: 'POPULARITY_DESC',
      );
    } else if (category == 'newlyReleased') {
      response = await _anilistService.search(
        page: page,
        perPage: 12,
        type: 'ANIME',
        status: 'RELEASING',
        sort: 'TRENDING_DESC',
      );
    } else if (category == 'upcoming') {
      response = await _anilistService.search(
        page: page,
        perPage: 12,
        type: 'ANIME',
        status: 'NOT_YET_RELEASED',
        sort: 'POPULARITY_DESC',
      );
    } else {
      // Genres (e.g. Action, Adventure, Romance, Fantasy)
      response = await _anilistService.search(
        page: page,
        perPage: 12,
        type: 'ANIME',
        genres: [category],
        sort: 'POPULARITY_DESC',
      );
    }

    return response['Page']?['media'] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2.0,
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40.0),
              const SizedBox(height: 16.0),
              Text(
                'Error loading dashboard:\n$_errorMessage',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14.0),
              ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _loadData(forceRefresh: true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white10,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final bool isOffline = AppSettings().offlineMode;

    return SmoothScrollArea(
      builder: (controller, physics) => AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final double scrollOffset = controller.hasClients ? controller.offset : 0.0;
          final double screenHeight = MediaQuery.of(context).size.height;
          final double revealProgress = (scrollOffset / (screenHeight * 0.35)).clamp(0.0, 1.0);
          final double curveVal = Curves.easeOutCubic.transform(revealProgress);

          return ListView(
            controller: controller,
            physics: physics,
            padding: EdgeInsets.zero,
            children: [
              // 1. Hero Section (Fading Banner Carousel) - Localized State
              if (_trending.isNotEmpty)
                _HeroSection(
                  trending: _trending,
                  navigationState: widget.navigationState,
                  scrollOffset: scrollOffset,
                ),

              // 2. Content Railways & Continue Watching Section
              Padding(
                padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 28.0, bottom: 40.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AnimeContinueWatchingSection(navigationState: widget.navigationState),
                    const SizedBox(height: 28.0),
                    if (_trending.isNotEmpty)
                          _RailwayTrack(
                            title: isOffline ? 'Watching (Local)' : 'Trending Now',
                            initialItems: _trending,
                            onLoadMore: isOffline ? (page) async => const [] : (page) => _loadMoreCategoryData(category: 'trending', page: page),
                            navigationState: widget.navigationState,
                          ),

                        if (_popularThisSeason.isNotEmpty)
                          _RailwayTrack(
                            title: isOffline ? 'Completed (Local)' : 'Popular This Season',
                            initialItems: _popularThisSeason,
                            onLoadMore: isOffline ? (page) async => const [] : (page) => _loadMoreCategoryData(category: 'popular', page: page),
                            navigationState: widget.navigationState,
                          ),
                        
                        if (_newlyReleased.isNotEmpty)
                          _RailwayTrack(
                            title: isOffline ? 'Planning (Local)' : 'Newly Released',
                            initialItems: _newlyReleased,
                            onLoadMore: isOffline ? (page) async => const [] : (page) => _loadMoreCategoryData(category: 'newlyReleased', page: page),
                            navigationState: widget.navigationState,
                          ),
                        
                        if (_upcoming.isNotEmpty)
                          _RailwayTrack(
                            title: isOffline ? 'Downloaded (Local)' : 'Upcoming Releases',
                            initialItems: _upcoming,
                            onLoadMore: isOffline ? (page) async => const [] : (page) => _loadMoreCategoryData(category: 'upcoming', page: page),
                            navigationState: widget.navigationState,
                          ),

                        const SizedBox(height: 16.0),
                        const Text(
                          'Genres',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22.0,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 12.0),

                        if (_action.isNotEmpty)
                          _RailwayTrack(
                            title: 'Action',
                            initialItems: _action,
                            onLoadMore: (page) => _loadMoreCategoryData(category: 'Action', page: page),
                            navigationState: widget.navigationState,
                          ),
                        
                        if (_adventure.isNotEmpty)
                          _RailwayTrack(
                            title: 'Adventure',
                            initialItems: _adventure,
                            onLoadMore: (page) => _loadMoreCategoryData(category: 'Adventure', page: page),
                            navigationState: widget.navigationState,
                          ),
                        
                        if (_romance.isNotEmpty)
                          _RailwayTrack(
                            title: 'Romance',
                            initialItems: _romance,
                            onLoadMore: (page) => _loadMoreCategoryData(category: 'Romance', page: page),
                            navigationState: widget.navigationState,
                          ),
                        
                        if (_fantasy.isNotEmpty)
                          _RailwayTrack(
                            title: 'Fantasy',
                            initialItems: _fantasy,
                            onLoadMore: (page) => _loadMoreCategoryData(category: 'Fantasy', page: page),
                            navigationState: widget.navigationState,
                          ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

// Localized state for the Hero Carousel to prevent rebuilding the entire dashboard every 7 seconds
class _HeroSection extends StatefulWidget {
  final List<dynamic> trending;
  final NavigationState navigationState;
  final double scrollOffset;

  const _HeroSection({
    required this.trending,
    required this.navigationState,
    this.scrollOffset = 0.0,
  });

  @override
  State<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<_HeroSection> {
  int _heroIndex = 0;
  Timer? _heroTimer;

  @override
  void initState() {
    super.initState();
    _startHeroTimer();
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    super.dispose();
  }

  void _startHeroTimer() {
    _heroTimer?.cancel();
    _heroTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (mounted && widget.trending.isNotEmpty) {
        setState(() {
          _heroIndex = (_heroIndex + 1) % widget.trending.length;
        });
        _enrichCurrentHeroBanner();
      }
    });
    _enrichCurrentHeroBanner();
  }

  void _enrichCurrentHeroBanner() async {
    if (widget.trending.isEmpty) return;
    final anime = widget.trending[_heroIndex % widget.trending.length];
    final String title = anime['title']?['english'] ?? anime['title']?['romaji'] ?? '';
    if (title.isNotEmpty) {
      final String? bestBanner = await BannerResolverService.getBestBanner(
        title: title,
        anilistBanner: anime['bannerImage']?.toString(),
        format: anime['format'],
      );
      if (bestBanner != null && mounted) {
        setState(() {
          anime['bannerImage'] = bestBanner;
        });
      }
    }
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

  @override
  Widget build(BuildContext context) {
    if (widget.trending.isEmpty) return const SizedBox.shrink();

    // Filter list to only use items with actual widescreen banners for the Hero Slider
    final List<dynamic> heroItems = widget.trending
        .where((item) => (item['bannerImage']?.toString() ?? '').isNotEmpty)
        .toList();
    final List<dynamic> featuredList = heroItems.isNotEmpty ? heroItems : widget.trending;
    final int safeIndex = _heroIndex >= featuredList.length ? 0 : _heroIndex;
    final anime = featuredList[safeIndex];

    String bannerUrl = (anime['bannerImage'] ?? anime['coverImage']?['extraLarge'] ?? '').toString();
    if (bannerUrl.contains('image.tmdb.org/t/p/')) {
      bannerUrl = bannerUrl.replaceAll(RegExp(r'/w\d+/'), '/original/');
    }
    final String title = anime['title']?['english'] ?? anime['title']?['romaji'] ?? 'Untitled';
    final String description = _cleanDescription(anime['description']);
    final double? rating = anime['averageScore'] != null ? (anime['averageScore'] as num).toDouble() : null;
    final String format = anime['format'] ?? '';
    final int? episodes = anime['episodes'];

    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final bool isMobile = screenWidth < 800;

    // Responsive Widescreen Height (Prevents 2.7x vertical zoom stretch on Desktop)
    final double heroHeight = isMobile
        ? (screenHeight * 0.70).clamp(420.0, 560.0)
        : (screenHeight * 0.65).clamp(520.0, 700.0);

    final int displayCount = featuredList.length > 6 ? 6 : featuredList.length;

    return SizedBox(
      height: heroHeight,
      width: double.infinity,
      child: DarkCloudHeroBackground(
        imageUrl: bannerUrl,
        imageAlignment: Alignment.topRight,
        child: Stack(
          children: [

          // 3. Floating Left Glassmorphic Content Card (With Scroll Parallax & Opacity Fade)
          Builder(
            builder: (context) {
              final double cardFade = (1.0 - (widget.scrollOffset / (screenHeight * 0.35))).clamp(0.0, 1.0);
              final double cardOffsetY = -widget.scrollOffset * 0.30;
              final double cardWidth = isMobile
                  ? (screenWidth - 32.0)
                  : (screenWidth > 1400 ? 520.0 : (screenWidth > 1100 ? 450.0 : 390.0));

              return Positioned(
                left: isMobile ? 16.0 : 44.0,
                bottom: isMobile ? 24.0 : 48.0,
                width: cardWidth,
                child: Transform.translate(
                  offset: Offset(0, cardOffsetY),
                  child: Opacity(
                    opacity: cardFade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tag & Metadata Badges Bar
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8.0,
                          runSpacing: 6.0,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6.0),
                                border: Border.all(color: Colors.white24, width: 0.8),
                              ),
                              child: Text(
                                '★ #${_heroIndex + 1} TRENDING',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.0,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ),
                            if (format.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9.0, vertical: 4.0),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6.0),
                                  border: Border.all(color: Colors.white12, width: 0.8),
                                ),
                                child: Text(
                                  format,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ),
                            if (episodes != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9.0, vertical: 4.0),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6.0),
                                  border: Border.all(color: Colors.white12, width: 0.8),
                                ),
                                child: Text(
                                  '$episodes Episodes',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ),
                            if (rating != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9.0, vertical: 4.0),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6.0),
                                  border: Border.all(color: Colors.amber.withValues(alpha: 0.6), width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded, color: Colors.amber, size: 14.0),
                                    const SizedBox(width: 3.0),
                                    Text(
                                      (rating / 10).toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontSize: 11.0,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Outfit',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14.0),

                        // Main Title
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 24.0 : 40.0,
                            fontWeight: FontWeight.w900,
                            height: 1.12,
                            fontFamily: 'Outfit',
                            letterSpacing: -0.5,
                            shadows: const [
                              Shadow(color: Colors.black87, blurRadius: 16),
                            ],
                          ),
                        ),

                        // Synopsis Description
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 12.0),
                          Text(
                            description,
                            maxLines: isMobile ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: isMobile ? 12.5 : 14.0,
                              height: 1.45,
                              fontStyle: FontStyle.italic,
                              fontFamily: 'Outfit',
                              shadows: const [
                                Shadow(color: Colors.black87, blurRadius: 12),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 22.0),

                        // Action Buttons Row
                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: Icon(Icons.play_arrow_rounded, color: Colors.black, size: isMobile ? 18 : 22),
                              label: Text(isMobile ? 'Watch' : 'Watch Now'),
                              onPressed: () {
                                widget.navigationState.selectAnime(anime['id']);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 18.0 : 26.0,
                                  vertical: isMobile ? 11.0 : 15.0,
                                ),
                                elevation: 6,
                                shadowColor: Colors.black54,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                                textStyle: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isMobile ? 13.0 : 14.5,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10.0),
                            ListenableBuilder(
                              listenable: LibraryState(),
                              builder: (context, _) {
                                final int idInt = anime['id'] is int ? anime['id'] : (int.tryParse(anime['id'].toString()) ?? 0);
                                final bool isSaved = idInt != 0 && LibraryState().isSaved(idInt, 'anime');

                                return OutlinedButton.icon(
                                  icon: Icon(
                                    isSaved ? Icons.check_rounded : Icons.add_rounded,
                                    color: Colors.white,
                                    size: isMobile ? 16 : 19,
                                  ),
                                  label: Text(isSaved ? 'In Library' : 'Add Library'),
                                  onPressed: () async {
                                    if (idInt == 0) return;
                                    final library = LibraryState();
                                    if (isSaved) {
                                      await library.removeItem(idInt, 'anime');
                                      if (context.mounted) NotificationService().show(context, 'Removed from Library');
                                    } else {
                                      await library.saveItem(
                                        id: idInt,
                                        mode: 'anime',
                                        format: format.isNotEmpty ? format : 'TV',
                                        libraryStatus: 'planning',
                                        rating: (rating ?? 0) / 10,
                                        watchedEpisodes: 0,
                                      );
                                      if (context.mounted) NotificationService().show(context, 'Added to Library');
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: Colors.black.withValues(alpha: 0.40),
                                    side: const BorderSide(
                                      color: Colors.white38,
                                      width: 1.0,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isMobile ? 14.0 : 18.0,
                                      vertical: isMobile ? 11.0 : 15.0,
                                    ),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                                    textStyle: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: isMobile ? 12.5 : 14.0,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 10.0),
                            OutlinedButton.icon(
                              icon: Icon(Icons.info_outline_rounded, color: Colors.white, size: isMobile ? 16 : 19),
                              label: const Text('Details'),
                              onPressed: () {
                                widget.navigationState.selectAnime(anime['id']);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.black.withValues(alpha: 0.40),
                                side: const BorderSide(color: Colors.white38, width: 1.0),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 14.0 : 18.0,
                                  vertical: isMobile ? 11.0 : 15.0,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                                textStyle: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: isMobile ? 12.5 : 14.0,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // 4. Horizontal Floating Cards Dock Switcher (Bottom Right on Desktop)
          if (!isMobile)
            Positioned(
              right: 44.0,
              bottom: 48.0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C0C10).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    displayCount,
                    (index) {
                      final item = widget.trending[index];
                      final bool isSelected = index == _heroIndex;
                      final String thumbUrl = item['coverImage']?['large'] ??
                          item['coverImage']?['extraLarge'] ??
                          item['bannerImage'] ??
                          '';

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _heroIndex = index;
                          });
                          _startHeroTimer();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                          width: isSelected ? 96.0 : 64.0,
                          height: 54.0,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10.0),
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.15),
                              width: isSelected ? 2.0 : 1.0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Colors.white.withValues(alpha: 0.3),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9.0),
                            child: Stack(
                              children: [
                                CachedNetworkImage(
                                  imageUrl: thumbUrl,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.topCenter,
                                  width: double.infinity,
                                  height: double.infinity,
                                  memCacheWidth: 250,
                                  placeholder: (context, url) => Container(color: Colors.black26),
                                  errorWidget: (context, url, err) => Container(color: Colors.black26),
                                ),
                                if (!isSelected)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                  ),
                                if (isSelected)
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      height: 3.0,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

          // 5. Floating "Scroll to Explore" Prompt at Bottom Center
          Positioned(
            bottom: 16.0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20.0),
                  border: Border.all(color: Colors.white12, width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'EXPLORE MORE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    SizedBox(width: 6.0),
                    Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 16.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }
}

// Localized state for each Railway Track to listen to scrolls, page results, and load-more at the end of the track
class _RailwayTrack extends StatefulWidget {
  final String title;
  final List<dynamic> initialItems;
  final Future<List<dynamic>> Function(int page) onLoadMore;
  final NavigationState navigationState;

  const _RailwayTrack({
    required this.title,
    required this.initialItems,
    required this.onLoadMore,
    required this.navigationState,
  });

  @override
  State<_RailwayTrack> createState() => _RailwayTrackState();
}

class _RailwayTrackState extends State<_RailwayTrack> {
  final ScrollController _scrollController = ScrollController();
  late List<dynamic> _items = List.from(widget.initialItems);
  int _currentPage = 1;
  bool _isLoadingMore = false;
  late bool _hasMore = widget.title != 'Continue Watching';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _RailwayTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialItems != oldWidget.initialItems) {
      setState(() {
        _items = List.from(widget.initialItems);
        _currentPage = 1;
        _isLoadingMore = false;
        _hasMore = widget.title != 'Continue Watching';
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 250) {
      _loadNextPage();
    }
    setState(() {});
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    
    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final newItems = await widget.onLoadMore(nextPage);
      
      if (mounted) {
        setState(() {
          if (newItems.isEmpty) {
            _hasMore = false;
          } else {
            _currentPage = nextPage;
            _items.addAll(newItems);
          }
          _isLoadingMore = false;
        });
      }
    } catch (e, stack) {
      developer.log('Error loading more items for track ${widget.title}', name: 'AnimeHomePage', error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    final bool showLeft = _scrollController.hasClients && _scrollController.offset > 10.0;
    final bool showRight = !_scrollController.hasClients 
        ? _items.length > 4 
        : (_scrollController.offset < _scrollController.position.maxScrollExtent - 10.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
          child: Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'Outfit',
            ),
          ),
        ),
        Stack(
          children: [
            SizedBox(
              height: 235.0,
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                itemCount: _items.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    // Return loading placeholder card only while actively fetching
                    return Container(
                      width: 140.0,
                      margin: const EdgeInsets.only(right: 14.0),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.01),
                        borderRadius: BorderRadius.circular(6.0),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const CircularProgressIndicator(
                        color: Colors.white30,
                        strokeWidth: 2.0,
                      ),
                    );
                  }

                  final animeItem = _items[index];
                  final rawId = animeItem['id'];
                  final int? parsedId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

                  return HoverPreviewWrapper(
                    item: animeItem,
                    isMovie: false,
                    onTap: () {
                      widget.navigationState.selectAnime(parsedId);
                    },
                    child: _AnimeCard(
                      anime: animeItem,
                      onTap: () {
                        widget.navigationState.selectAnime(parsedId);
                      },
                      onDelete: widget.title == 'Continue Watching'
                          ? () {
                              final String idStr = rawId?.toString() ?? '';
                              if (idStr.isNotEmpty) {
                                PlayerState.removeFromContinueWatching(idStr, isAnime: true);
                              }
                            }
                          : null,
                    ),
                  );
                },
              ),
            ),
            
            // Scroll buttons (Desktop only)
            if (!isMobile) ...[
              // Left button
              if (showLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.only(left: 4.0),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white10),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.chevron_left, color: Colors.white),
                        onPressed: () {
                          final double target = (_scrollController.offset - 400.0).clamp(0.0, _scrollController.position.maxScrollExtent);
                          _scrollController.animateTo(
                            target,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              // Right button
              if (showRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.only(right: 4.0),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white10),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.chevron_right, color: Colors.white),
                        onPressed: () {
                          final double target = (_scrollController.offset + 400.0).clamp(0.0, _scrollController.position.maxScrollExtent);
                          _scrollController.animateTo(
                            target,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

class _AnimeCard extends StatefulWidget {
  final dynamic anime;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _AnimeCard({
    required this.anime,
    required this.onTap,
    this.onDelete,
  });

  @override
  State<_AnimeCard> createState() => _AnimeCardState();
}

class _AnimeCardState extends State<_AnimeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final rawCover = widget.anime['coverImage'];
    final coverUrl = (rawCover is Map) 
        ? (rawCover['extraLarge'] ?? rawCover['large'] ?? '') 
        : (rawCover?.toString() ?? '');

    final rawTitle = widget.anime['title'];
    final title = (rawTitle is Map) 
        ? (rawTitle['english'] ?? rawTitle['romaji'] ?? rawTitle['native'] ?? 'Untitled') 
        : (rawTitle?.toString() ?? 'Untitled');

    final double? rating = widget.anime['averageScore'] != null
        ? double.tryParse(widget.anime['averageScore'].toString())
        : null;
    final String? format = widget.anime['format'];
    final int? episodes = widget.anime['episodes'];

    String infoString = '';
    if (format != null) infoString += format;
    if (episodes != null) infoString += ' · $episodes eps';

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 140.0,
            margin: const EdgeInsets.only(right: 14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Cover Image
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 190.0,
                width: 140.0,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(
                    color: _isHovered ? Colors.white24 : Colors.white10,
                    width: 1.0,
                  ),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.05),
                            blurRadius: 8.0,
                            spreadRadius: 2.0,
                          )
                        ]
                      : [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5.0),
                  child: Stack(
                    children: [
                      // Image
                      Positioned.fill(
                        child: AnimatedScale(
                          scale: _isHovered ? 1.05 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: coverUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: coverUrl,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 280,
                                  placeholder: (context, url) => Container(color: Colors.grey[950]),
                                  errorWidget: (context, url, error) => Container(color: Colors.grey[950]),
                                )
                              : Container(color: Colors.grey[950]),
                        ),
                      ),
                      // Delete button overlay
                      if (widget.onDelete != null && _isHovered)
                        Positioned(
                          top: 8.0,
                          left: 8.0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onDelete,
                            child: Container(
                              padding: const EdgeInsets.all(4.0),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 1.0),
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 12.0),
                            ),
                          ),
                        ),

                      // Score Badge / Hover Add-to-Library Button
                      Positioned(
                        top: 6.0,
                        right: 6.0,
                        child: ListenableBuilder(
                          listenable: LibraryState(),
                          builder: (context, _) {
                            final rawId = widget.anime['id'];
                            final int? parsedId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
                            final bool isSavedInLib = parsedId != null && LibraryState().isSaved(parsedId, 'anime');

                            if (_isHovered) {
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (parsedId == null) return;
                                  final library = LibraryState();
                                  if (isSavedInLib) {
                                    library.removeItem(parsedId, 'anime');
                                    NotificationService().show(context, 'Removed from Library');
                                  } else {
                                    library.saveItem(
                                      id: parsedId,
                                      mode: 'anime',
                                      format: format ?? 'TV',
                                      libraryStatus: 'planning',
                                      rating: 0.0,
                                      watchedEpisodes: 0,
                                      totalEpisodes: episodes,
                                    );
                                    NotificationService().show(context, 'Added to Library');
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4.0),
                                  decoration: BoxDecoration(
                                    color: isSavedInLib ? Colors.white : Colors.black.withValues(alpha: 0.88),
                                    borderRadius: BorderRadius.circular(6.0),
                                    border: Border.all(
                                      color: isSavedInLib ? Colors.white : Colors.white30,
                                      width: 1.0,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black54, blurRadius: 6),
                                    ],
                                  ),
                                  child: Icon(
                                    isSavedInLib ? Icons.check_rounded : Icons.add_rounded,
                                    color: isSavedInLib ? Colors.black : Colors.white,
                                    size: 13.0,
                                  ),
                                ),
                              );
                            }

                            if (rating != null) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(3.0),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 10.0),
                                    const SizedBox(width: 2.0),
                                    Text(
                                      (rating / 10).toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontSize: 9.0,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return const SizedBox.shrink();
                          },
                        ),
                      ),

                      // Format/Episodes overlay at bottom
                      if (infoString.isNotEmpty)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 6.0),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.85),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: Text(
                              infoString,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6.0),

              // Title text
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _isHovered ? Colors.white : Colors.white70,
                  fontSize: 12.0,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Outfit',
                  height: 1.2,
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

class _AnimeContinueWatchingSection extends StatefulWidget {
  final NavigationState navigationState;
  const _AnimeContinueWatchingSection({required this.navigationState});

  @override
  State<_AnimeContinueWatchingSection> createState() => _AnimeContinueWatchingSectionState();
}

class _AnimeContinueWatchingSectionState extends State<_AnimeContinueWatchingSection> {
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    PlayerState().addListener(_onPlayerChange);
    _loadItems();
  }

  @override
  void dispose() {
    PlayerState().removeListener(_onPlayerChange);
    super.dispose();
  }

  void _onPlayerChange() {
    if (mounted) _loadItems();
  }

  Future<void> _loadItems() async {
    final list = await PlayerState.getContinueWatchingList(isAnime: true);
    if (mounted) {
      setState(() {
        _items = list;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return _RailwayTrack(
      title: 'Continue Watching',
      initialItems: _items,
      onLoadMore: (page) async => const [],
      navigationState: widget.navigationState,
    );
  }
}
