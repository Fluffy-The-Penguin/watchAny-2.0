import 'dart:async';
import 'package:flutter/material.dart';
import '../services/anilist_service.dart';
import '../state/navigation_state.dart';
import '../state/player_state.dart';
import '../widgets/smooth_scroll_area.dart';

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

  Future<void> _loadData() async {
    try {
      final data = await _anilistService.fetchDashboardData();
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
                  _loadData();
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

    return SmoothScrollArea(
      builder: (controller, physics) => ListView(
        controller: controller,
        physics: physics,
        padding: EdgeInsets.zero,
        children: [
          // 1. Hero Section (Fading Banner Carousel) - Localized State
          if (_trending.isNotEmpty)
            _HeroSection(
              trending: _trending,
              navigationState: widget.navigationState,
            ),

          // 2. Content Railways (Horizontal tracks with load-more at the end)
          Padding(
            padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 40.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListenableBuilder(
                  listenable: PlayerState(),
                  builder: (context, _) {
                    return FutureBuilder<List<dynamic>>(
                      future: PlayerState.getContinueWatchingList(isAnime: true),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return _RailwayTrack(
                          title: 'Continue Watching',
                          initialItems: snapshot.data!,
                          onLoadMore: (page) async => const [],
                          navigationState: widget.navigationState,
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 24.0),
                if (_trending.isNotEmpty)
                  _RailwayTrack(
                    title: 'Trending Now',
                    initialItems: _trending,
                    onLoadMore: (page) => _loadMoreCategoryData(category: 'trending', page: page),
                    navigationState: widget.navigationState,
                  ),

                if (_popularThisSeason.isNotEmpty)
                  _RailwayTrack(
                    title: 'Popular This Season',
                    initialItems: _popularThisSeason,
                    onLoadMore: (page) => _loadMoreCategoryData(category: 'popular', page: page),
                    navigationState: widget.navigationState,
                  ),
                
                if (_newlyReleased.isNotEmpty)
                  _RailwayTrack(
                    title: 'Newly Released',
                    initialItems: _newlyReleased,
                    onLoadMore: (page) => _loadMoreCategoryData(category: 'newlyReleased', page: page),
                    navigationState: widget.navigationState,
                  ),
                
                if (_upcoming.isNotEmpty)
                  _RailwayTrack(
                    title: 'Upcoming Releases',
                    initialItems: _upcoming,
                    onLoadMore: (page) => _loadMoreCategoryData(category: 'upcoming', page: page),
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
      ),
    );
  }
}

// Localized state for the Hero Carousel to prevent rebuilding the entire dashboard every 7 seconds
class _HeroSection extends StatefulWidget {
  final List<dynamic> trending;
  final NavigationState navigationState;

  const _HeroSection({
    required this.trending,
    required this.navigationState,
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
      }
    });
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
    final anime = widget.trending[_heroIndex];
    final String bannerUrl = anime['bannerImage'] ?? anime['coverImage']?['extraLarge'] ?? '';
    final String title = anime['title']?['english'] ?? anime['title']?['romaji'] ?? 'Untitled';
    final String description = _cleanDescription(anime['description']);
    final double? rating = anime['averageScore'] != null ? (anime['averageScore'] as num).toDouble() : null;
    final String format = anime['format'] ?? '';
    final int? episodes = anime['episodes'];

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    return SizedBox(
      height: isMobile ? 360.0 : 480.0,
      width: double.infinity,
      child: Stack(
        children: [
          // Banner Image (Fading Transition)
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 800),
              child: bannerUrl.isNotEmpty
                  ? Image.network(
                      bannerUrl,
                      key: ValueKey(bannerUrl),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      cacheWidth: 1280,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(color: Colors.black);
                      },
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: Colors.black),
                    )
                  : Container(color: Colors.black, key: const ValueKey('empty')),
            ),
          ),

          // Gradients
          Positioned.fill(
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
                  stops: [0.0, 0.25, 0.6, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.95),
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.4, 0.8],
                ),
              ),
            ),
          ),

          // Content Text Overlay
          Positioned(
            bottom: isMobile ? 24.0 : 40.0,
            left: isMobile ? 16.0 : 24.0,
            right: isMobile ? 16.0 : 24.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (format.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: Text(
                            format,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (episodes != null) ...[
                        const SizedBox(width: 8.0),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: Text(
                            '$episodes Episodes',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      if (rating != null) ...[
                        const SizedBox(width: 8.0),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 16.0),
                            const SizedBox(width: 4.0),
                            Text(
                              (rating / 10).toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 13.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12.0),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 22.0 : 32.0,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 12.0),
                    Text(
                      description,
                      maxLines: isMobile ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13.0,
                        height: 1.4,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                  const SizedBox(height: 20.0),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(Icons.play_arrow, size: isMobile ? 16 : 18),
                        label: const Text('Play'),
                        onPressed: () {
                          widget.navigationState.selectAnime(anime['id']);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 18.0 : 24.0, 
                            vertical: isMobile ? 10.0 : 12.0,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                          textStyle: TextStyle(
                            fontWeight: FontWeight.bold, 
                            fontSize: isMobile ? 13.0 : 14.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      OutlinedButton(
                        onPressed: () {
                          widget.navigationState.selectAnime(anime['id']);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24, width: 1.0),
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 14.0 : 16.0, 
                            vertical: isMobile ? 10.0 : 12.0,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                          textStyle: TextStyle(
                            fontSize: isMobile ? 13.0 : 14.0,
                          ),
                        ),
                        child: const Text('Details'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Indicators
          Positioned(
            bottom: 24.0,
            right: 24.0,
            child: Row(
              children: List.generate(
                widget.trending.length > 6 ? 6 : widget.trending.length,
                (index) => GestureDetector(
                  onTap: () {
                    setState(() {
                      _heroIndex = index;
                    });
                    _startHeroTimer();
                  },
                  child: Container(
                    width: 6.0,
                    height: 6.0,
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _heroIndex == index ? Colors.white : Colors.white24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
    } catch (e) {
      debugPrint('Error loading more items for track ${widget.title}: $e');
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
                itemCount: _items.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    // Return loading placeholder card at the end of the track
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
                  return _AnimeCard(
                    anime: animeItem,
                    onTap: () {
                      final rawId = animeItem['id'];
                      final int? parsedId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
                      widget.navigationState.selectAnime(parsedId);
                    },
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

  const _AnimeCard({
    required this.anime,
    required this.onTap,
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
        ? (rawCover['large'] ?? rawCover['extraLarge'] ?? '') 
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

    return MouseRegion(
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
                              ? Image.network(
                                  coverUrl,
                                  fit: BoxFit.cover,
                                  cacheWidth: 280,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return Container(color: Colors.grey[950]);
                                  },
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(color: Colors.grey[950]),
                                )
                              : Container(color: Colors.grey[950]),
                        ),
                      ),
                      
                      // Score Badge
                      if (rating != null)
                        Positioned(
                          top: 8.0,
                          right: 8.0,
                          child: Container(
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
    );
  }
}
