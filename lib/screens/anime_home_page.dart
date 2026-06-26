import 'dart:async';
import 'package:flutter/material.dart';
import '../services/anilist_service.dart';
import '../state/navigation_state.dart';

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

  // Hero Carousel State
  int _heroIndex = 0;
  Timer? _heroTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    super.dispose();
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

        // Initialize Hero Timer if we have trending items
        if (_trending.isNotEmpty) {
          _startHeroTimer();
        }
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

  void _startHeroTimer() {
    _heroTimer?.cancel();
    _heroTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (mounted && _trending.isNotEmpty) {
        setState(() {
          _heroIndex = (_heroIndex + 1) % _trending.length;
        });
      }
    });
  }

  String _cleanDescription(String? htmlDesc) {
    if (htmlDesc == null) return '';
    // Strip HTML tags
    final regExp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    String clean = htmlDesc.replaceAll(regExp, '');
    // Clean up entities
    clean = clean
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&rsquo;', "'")
        .replaceAll('&amp;', '&');
    return clean;
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

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Hero Section (Fading Banner Carousel)
          if (_trending.isNotEmpty) _buildHeroSection(),

          // Content rows
          Padding(
            padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 40.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24.0),
                if (_popularThisSeason.isNotEmpty)
                  _buildRailway('Popular This Season', _popularThisSeason),
                
                if (_newlyReleased.isNotEmpty)
                  _buildRailway('Newly Released', _newlyReleased),
                
                if (_upcoming.isNotEmpty)
                  _buildRailway('Upcoming Releases', _upcoming),

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

                if (_action.isNotEmpty) _buildRailway('Action', _action),
                if (_adventure.isNotEmpty) _buildRailway('Adventure', _adventure),
                if (_romance.isNotEmpty) _buildRailway('Romance', _romance),
                if (_fantasy.isNotEmpty) _buildRailway('Fantasy', _fantasy),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    final anime = _trending[_heroIndex];
    final String bannerUrl = anime['bannerImage'] ?? anime['coverImage']?['extraLarge'] ?? '';
    final String title = anime['title']?['english'] ?? anime['title']?['romaji'] ?? 'Untitled';
    final String description = _cleanDescription(anime['description']);
    final double? rating = anime['averageScore'] != null ? (anime['averageScore'] as num).toDouble() : null;
    final String format = anime['format'] ?? '';
    final int? episodes = anime['episodes'];

    return SizedBox(
      height: 480.0,
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

          // Gradient overlays to blend into pure black
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
            bottom: 40.0,
            left: 24.0,
            right: 24.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges Row
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
                        Text(
                          '$episodes Episodes',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12.0,
                          ),
                        ),
                      ],
                      if (rating != null) ...[
                        const SizedBox(width: 12.0),
                        const Icon(Icons.star, color: Colors.amber, size: 14.0),
                        const SizedBox(width: 4.0),
                        Text(
                          (rating / 10).toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.0,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12.0),

                  // Title
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      fontFamily: 'Outfit',
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10.0),

                  // Description
                  if (description.isNotEmpty)
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13.0,
                        height: 1.4,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  const SizedBox(height: 20.0),

                  // Action Buttons
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Play'),
                        onPressed: () {
                          // Handle play action
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.0),
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
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                        ),
                        child: const Text('Details'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Carousel Navigation Indicators
          Positioned(
            bottom: 24.0,
            right: 24.0,
            child: Row(
              children: List.generate(
                _trending.length > 6 ? 6 : _trending.length,
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

  Widget _buildRailway(String title, List<dynamic> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'Outfit',
            ),
          ),
        ),
        SizedBox(
          height: 235.0,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            itemBuilder: (context, index) {
              final animeItem = list[index];
              return _AnimeCard(
                anime: animeItem,
                onTap: () => widget.navigationState.selectAnime(animeItem['id']),
              );
            },
          ),
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
    final coverUrl = widget.anime['coverImage']?['large'] ?? '';
    final title = widget.anime['title']?['english'] ?? widget.anime['title']?['romaji'] ?? 'Untitled';
    final double? rating = widget.anime['averageScore'] != null
        ? (widget.anime['averageScore'] as num).toDouble()
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
                                    return Container(color: Colors.grey[900]);
                                  },
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(color: Colors.grey[900]),
                                )
                              : Container(color: Colors.grey[900]),
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
