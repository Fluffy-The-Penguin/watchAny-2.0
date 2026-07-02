import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../state/navigation_state.dart';
import '../services/stremio_addon_service.dart';
import '../state/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'movies_details_page.dart';

class MoviesHomePage extends StatefulWidget {
  final NavigationState navigationState;

  const MoviesHomePage({
    super.key,
    required this.navigationState,
  });

  @override
  State<MoviesHomePage> createState() => _MoviesHomePageState();
}

class _MoviesHomePageState extends State<MoviesHomePage> {
  bool _isLoading = true;
  bool _isFetching = true;
  List<Map<String, dynamic>> _catalogRows = [];
  Map<String, dynamic>? _featuredItem;
  bool _hasEnabledAddons = false;

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
  }

  Future<void> _loadCatalogs() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isFetching = true;
      _catalogRows = [];
      _featuredItem = null;
      _hasEnabledAddons = false;
    });

    final addonService = StremioAddonService();
    await addonService.init();

    final enabledCatalogAddons = addonService.catalogAddons;

    if (!mounted) return;
    setState(() {
      _hasEnabledAddons = enabledCatalogAddons.isNotEmpty;
      _isLoading = false;
    });

    if (enabledCatalogAddons.isEmpty) {
      setState(() => _isFetching = false);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final List<String> selectedAddonIds =
        prefs.getStringList('stremio_homepage_selected_addons') ?? [];

    List<StremioAddon> targetAddons;
    if (selectedAddonIds.isNotEmpty) {
      targetAddons = selectedAddonIds
          .map((id) => enabledCatalogAddons.where((a) => a.id == id).toList())
          .expand((x) => x)
          .toList();
    } else {
      targetAddons = enabledCatalogAddons.take(5).toList();
    }

    final List<Future<void>> fetchTasks = [];

    for (final addon in targetAddons) {
      final List<String> selectedCatalogIds =
          prefs.getStringList('stremio_homepage_selected_catalogs_${addon.id}') ?? [];

      List<Map<String, dynamic>> targetCatalogs;
      if (selectedCatalogIds.isNotEmpty) {
        targetCatalogs = selectedCatalogIds
            .map((catId) => addon.catalogs.where((c) => c['id'] == catId).toList())
            .expand((x) => x)
            .toList();
      } else {
        targetCatalogs = addon.catalogs.take(5).cast<Map<String, dynamic>>().toList();
      }

      for (final cat in targetCatalogs) {
        final type = (cat['type'] as String?) ?? 'movie';
        final id = (cat['id'] as String?) ?? '';
        final catName = (cat['name'] as String?) ?? addon.name;

        if (id.isEmpty) continue;

        final task = () async {
          try {
            final catalogUrl = '${addon.baseUrl}/catalog/$type/$id.json';
            final response = await http
                .get(Uri.parse(catalogUrl))
                .timeout(const Duration(seconds: 10));

            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              final List metas = data['metas'] ?? [];
              if (metas.isNotEmpty && mounted) {
                setState(() {
                  _catalogRows = List.from(_catalogRows)
                    ..add({
                      'addonName': addon.name,
                      'catalogName': catName,
                      'type': type,
                      'items': metas,
                    });

                  // Feature the first item that has a background image
                  if (_featuredItem == null) {
                    for (final item in metas) {
                      final bg = item['background']?.toString() ?? '';
                      final poster = item['poster']?.toString() ?? '';
                      if (bg.isNotEmpty || poster.isNotEmpty) {
                        _featuredItem = Map<String, dynamic>.from(item);
                        break;
                      }
                    }
                  }
                });
              }
            }
          } catch (e, stack) {
            developer.log('Error loading catalog "$catName" from "${addon.name}"', name: 'MoviesHomePage', error: e, stackTrace: stack);
          }
        }();
        fetchTasks.add(task);
      }
    }

    if (fetchTasks.isNotEmpty) {
      await Future.wait(fetchTasks);
    }

    if (mounted) {
      setState(() => _isFetching = false);
    }
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

    if (!_hasEnabledAddons) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 64.0),
                const SizedBox(height: 18.0),
                const Text(
                  'No Catalog Addons Installed',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 8.0),
                const Text(
                  'Install Stremio addons (like Cinemeta) from Settings → Movies/TV Addons to load catalogs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 14.0),
                ),
                const SizedBox(height: 24.0),
                ElevatedButton.icon(
                  onPressed: () => widget.navigationState.setPage(TabPage.settings),
                  icon: const Icon(Icons.settings, color: Colors.black, size: 18.0),
                  label: const Text('Go to Settings',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: RefreshIndicator(
        onRefresh: _loadCatalogs,
        color: Colors.white,
        backgroundColor: const Color(0xFF0F0F11),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Featured Hero Banner
              if (_featuredItem != null) _buildHeroBanner(_featuredItem!),

              // 2. Continue Watching (Stremio items only)
              _ContinueWatchingRail(navigationState: widget.navigationState),

              // 3. Dynamic Catalog Railways
              if (_catalogRows.isEmpty)
                _isFetching
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 64.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                              SizedBox(height: 16.0),
                              Text(
                                'Loading catalogs...',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 13.0, fontFamily: 'Outfit'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 64.0),
                          child: Text(
                            'No content returned by enabled addons.\nCheck your addon settings.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          ),
                        ),
                      )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 48.0),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    itemCount: _catalogRows.length,
                    itemBuilder: (context, index) {
                      final row = _catalogRows[index];
                      return FadeInWidget(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: _MovieRailwayTrack(
                            title: '${row['catalogName']} · ${row['addonName']}',
                            items: row['items'],
                            navigationState: widget.navigationState,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner(Map<String, dynamic> item) {
    final background =
        item['background']?.toString() ?? item['poster']?.toString() ?? '';
    final title = item['name']?.toString() ?? item['title']?.toString() ?? 'Featured Content';
    final description = item['description']?.toString() ?? '';
    final double? rating = item['imdbRating'] != null
        ? double.tryParse(item['imdbRating'].toString())
        : null;
    final String type = item['type']?.toString() ?? 'movie';
    final String id = item['id']?.toString() ?? '';

    return Stack(
      children: [
        // Backdrop
        Container(
          height: 480.0,
          width: double.infinity,
          decoration: BoxDecoration(
            image: background.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(background),
                    fit: BoxFit.cover,
                  )
                : null,
            color: Colors.white10,
          ),
        ),
        // Gradient overlay
        Container(
          height: 480.0,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black26, Colors.black87, Colors.black],
              stops: [0.0, 0.65, 1.0],
            ),
          ),
        ),
        // Content
        Positioned(
          left: 24.0,
          right: 24.0,
          bottom: 24.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rating != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8.0),
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, color: Colors.black, size: 12.0),
                      const SizedBox(width: 4.0),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6.0),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600.0),
                  child: Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 14.0),
                  ),
                ),
              ],
              const SizedBox(height: 16.0),
              ElevatedButton.icon(
                onPressed: id.isNotEmpty
                    ? () {
                        MovieMetadataCache.placeholders[id] =
                            Map<String, dynamic>.from(item);
                        MovieMetadataCache.placeholders['$type:$id'] =
                            Map<String, dynamic>.from(item);
                        widget.navigationState.selectMovie('$type:$id');
                      }
                    : null,
                icon: const Icon(Icons.info_outline, color: Colors.black, size: 18.0),
                label: const Text('View Details',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Continue Watching Rail ───────────────────────────────────────────────────

class _ContinueWatchingRail extends StatefulWidget {
  final NavigationState navigationState;
  const _ContinueWatchingRail({required this.navigationState});

  @override
  State<_ContinueWatchingRail> createState() => _ContinueWatchingRailState();
}

class _ContinueWatchingRailState extends State<_ContinueWatchingRail> {
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
    PlayerState().addListener(_onPlayerChange);
  }

  @override
  void dispose() {
    PlayerState().removeListener(_onPlayerChange);
    super.dispose();
  }

  void _onPlayerChange() => _loadItems();

  Future<void> _loadItems() async {
    final filtered = await PlayerState.getContinueWatchingList(isAnime: false);
    if (mounted) setState(() => _items = filtered);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 12.0),
      child: _MovieRailwayTrack(
        title: 'Continue Watching',
        items: _items,
        navigationState: widget.navigationState,
      ),
    );
  }
}

// ─── Railway Track ────────────────────────────────────────────────────────────

class _MovieRailwayTrack extends StatefulWidget {
  final String title;
  final List<dynamic> items;
  final NavigationState navigationState;

  const _MovieRailwayTrack({
    required this.title,
    required this.items,
    required this.navigationState,
  });

  @override
  State<_MovieRailwayTrack> createState() => _MovieRailwayTrackState();
}

class _MovieRailwayTrackState extends State<_MovieRailwayTrack> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
          child: Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17.0,
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
                itemCount: widget.items.length,
                itemBuilder: (context, index) {
                  final item = widget.items[index] as Map;
                  return _MovieCard(
                    item: item,
                    onTap: () {
                      final type = item['type']?.toString() ?? 'movie';
                      final id = item['id']?.toString() ?? '';
                      if (id.isEmpty) return;
                      final String selectId = id.contains(':') ? id : '$type:$id';
                      MovieMetadataCache.placeholders[id] =
                          Map<String, dynamic>.from(item.cast());
                      MovieMetadataCache.placeholders[selectId] =
                          Map<String, dynamic>.from(item.cast());
                      widget.navigationState.selectMovie(selectId);
                    },
                  );
                },
              ),
            ),
            if (!isMobile && widget.items.length > 4) ...[
              _ScrollButton(
                direction: ScrollDirection.left,
                controller: _scrollController,
              ),
              _ScrollButton(
                direction: ScrollDirection.right,
                controller: _scrollController,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

enum ScrollDirection { left, right }

class _ScrollButton extends StatelessWidget {
  final ScrollDirection direction;
  final ScrollController controller;

  const _ScrollButton({required this.direction, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isLeft = direction == ScrollDirection.left;
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          margin: EdgeInsets.only(left: isLeft ? 4 : 0, right: isLeft ? 0 : 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white10),
          ),
          child: IconButton(
            icon: Icon(
              isLeft ? Icons.chevron_left : Icons.chevron_right,
              color: Colors.white,
            ),
            onPressed: () {
              if (!controller.hasClients) return;
              final delta = isLeft ? -420.0 : 420.0;
              final target =
                  (controller.offset + delta).clamp(0.0, controller.position.maxScrollExtent);
              controller.animateTo(
                target,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Movie Card ───────────────────────────────────────────────────────────────

class _MovieCard extends StatefulWidget {
  final dynamic item;
  final VoidCallback onTap;

  const _MovieCard({required this.item, required this.onTap});

  @override
  State<_MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<_MovieCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Map item = widget.item;
    final posterUrl =
        item['poster']?.toString() ?? item['coverImage']?.toString() ?? '';
    final title =
        item['name']?.toString() ?? item['title']?.toString() ?? 'Untitled';
    final double? rating = item['imdbRating'] != null
        ? double.tryParse(item['imdbRating'].toString())
        : null;
    final String? releaseInfo = item['releaseInfo']?.toString();
    final String? type = item['type']?.toString();

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
                      Positioned.fill(
                        child: AnimatedScale(
                          scale: _isHovered ? 1.05 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: posterUrl.isNotEmpty
                              ? Image.network(
                                  posterUrl,
                                  fit: BoxFit.cover,
                                  cacheWidth: 280,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _placeholder(),
                                )
                              : _placeholder(),
                        ),
                      ),
                      // Type badge (series vs movie)
                      if (type == 'series')
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(3.0),
                            ),
                            child: const Text(
                              'TV',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.0,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      if (rating != null)
                        Positioned(
                          right: 6.0,
                          top: 6.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(4.0),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 10.0),
                                const SizedBox(width: 2.0),
                                Text(
                                  rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Play overlay on hover
                      Positioned.fill(
                        child: AnimatedOpacity(
                          opacity: _isHovered ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.35),
                            child: const Center(
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.white,
                                child: Icon(Icons.play_arrow, color: Colors.black, size: 22),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6.0),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Outfit',
                ),
              ),
              if (releaseInfo != null && releaseInfo.isNotEmpty)
                Text(
                  releaseInfo,
                  style: const TextStyle(color: Colors.white38, fontSize: 11.0),
                ),
            ],
          ),
        ),
      ),
    ),);
  }

  Widget _placeholder() => Container(
        color: Colors.grey[950],
        child: const Icon(Icons.movie, color: Colors.white24),
      );
}

// ─── Fade-in Animation Widget ─────────────────────────────────────────────────

class FadeInWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const FadeInWidget({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
  });

  @override
  State<FadeInWidget> createState() => _FadeInWidgetState();
}

class _FadeInWidgetState extends State<FadeInWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _animation, child: widget.child);
  }
}
