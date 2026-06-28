import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/suwayomi_service.dart';
import '../services/suwayomi_manager.dart';
import '../state/navigation_state.dart';

class MangaTrendingHomePage extends StatefulWidget {
  final NavigationState navigationState;

  const MangaTrendingHomePage({
    super.key,
    required this.navigationState,
  });

  @override
  State<MangaTrendingHomePage> createState() => _MangaTrendingHomePageState();
}

class _MangaTrendingHomePageState extends State<MangaTrendingHomePage> {
  final SuwayomiService _suwayomiService = SuwayomiService();
  
  List<String> _pinnedSourceIds = [];
  List<dynamic> _allSources = [];
  bool _isLoadingSources = true;
  
  // Caching fetched manga list per source ID and type
  final Map<String, List<dynamic>> _popularCache = {};
  final Map<String, List<dynamic>> _latestCache = {};
  
  final Map<String, bool> _loadingPopularStatus = {};
  final Map<String, bool> _loadingLatestStatus = {};
  
  final Map<String, String> _popularErrors = {};
  final Map<String, String> _latestErrors = {};

  @override
  void initState() {
    super.initState();
    _initDashboard();
  }

  Future<void> _initDashboard() async {
    // Auto-start Suwayomi server if not running
    await SuwayomiManager.start();
    if (!mounted) return;
    
    await _loadPins();
    await _loadSources();
  }

  // Load Pinned Source IDs from SharedPreferences
  Future<void> _loadPins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('pinned_manga_sources');
      if (mounted) {
        setState(() {
          _pinnedSourceIds = list ?? [];
        });
      }
    } catch (_) {}
  }

  // Save Pinned Source IDs to SharedPreferences
  Future<void> _savePins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('pinned_manga_sources', _pinnedSourceIds);
    } catch (_) {}
  }

  // Load all installed manga sources from Suwayomi
  Future<void> _loadSources() async {
    if (!mounted) return;
    setState(() => _isLoadingSources = true);
    
    try {
      final list = await _suwayomiService.getSources();
      if (mounted) {
        setState(() {
          _allSources = list;
          _isLoadingSources = false;
        });
        
        // Auto-pin first source if list is completely empty
        if (_pinnedSourceIds.isEmpty && _allSources.isNotEmpty) {
          setState(() {
            _pinnedSourceIds = [_allSources.first['id']?.toString() ?? ''];
          });
          await _savePins();
        }
        
        // Load feeds for pinned sources
        _loadAllFeeds();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSources = false);
      }
    }
  }

  // Trigger parallel fetching of all pinned source popular/latest feeds
  void _loadAllFeeds() {
    for (final id in _pinnedSourceIds) {
      _loadSourceFeeds(id);
    }
  }

  // Load both feeds for a source
  Future<void> _loadSourceFeeds(String sourceId) async {
    if (sourceId.isEmpty) return;
    
    _loadPopularFeed(sourceId);
    _loadLatestFeed(sourceId);
  }

  // Load popular feed for a source
  Future<void> _loadPopularFeed(String sourceId) async {
    setState(() {
      _loadingPopularStatus[sourceId] = true;
      _popularErrors.remove(sourceId);
    });

    try {
      final list = await _suwayomiService.fetchSourceManga(sourceId: sourceId, page: 1, latest: false);
      if (mounted) {
        setState(() {
          _popularCache[sourceId] = list;
          _loadingPopularStatus[sourceId] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _popularErrors[sourceId] = "Failed to load popular items";
          _loadingPopularStatus[sourceId] = false;
        });
      }
    }
  }

  // Load latest feed for a source
  Future<void> _loadLatestFeed(String sourceId) async {
    setState(() {
      _loadingLatestStatus[sourceId] = true;
      _latestErrors.remove(sourceId);
    });

    try {
      final list = await _suwayomiService.fetchSourceManga(sourceId: sourceId, page: 1, latest: true);
      if (mounted) {
        setState(() {
          _latestCache[sourceId] = list;
          _loadingLatestStatus[sourceId] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _latestErrors[sourceId] = "Failed to load new updates";
          _loadingLatestStatus[sourceId] = false;
        });
      }
    }
  }

  // Show bottom sheet configuration dialog to toggle pins (max 5)
  void _showManagePinsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0F11),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pin Extensions (Max 5)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    'Selected: ${_pinnedSourceIds.length} / 5',
                    style: const TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
                  ),
                  const SizedBox(height: 16.0),
                  Expanded(
                    child: _allSources.isEmpty
                        ? const Center(
                            child: Text(
                              'No extensions installed. Install them in the Search tab first.',
                              style: TextStyle(color: Colors.white38, fontFamily: 'Outfit'),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: _allSources.length,
                            separatorBuilder: (c, i) => const Divider(color: Colors.white10, height: 1.0),
                            itemBuilder: (context, index) {
                              final source = _allSources[index];
                              final String sId = source['id']?.toString() ?? '';
                              final String name = source['name'] ?? 'Unknown Source';
                              final String lang = source['lang'] ?? 'en';
                              final bool isPinned = _pinnedSourceIds.contains(sId);

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(name, style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 14.0)),
                                subtitle: Text(lang.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit')),
                                trailing: IconButton(
                                  icon: Icon(
                                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                                    color: isPinned ? const Color(0xFFFF9F1C) : Colors.white38,
                                    size: 20.0,
                                  ),
                                  onPressed: () async {
                                    setModalState(() {
                                      if (isPinned) {
                                        _pinnedSourceIds.remove(sId);
                                      } else {
                                        if (_pinnedSourceIds.length >= 5) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('You can only pin up to 5 extensions.', style: TextStyle(fontFamily: 'Outfit')),
                                              backgroundColor: Colors.redAccent,
                                            ),
                                          );
                                          return;
                                        }
                                        _pinnedSourceIds.add(sId);
                                      }
                                    });
                                    
                                    // Mirror state to parent widget
                                    setState(() {});
                                    await _savePins();
                                    
                                    // Load feeds for the newly pinned source
                                    if (!isPinned) {
                                      _loadSourceFeeds(sId);
                                    }
                                  },
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

  // Build a horizontal list widget for either popular or latest manga
  Widget _buildHorizontalMangaList({
    required String sourceId,
    required List<dynamic> mangaList,
    required bool isLoading,
    required String? error,
    required bool isMobile,
  }) {
    return SizedBox(
      height: 185.0,
      child: isLoading
          ? _buildShimmerLoadingRow()
          : error != null
              ? Center(
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12.0, fontFamily: 'Outfit'),
                  ),
                )
              : mangaList.isEmpty
                  ? const Center(
                      child: Text(
                        'No items available.',
                        style: TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      cacheExtent: 400.0,
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      itemCount: mangaList.length,
                      itemBuilder: (context, index) {
                        final item = mangaList[index];
                        final String title = item['title'] ?? 'Untitled';
                        final String coverUrl = item['thumbnailUrl'] ?? '';
                        final String mId = item['id']?.toString() ?? '';

                        return RepaintBoundary(
                          child: GestureDetector(
                            onTap: () {
                              if (mId.isNotEmpty) {
                                widget.navigationState.selectManga(mId);
                              }
                            },
                            child: Container(
                              width: 105.0,
                              margin: const EdgeInsets.only(right: 12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.03),
                                        borderRadius: BorderRadius.circular(6.0),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.3),
                                            blurRadius: 4.0,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(5.0),
                                        child: coverUrl.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: coverUrl,
                                                fit: BoxFit.cover,
                                                memCacheWidth: 250,
                                                fadeInDuration: const Duration(milliseconds: 150),
                                                placeholder: (c, u) => Container(color: Colors.white10),
                                                errorWidget: (c, u, e) => const Center(
                                                  child: Icon(Icons.book, color: Colors.white24, size: 24.0),
                                                ),
                                              )
                                            : const Center(
                                                child: Icon(Icons.book, color: Colors.white24, size: 24.0),
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6.0),
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  // Build a single source section (Popular + Latest stacked)
  Widget _buildRailwayRow(String sourceId, String sourceName, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Source extension title row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                sourceName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white38, size: 18.0),
                onPressed: () => _loadSourceFeeds(sourceId),
                tooltip: 'Refresh feeds',
              ),
            ],
          ),
        ),
        const SizedBox(height: 4.0),

        // Popular subheader
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            'Popular',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'Outfit',
            ),
          ),
        ),
        const SizedBox(height: 6.0),
        _buildHorizontalMangaList(
          sourceId: sourceId,
          mangaList: _popularCache[sourceId] ?? [],
          isLoading: _loadingPopularStatus[sourceId] ?? false,
          error: _popularErrors[sourceId],
          isMobile: isMobile,
        ),
        const SizedBox(height: 16.0),

        // Latest updates subheader
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            'New Updates',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'Outfit',
            ),
          ),
        ),
        const SizedBox(height: 6.0),
        _buildHorizontalMangaList(
          sourceId: sourceId,
          mangaList: _latestCache[sourceId] ?? [],
          isLoading: _loadingLatestStatus[sourceId] ?? false,
          error: _latestErrors[sourceId],
          isMobile: isMobile,
        ),
        const SizedBox(height: 28.0),
      ],
    );
  }

  // Shimmer loading card row placeholders
  Widget _buildShimmerLoadingRow() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          width: 105.0,
          margin: const EdgeInsets.only(right: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                ),
              ),
              const SizedBox(height: 6.0),
              Container(
                height: 10.0,
                width: 70.0,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: isMobile ? 12.0 : 48.0),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Manga Home',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Outfit',
                      fontSize: 22.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showManagePinsSheet,
                    icon: const Icon(Icons.push_pin, size: 14),
                    label: const Text('Manage Pins', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, fontFamily: 'Outfit')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.0),
                        side: const BorderSide(color: Colors.white10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24.0),
            
            // Pinned source railways list
            Expanded(
              child: _isLoadingSources
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                    )
                  : _pinnedSourceIds.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.push_pin_outlined, size: 48.0, color: Colors.white24),
                                const SizedBox(height: 16.0),
                                const Text(
                                  'Your trending feed is empty.',
                                  style: TextStyle(color: Colors.white54, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                ),
                                const SizedBox(height: 8.0),
                                const Text(
                                  'Pin up to 5 extensions to show popular & new items on the homepage.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
                                ),
                                const SizedBox(height: 24.0),
                                ElevatedButton.icon(
                                  onPressed: _showManagePinsSheet,
                                  icon: const Icon(Icons.add, size: 16.0),
                                  label: const Text('Pin Extensions', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: _pinnedSourceIds.length,
                          itemBuilder: (context, index) {
                            final String sId = _pinnedSourceIds[index];
                            
                            // Safe iteration to find the source name and bypass List firstWhere sound null safety TypeErrors
                            Map<String, dynamic>? sourceMap;
                            for (final s in _allSources) {
                              if (s['id']?.toString() == sId) {
                                sourceMap = s as Map<String, dynamic>?;
                                break;
                              }
                            }
                            final String sourceName = sourceMap?['name'] ?? 'Manga Source';
                            
                            return _buildRailwayRow(sId, sourceName, isMobile);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
