import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../state/navigation_state.dart';
import '../services/stremio_addon_service.dart';
import '../state/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'movies_details_page.dart';
import '../widgets/smooth_scroll_area.dart';
import '../state/app_settings.dart';
import '../state/library_state.dart';
import '../services/download_service.dart';
import '../services/notification_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/item_details_preview_popover.dart';
import '../widgets/dark_cloud_hero_background.dart';


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

  // Carousel variables
  List<Map<String, dynamic>> _featuredItems = [];
  PageController? _pageController;
  Timer? _carouselTimer;
  int _currentCarouselIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadCatalogs();
    StremioAddonService().addListener(_onAddonsChanged);
  }

  @override
  void dispose() {
    StremioAddonService().removeListener(_onAddonsChanged);
    _pageController?.dispose();
    _carouselTimer?.cancel();
    super.dispose();
  }

  void _onAddonsChanged() {
    if (mounted) {
      _loadCatalogs();
    }
  }

  void _startCarouselTimer() {
    _carouselTimer?.cancel();
    if (_featuredItems.isEmpty) return;
    _carouselTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (!mounted) return;
      if (_featuredItems.length <= 1) return;
      final nextIndex = (_currentCarouselIndex + 1) % _featuredItems.length;
      _currentCarouselIndex = nextIndex;
      _pageController?.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _loadCatalogs() async {
    if (!mounted) return;
    _carouselTimer?.cancel();

    if (AppSettings().offlineMode) {
      setState(() {
        _isLoading = true;
        _isFetching = true;
        _catalogRows = [];
        _featuredItem = null;
        _featuredItems = [];
        _currentCarouselIndex = 0;
        _hasEnabledAddons = true;
      });

      final library = LibraryState();
      
      List<dynamic> getLocalMovieItems(String status) {
        return library.items
            .where((i) => i.mode == 'movies' && i.libraryStatus == status)
            .map((item) {
              final cache = library.movieCache[item.id];
              if (cache != null) return cache;
              return {
                'id': 'movie:tt${item.id}',
                'name': 'Media #${item.id}',
                'poster': '',
                'type': item.format == 'MOVIE' ? 'movie' : 'series',
              };
            })
            .toList();
      }

      final completedDownloads = DownloadService().tasks
          .where((t) => t.isMovie == true && t.status == DownloadStatus.completed)
          .toList();
      
      final List<dynamic> downloadedMapped = [];
      for (final task in completedDownloads) {
        final cleanId = task.id.split(':').last;
        final digits = RegExp(r'\d+').allMatches(cleanId).map((m) => m.group(0)!).join();
        final parsedId = int.tryParse(digits) ?? task.id.hashCode.abs();
        
        final cache = library.movieCache[parsedId];
        if (cache != null) {
          if (!downloadedMapped.any((m) => m['id'] == cache['id'])) {
            downloadedMapped.add(cache);
          }
        } else {
          if (!downloadedMapped.any((m) => m['id'] == task.id)) {
            downloadedMapped.add({
              'id': task.id,
              'name': task.title,
              'poster': '',
              'type': task.isMovie == true ? 'movie' : 'series',
            });
          }
        }
      }

      final watching = getLocalMovieItems('watching');
      final completed = getLocalMovieItems('completed');
      final planning = getLocalMovieItems('planning');

      setState(() {
        if (watching.isNotEmpty) {
          _catalogRows.add({
            'addonName': 'Library',
            'catalogName': 'Watching (Local)',
            'type': 'movie',
            'items': watching,
          });
          _featuredItems.addAll(watching.cast<Map<String, dynamic>>());
        }
        if (completed.isNotEmpty) {
          _catalogRows.add({
            'addonName': 'Library',
            'catalogName': 'Completed (Local)',
            'type': 'movie',
            'items': completed,
          });
          _featuredItems.addAll(completed.cast<Map<String, dynamic>>());
        }
        if (planning.isNotEmpty) {
          _catalogRows.add({
            'addonName': 'Library',
            'catalogName': 'Planning (Local)',
            'type': 'movie',
            'items': planning,
          });
        }
        if (downloadedMapped.isNotEmpty) {
          _catalogRows.add({
            'addonName': 'Library',
            'catalogName': 'Downloaded (Local)',
            'type': 'movie',
            'items': downloadedMapped,
          });
          _featuredItems.addAll(downloadedMapped.cast<Map<String, dynamic>>());
        }

        if (_featuredItems.isNotEmpty) {
          _featuredItem = _featuredItems.first;
        }
        _isLoading = false;
        _isFetching = false;
      });

      _startCarouselTimer();
      return;
    }

    setState(() {
      _isLoading = true;
      _isFetching = true;
      _catalogRows = [];
      _featuredItem = null;
      _featuredItems = [];
      _currentCarouselIndex = 0;
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

                  // Add items to featured carousel (up to 6 items total)
                  for (final item in metas) {
                    final bg = item['background']?.toString() ?? '';
                    final poster = item['poster']?.toString() ?? '';
                    final itemId = item['id']?.toString() ?? '';
                    if ((bg.isNotEmpty || poster.isNotEmpty) && itemId.isNotEmpty) {
                      if (!_featuredItems.any((x) => x['id'] == itemId)) {
                        _featuredItems.add(Map<String, dynamic>.from(item));
                      }
                    }
                    if (_featuredItems.length >= 6) break;
                  }

                  // Setup initial featuredItem just in case anything else queries it
                  if (_featuredItem == null && _featuredItems.isNotEmpty) {
                    _featuredItem = _featuredItems.first;
                  }
                });
                _startCarouselTimer();
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
      _startCarouselTimer();
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
        child: SmoothScrollArea(
          builder: (controller, physics) => AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final double scrollOffset = controller.hasClients ? controller.offset : 0.0;
              final double screenHeight = MediaQuery.of(context).size.height;
              final double revealProgress = (scrollOffset / (screenHeight * 0.35)).clamp(0.0, 1.0);
              final double curveVal = Curves.easeOutCubic.transform(revealProgress);

              return SingleChildScrollView(
                controller: controller,
                physics: physics,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Featured Hero Banner
                    if (_featuredItems.isNotEmpty) _buildHeroBanner(scrollOffset),

                    // 2. Animated Railways Container (Unlocks with scale, fade & slide on scroll)
                    Transform.translate(
                      offset: Offset(0, 40.0 * (1.0 - curveVal)),
                      child: Opacity(
                        opacity: (0.15 + (0.85 * curveVal)).clamp(0.0, 1.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Crimson Ambient Top Accent Line when unlocking content
                            Container(
                              height: 2.0,
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.white.withValues(alpha: 0.35 * curveVal),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            // Continue Watching (Stremio items only)
                            _ContinueWatchingRail(navigationState: widget.navigationState),

                            // Dynamic Catalog Railways
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
                                  : Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 64.0),
                                        child: Text(
                                          AppSettings().offlineMode
                                              ? 'No local downloads or library items found.\nToggle Offline Mode off in Settings to stream online content.'
                                              : 'No content returned by enabled addons.\nCheck your addon settings.',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white38),
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
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner([double scrollOffset = 0.0]) {
    if (_featuredItems.isEmpty) return const SizedBox.shrink();

    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final bool isMobile = screenWidth < 800;

    // Responsive Widescreen Height (Prevents 2.7x vertical zoom stretch on Desktop)
    final double heroHeight = isMobile
        ? (screenHeight * 0.70).clamp(420.0, 560.0)
        : (screenHeight * 0.65).clamp(520.0, 700.0);

    final int displayCount = _featuredItems.length > 6 ? 6 : _featuredItems.length;

    return SizedBox(
      height: heroHeight,
      width: double.infinity,
      child: Stack(
        children: [
          // 1. Page View Banner Backgrounds
          PageView.builder(
            controller: _pageController,
            itemCount: displayCount,
            onPageChanged: (index) {
              setState(() {
                _currentCarouselIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final item = _featuredItems[index];
              String rawBg = (item['background'] ?? item['backdrop'] ?? item['poster'] ?? '').toString();
              if (rawBg.contains('image.tmdb.org/t/p/')) {
                rawBg = rawBg.replaceAll(RegExp(r'/w\d+/'), '/original/');
              }
              final background = rawBg;
              final title = item['name'] ?? item['title'] ?? 'Featured Content';
              final overview = item['description'] ?? item['overview'] ?? '';
              final type = item['type'] ?? 'movie';
              final id = item['id'] ?? item['imdb_id'] ?? '';
              final double? rating = item['imdbRating'] != null
                  ? double.tryParse(item['imdbRating'].toString())
                  : null;

              return DarkCloudHeroBackground(
                imageUrl: background,
                imageAlignment: Alignment.topRight,
                child: Stack(
                  children: [

                  // Left Floating Glassmorphic Card (With Scroll Parallax & Opacity Fade)
                  Builder(
                    builder: (context) {
                      final double cardFade = (1.0 - (scrollOffset / (screenHeight * 0.35))).clamp(0.0, 1.0);
                      final double cardOffsetY = -scrollOffset * 0.30;
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
                                // Badges Row
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
                                        '★ #${index + 1} FEATURED',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11.0,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9.0, vertical: 4.0),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6.0),
                                        border: Border.all(color: Colors.white12, width: 0.8),
                                      ),
                                      child: Text(
                                        type.toUpperCase(),
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
                                              rating.toStringAsFixed(1),
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

                                // Title
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

                                // Description
                                if (overview.isNotEmpty) ...[
                                  const SizedBox(height: 12.0),
                                  Text(
                                    overview,
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

                                // Action Buttons
                                Row(
                                  children: [
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
                                      icon: Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.black,
                                        size: isMobile ? 18 : 22,
                                      ),
                                      label: Text(type == 'series' ? 'Watch Series' : 'Watch Movie'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black,
                                        elevation: 6,
                                        shadowColor: Colors.black54,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isMobile ? 18.0 : 26.0,
                                          vertical: isMobile ? 11.0 : 15.0,
                                        ),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                                        textStyle: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: isMobile ? 13.0 : 14.5,
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12.0),
                                    OutlinedButton.icon(
                                      onPressed: id.isNotEmpty
                                          ? () {
                                              MovieMetadataCache.placeholders[id] =
                                                  Map<String, dynamic>.from(item);
                                              MovieMetadataCache.placeholders['$type:$id'] =
                                                  Map<String, dynamic>.from(item);
                                              widget.navigationState.selectMovie('$type:$id');
                                            }
                                          : null,
                                      icon: Icon(Icons.info_outline_rounded, color: Colors.white, size: isMobile ? 16 : 19),
                                      label: const Text('Details'),
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
        ],
      ),
    );
  },
),

          // 2. Desktop Horizontal Floating Deck Switcher
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
                      final item = _featuredItems[index];
                      final bool isSelected = index == _currentCarouselIndex;
                      final String thumbUrl = item['poster']?.toString() ??
                          item['background']?.toString() ??
                          '';

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentCarouselIndex = index;
                          });
                          _pageController?.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                          );
                          _startCarouselTimer();
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

          // 3. Floating "Scroll to Explore" Prompt at Bottom Center
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
    widget.navigationState.addListener(_onNavigationChanged);
  }

  @override
  void dispose() {
    PlayerState().removeListener(_onPlayerChange);
    widget.navigationState.removeListener(_onNavigationChanged);
    super.dispose();
  }

  void _onNavigationChanged() {
    final nav = widget.navigationState;
    if (nav.currentMode == AppMode.movies && nav.currentPage == TabPage.home) {
      _loadItems();
    }
  }

  void _onPlayerChange() {
    final nav = widget.navigationState;
    if (nav.currentMode == AppMode.movies && nav.currentPage == TabPage.home) {
      _loadItems();
    }
  }

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
                  final type = item['type']?.toString() ?? 'movie';
                  final id = item['id']?.toString() ?? '';
                  final String selectId = id.contains(':') ? id : '$type:$id';

                  return HoverPreviewWrapper(
                    item: item,
                    isMovie: true,
                    onTap: () {
                      if (id.isEmpty) return;
                      MovieMetadataCache.placeholders[id] = Map<String, dynamic>.from(item.cast());
                      MovieMetadataCache.placeholders[selectId] = Map<String, dynamic>.from(item.cast());
                      widget.navigationState.selectMovie(selectId);
                    },
                    child: _MovieCard(
                      item: item,
                      onTap: () {
                        if (id.isEmpty) return;
                        MovieMetadataCache.placeholders[id] = Map<String, dynamic>.from(item.cast());
                        MovieMetadataCache.placeholders[selectId] = Map<String, dynamic>.from(item.cast());
                        widget.navigationState.selectMovie(selectId);
                      },
                      onDelete: widget.title == 'Continue Watching'
                          ? () {
                              if (id.isNotEmpty) {
                                PlayerState.removeFromContinueWatching(id, isAnime: false);
                              }
                            }
                          : null,
                    ),
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
  final VoidCallback? onDelete;

  const _MovieCard({
    required this.item,
    required this.onTap,
    this.onDelete,
  });

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
                              ? CachedNetworkImage(
                                  imageUrl: posterUrl,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 280,
                                  placeholder: (context, url) => _placeholder(),
                                  errorWidget: (context, url, error) => _placeholder(),
                                )
                              : _placeholder(),
                        ),
                      ),
                      // Delete button overlay
                      if (widget.onDelete != null && _isHovered)
                        Positioned(
                          top: 6.0,
                          left: 6.0,
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
                      // Type badge (series vs movie)
                      if (type == 'series' && !(widget.onDelete != null && _isHovered))
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
                      // Score Badge / Hover Add-to-Library Button
                      Positioned(
                        right: 6.0,
                        top: 6.0,
                        child: ListenableBuilder(
                          listenable: LibraryState(),
                          builder: (context, _) {
                            final rawId = item['id']?.toString() ?? '';
                            final int libId = rawId.isEmpty ? 0 : (() {
                              final digits = RegExp(r'\d+').allMatches(rawId).map((m) => m.group(0)!).join();
                              final n = int.tryParse(digits);
                              if (n != null && n > 0) return n;
                              return rawId.hashCode.abs();
                            })();

                            final bool isSavedInLib = libId != 0 && LibraryState().isSaved(libId, 'movies');

                            if (_isHovered) {
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () async {
                                  if (libId == 0) return;
                                  final library = LibraryState();
                                  if (isSavedInLib) {
                                    await library.removeItem(libId, 'movies');
                                    if (context.mounted) NotificationService().show(context, 'Removed from Library');
                                  } else {
                                    await library.saveItem(
                                      id: libId,
                                      mode: 'movies',
                                      format: type == 'series' ? 'TV' : 'MOVIE',
                                      libraryStatus: 'planning',
                                      rating: rating ?? 0.0,
                                      watchedEpisodes: 0,
                                    );
                                    await library.updateMovieCache(libId, Map<String, dynamic>.from(item.cast()));
                                    if (context.mounted) NotificationService().show(context, 'Added to Library');
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
                              );
                            }

                            return const SizedBox.shrink();
                          },
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
