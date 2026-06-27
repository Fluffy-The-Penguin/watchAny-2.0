import 'dart:convert';
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
    });

    final addonService = StremioAddonService();
    await addonService.init();

    final enabledCatalogAddons = addonService.addons
        .where((a) => a.isEnabled && a.resources.contains('catalog'))
        .toList();

    if (enabledCatalogAddons.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetching = false;
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final List<String> selectedAddons = prefs.getStringList('stremio_homepage_selected_addons') ?? [];

    List<StremioAddon> targetAddons = [];
    if (selectedAddons.isNotEmpty) {
      for (final addonId in selectedAddons) {
        final addonObj = enabledCatalogAddons.firstWhere(
          (a) => a.id == addonId,
          orElse: () => StremioAddon(id: '', name: '', version: '', description: '', url: '', icon: '', types: [], resources: [], catalogs: []),
        );
        if (addonObj.id.isNotEmpty) {
          targetAddons.add(addonObj);
        }
      }
    } else {
      targetAddons = enabledCatalogAddons.take(5).toList();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    final List<Future<void>> fetchTasks = [];

    for (final addon in targetAddons) {
      final List<String> selectedCatalogs = prefs.getStringList('stremio_homepage_selected_catalogs_${addon.id}') ?? [];

      List<dynamic> targetCatalogs = [];
      if (selectedCatalogs.isNotEmpty) {
        for (final catId in selectedCatalogs) {
          final catObj = addon.catalogs.firstWhere(
            (c) => c['id'] == catId,
            orElse: () => <String, dynamic>{},
          );
          if (catObj.isNotEmpty) {
            targetCatalogs.add(catObj);
          }
        }
      } else {
        targetCatalogs = addon.catalogs.take(5).toList();
      }

      for (final cat in targetCatalogs) {
        final type = cat['type'] ?? 'movie';
        final id = cat['id'] ?? '';
        final name = cat['name'] ?? addon.name;

        final task = () async {
          try {
            final catalogUrl = '${addon.url.replaceAll('/manifest.json', '')}/catalog/$type/$id.json';
            final response = await http.get(Uri.parse(catalogUrl)).timeout(const Duration(seconds: 8));

            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              final List metas = data['metas'] ?? [];
              if (metas.isNotEmpty && mounted) {
                setState(() {
                  _catalogRows = List.from(_catalogRows)
                    ..add({
                      'addonName': addon.name,
                      'catalogName': name,
                      'type': type,
                      'items': metas,
                    });

                  if (_featuredItem == null) {
                    for (final item in metas) {
                      if (item['background'] != null && item['background'].toString().isNotEmpty) {
                        _featuredItem = item;
                        break;
                      }
                    }
                  }
                });
              }
            }
          } catch (e) {
            debugPrint('Error loading catalog $name from ${addon.name}: $e');
          }
        }();
        fetchTasks.add(task);
      }
    }

    if (fetchTasks.isNotEmpty) {
      await Future.wait(fetchTasks);
    }

    if (mounted) {
      setState(() {
        _isFetching = false;
      });
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

    final StremioAddonService addonService = StremioAddonService();
    final enabledCatalogAddons = addonService.addons.where((a) => a.isEnabled && a.resources.contains('catalog')).toList();

    if (enabledCatalogAddons.isEmpty) {
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
                  'No Catalog Addons Enabled',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 8.0),
                const Text(
                  'Install Stremio addons (like Cinemeta) from the Settings -> Movies/TV Addons page to load catalogs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 14.0),
                ),
                const SizedBox(height: 24.0),
                ElevatedButton.icon(
                  onPressed: () => widget.navigationState.setPage(TabPage.settings),
                  icon: const Icon(Icons.settings, color: Colors.black, size: 18.0),
                  label: const Text('Go to Settings', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
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

              // 2. Continue Watching Railway (Filtered for Movie Mode)
              ListenableBuilder(
                listenable: PlayerState(),
                builder: (context, _) {
                  return FutureBuilder<List<dynamic>>(
                    future: PlayerState.getContinueWatchingList(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      // Keep only items that are NOT AniList integers (Stremio IDs start with tt/etc)
                      final movieOnly = snapshot.data!
                          .where((item) => int.tryParse(item['id']?.toString() ?? '') == null)
                          .toList();
                      if (movieOnly.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 12.0),
                        child: _MovieRailwayTrack(
                          title: 'Continue Watching',
                          items: movieOnly,
                          navigationState: widget.navigationState,
                        ),
                      );
                    },
                  );
                },
              ),

              // 3. Dynamic Catalog Railways
              if (_catalogRows.isEmpty)
                if (_isFetching)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 64.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                          SizedBox(height: 16.0),
                          Text(
                            'Loading catalogs...',
                            style: TextStyle(color: Colors.white38, fontSize: 13.0, fontFamily: 'Outfit'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 64.0),
                      child: Text(
                        'No content rows returned by enabled addons.',
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
                            title: '${row['catalogName']} (${row['addonName']})',
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
    final background = item['background'] ?? item['poster'] ?? '';
    final title = item['name'] ?? 'Featured Content';
    final description = item['description'] ?? 'No description available.';
    final double? rating = item['imdbRating'] != null ? double.tryParse(item['imdbRating'].toString()) : null;
    final String type = item['type'] ?? 'movie';
    final String id = item['id'] ?? '';

    return Stack(
      children: [
        // Backdrop Image
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
        // Dark Radial/Linear Gradient Overlay
        Container(
          height: 480.0,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black38,
                Colors.black87,
                Colors.black,
              ],
              stops: [0.0, 0.7, 1.0],
            ),
          ),
        ),
        // Content Details Info
        Positioned(
          left: 24.0,
          right: 24.0,
          bottom: 24.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rating Tag
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
              // Title Text
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
              const SizedBox(height: 6.0),
              // Description Paragraph
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600.0),
                child: Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 14.0),
                ),
              ),
              const SizedBox(height: 16.0),
              // Play/Watch Details Buttons
              ElevatedButton.icon(
                onPressed: () {
                  if (_featuredItem != null) {
                    MovieMetadataCache.placeholders[id] = Map<String, dynamic>.from(_featuredItem!);
                    MovieMetadataCache.placeholders['$type:$id'] = Map<String, dynamic>.from(_featuredItem!);
                  }
                  widget.navigationState.selectMovie('$type:$id');
                },
                icon: const Icon(Icons.info_outline, color: Colors.black, size: 18.0),
                label: const Text('View Details', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
                itemCount: widget.items.length,
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return _MovieCard(
                    item: item,
                    onTap: () {
                      final type = item['type'] ?? 'movie';
                      final id = item['id'] ?? '';
                      MovieMetadataCache.placeholders[id] = Map<String, dynamic>.from(item);
                      MovieMetadataCache.placeholders['$type:$id'] = Map<String, dynamic>.from(item);
                      widget.navigationState.selectMovie('$type:$id');
                    },
                  );
                },
              ),
            ),
            if (!isMobile && widget.items.length > 4) ...[
              // Left Scroll Button
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
                        final target = (_scrollController.offset - 400.0).clamp(0.0, _scrollController.position.maxScrollExtent);
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
              // Right Scroll Button
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
                        final target = (_scrollController.offset + 400.0).clamp(0.0, _scrollController.position.maxScrollExtent);
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

class _MovieCard extends StatefulWidget {
  final dynamic item;
  final VoidCallback onTap;

  const _MovieCard({
    required this.item,
    required this.onTap,
  });

  @override
  State<_MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<_MovieCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final posterUrl = widget.item['poster'] ?? widget.item['coverImage'] ?? '';
    final title = widget.item['name'] ?? widget.item['title'] ?? 'Untitled';
    final double? rating = widget.item['imdbRating'] != null ? double.tryParse(widget.item['imdbRating'].toString()) : null;
    final String? releaseInfo = widget.item['releaseInfo']?.toString();

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
                                      Container(color: Colors.grey[950], child: const Icon(Icons.movie, color: Colors.white24)),
                                )
                              : Container(color: Colors.grey[950], child: const Icon(Icons.movie, color: Colors.white24)),
                        ),
                      ),
                      if (rating != null)
                        Positioned(
                          right: 6.0,
                          top: 6.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
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
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11.0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

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

class _FadeInWidgetState extends State<FadeInWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: widget.child,
    );
  }
}
