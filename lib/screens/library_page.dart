import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../state/library_state.dart';
import '../state/navigation_state.dart';
import '../services/anilist_service.dart';
import '../services/tmdb_service.dart';
import '../services/download_service.dart';
import '../services/suwayomi_service.dart';

class LibraryPage extends StatefulWidget {
  final AppMode mode;
  final NavigationState navigationState;

  const LibraryPage({
    super.key,
    required this.mode,
    required this.navigationState,
  });

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final AnilistService _anilistService = AnilistService();
  final TmdbService _tmdbService = TmdbService();

  bool _isLoading = true;
  String? _errorMessage;
  bool _isBackgroundFetchingMissing = false;
  bool _isUpdatingLibrary = false;

  // Real-time fetched items
  List<dynamic> _fetchedMedia = [];

  // Tab & Filter states
  String _activeStatusTab = 'ALL';
  String _searchQuery = '';
  String _selectedFormat = 'ALL';
  String _selectedStatus = 'ALL';
  String _selectedSort = 'DATE_ADDED_DESC'; // 'DATE_ADDED_DESC', 'DATE_ADDED_ASC', 'RATING_DESC', 'TITLE_ASC', 'TITLE_DESC'

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLibraryData();
    LibraryState().addListener(_onLibraryChanged);
    DownloadService().addListener(_onLibraryChanged);
  }

  @override
  void dispose() {
    LibraryState().removeListener(_onLibraryChanged);
    DownloadService().removeListener(_onLibraryChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) {
      _loadLibraryData();
    }
  }

  // Load basic details for all saved IDs in this mode
  Future<void> _loadLibraryData() async {
    final modeStr = widget.mode.name;
    final savedItems = LibraryState().items.where((item) => item.mode == modeStr).toList();

    if (savedItems.isEmpty) {
      if (mounted) {
        setState(() {
          _fetchedMedia = [];
          _isLoading = false;
        });
      }
      return;
    }

    try {
      List<dynamic> loadedMedia = [];

      if (widget.mode == AppMode.anime) {
        final ids = savedItems.map((item) => item.id).toList();
        final rawList = await _anilistService.fetchMultipleMedia(ids, 'ANIME');
        loadedMedia = rawList;
      } else if (widget.mode == AppMode.manga) {
        final cache = LibraryState().mangaCache;
        final list = <Map<String, dynamic>>[];
        final missingIds = <int>[];
        
        for (final item in savedItems) {
          if (cache.containsKey(item.id)) {
            list.add(cache[item.id]!);
          } else {
            missingIds.add(item.id);
          }
        }
        
        loadedMedia = list;

        if (missingIds.isNotEmpty) {
          _triggerBackgroundFetchMissing(missingIds);
        }
      } else {
        // Movies/Series (TMDB)
        final futures = savedItems.map((item) => _tmdbService.fetchTmdbBasicDetails(item.id, item.format));
        final results = await Future.wait(futures);
        loadedMedia = results.whereType<Map<String, dynamic>>().toList();
      }

      if (mounted) {
        setState(() {
          _fetchedMedia = loadedMedia;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _triggerBackgroundFetchMissing(List<int> missingIds) async {
    if (_isBackgroundFetchingMissing) return;
    _isBackgroundFetchingMissing = true;

    try {
      for (final id in missingIds) {
        final details = await SuwayomiService().getMangaDetails(id);
        if (details != null) {
          await LibraryState().updateMangaCache(id, details);

          final item = LibraryState().getItem(id, 'manga');
          if (item != null) {
            await LibraryState().saveItem(
              id: item.id,
              mode: item.mode,
              format: item.format,
              libraryStatus: item.libraryStatus,
              rating: item.rating,
              watchedEpisodes: item.watchedEpisodes,
              totalEpisodes: item.totalEpisodes,
              categoryIds: item.categoryIds,
            );
          }
        }
      }
    } catch (_) {} finally {
      _isBackgroundFetchingMissing = false;
      if (mounted) {
        _loadLibraryData();
      }
    }
  }

  void _showUpdateLibraryDialog(List<String> tabIds, List<String> tabNames) {
    final controller = DefaultTabController.of(context);
    final activeIndex = controller.index;
    final activeId = tabIds[activeIndex];
    final activeName = tabNames[activeIndex];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      constraints: const BoxConstraints(maxWidth: 500.0),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Update Options',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                  ),
                ),
                const SizedBox(height: 20.0),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _runMangaUpdate(onlyCategory: false);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white10,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14.0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                        ),
                        child: const Text('Update Library', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0, fontFamily: 'Outfit')),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _runMangaUpdate(onlyCategory: true, categoryId: activeId, categoryName: activeName);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14.0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                        ),
                        child: Text('Update "$activeName"', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0, fontFamily: 'Outfit')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white38, fontFamily: 'Outfit')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _runMangaUpdate({
    required bool onlyCategory,
    String? categoryId,
    String? categoryName,
  }) async {
    final modeStr = widget.mode.name;
    var savedItems = LibraryState().items.where((item) => item.mode == modeStr).toList();

    if (onlyCategory && categoryId != null) {
      savedItems = savedItems.where((item) {
        if (categoryId == 'UNCATEGORIZED') {
          return item.categoryIds.isEmpty;
        } else {
          return item.categoryIds.contains(categoryId);
        }
      }).toList();
    }

    if (savedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No manga items to update.')),
      );
      return;
    }

    setState(() {
      _isUpdatingLibrary = true;
    });

    final progressTextNotifier = ValueNotifier<String>('0 / ${savedItems.length}');
    final progressValueNotifier = ValueNotifier<double>(0.0);
    final currentMangaTitleNotifier = ValueNotifier<String>('Initializing update...');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF141414),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    onlyCategory
                        ? 'Updating Category "$categoryName"...'
                        : 'Updating Library...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.bold,
                      fontSize: 16.0,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  ValueListenableBuilder<String>(
                    valueListenable: currentMangaTitleNotifier,
                    builder: (context, title, _) {
                      return Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13.0),
                      );
                    },
                  ),
                  const SizedBox(height: 16.0),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.0),
                    child: ValueListenableBuilder<double>(
                      valueListenable: progressValueNotifier,
                      builder: (context, val, _) {
                        return LinearProgressIndicator(
                          value: val,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                          minHeight: 6.0,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ValueListenableBuilder<String>(
                      valueListenable: progressTextNotifier,
                      builder: (context, txt, _) {
                        return Text(
                          txt,
                          style: const TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    int updatedCount = 0;
    try {
      for (int i = 0; i < savedItems.length; i++) {
        final item = savedItems[i];
        final cached = LibraryState().mangaCache[item.id];
        final String displayName = cached?['title'] ?? 'Manga #${item.id}';
        currentMangaTitleNotifier.value = 'Updating: $displayName';

        final freshDetails = await SuwayomiService().getMangaDetails(item.id);
        if (freshDetails != null) {
          final chaptersList = await SuwayomiService().getChapters(item.id);
          final totalChapters = chaptersList.length;

          await LibraryState().updateMangaCache(item.id, freshDetails);

          await LibraryState().saveItem(
            id: item.id,
            mode: item.mode,
            format: item.format,
            libraryStatus: item.libraryStatus,
            rating: item.rating,
            watchedEpisodes: item.watchedEpisodes,
            totalEpisodes: totalChapters,
            categoryIds: item.categoryIds,
          );

          updatedCount++;
        }

        progressValueNotifier.value = (i + 1) / savedItems.length;
        progressTextNotifier.value = '${i + 1} / ${savedItems.length}';
      }
    } catch (e) {
      debugPrint('[LibraryPage] Manga library update error: $e');
    } finally {
      setState(() {
        _isUpdatingLibrary = false;
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Manga update complete! Updated $updatedCount of ${savedItems.length} manga.')),
        );
        _loadLibraryData();
      }
    }
  }

  // Get library detail field helpers
  DateTime _getAddedDate(int id) {
    final modeStr = widget.mode.name;
    final match = LibraryState().items.firstWhere(
      (item) => item.id == id && item.mode == modeStr,
      orElse: () => LibraryItem(id: id, mode: modeStr, format: '', addedAt: DateTime.fromMillisecondsSinceEpoch(0), libraryStatus: 'planning', rating: 0.0, watchedEpisodes: 0),
    );
    return match.addedAt;
  }

  String _getLibraryStatus(int id) {
    final modeStr = widget.mode.name;
    final match = LibraryState().items.firstWhere(
      (item) => item.id == id && item.mode == modeStr,
      orElse: () => LibraryItem(id: id, mode: modeStr, format: '', addedAt: DateTime.fromMillisecondsSinceEpoch(0), libraryStatus: 'planning', rating: 0.0, watchedEpisodes: 0),
    );
    return match.libraryStatus;
  }



  List<dynamic> _sortItems(List<dynamic> items) {
    items.sort((a, b) {
      switch (_selectedSort) {
        case 'DATE_ADDED_DESC':
          return _getAddedDate(b['id']).compareTo(_getAddedDate(a['id']));
        case 'DATE_ADDED_ASC':
          return _getAddedDate(a['id']).compareTo(_getAddedDate(b['id']));
        case 'RATING_DESC':
          final rA = a['averageScore'] != null ? (a['averageScore'] as num).toDouble() : 0.0;
          final rB = b['averageScore'] != null ? (b['averageScore'] as num).toDouble() : 0.0;
          return rB.compareTo(rA);
        case 'TITLE_ASC':
          final tA = (a['title']?['english'] ?? a['title']?['romaji'] ?? '').toString().toLowerCase();
          final tB = (b['title']?['english'] ?? b['title']?['romaji'] ?? '').toString().toLowerCase();
          return tA.compareTo(tB);
        case 'TITLE_DESC':
          final tA = (a['title']?['english'] ?? a['title']?['romaji'] ?? '').toString().toLowerCase();
          final tB = (b['title']?['english'] ?? b['title']?['romaji'] ?? '').toString().toLowerCase();
          return tB.compareTo(tA);
        default:
          return 0;
      }
    });
    return items;
  }

  Widget _buildEmptyStateForCategory(String categoryId) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bookmark_outline, size: 40.0, color: Colors.white24),
          const SizedBox(height: 12.0),
          Text(
            categoryId == 'UNCATEGORIZED'
                ? 'No uncategorized items.'
                : 'No items in this category yet.',
            style: const TextStyle(color: Colors.white38, fontSize: 13.0, fontFamily: 'Outfit'),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(String categoryId, bool isMobile) {
    final modeStr = widget.mode.name;
    var items = _fetchedMedia.where((media) {
      final savedItem = LibraryState().getItem(media['id'], modeStr);
      if (categoryId == 'UNCATEGORIZED') {
        return savedItem == null || savedItem.categoryIds.isEmpty;
      } else {
        return savedItem != null && savedItem.categoryIds.contains(categoryId);
      }
    }).toList();

    // 1. Search Query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      items = items.where((media) {
        final title = (media['title']?['english'] ?? media['title']?['romaji'] ?? '').toString().toLowerCase();
        final nativeTitle = (media['title']?['native'] ?? '').toString().toLowerCase();
        return title.contains(query) || nativeTitle.contains(query);
      }).toList();
    }

    // 2. Format Filter
    if (_selectedFormat != 'ALL') {
      items = items.where((media) {
        final fmt = (media['format'] ?? '').toString().toUpperCase();
        final sel = _selectedFormat.toUpperCase();
        if (sel == 'TV') {
          return fmt == 'TV' || fmt == 'SERIES';
        }
        return fmt == sel;
      }).toList();
    }

    // 3. Status Filter (API)
    if (_selectedStatus != 'ALL') {
      items = items.where((media) {
        final stat = (media['status'] ?? '').toString().replaceAll('_', ' ').toUpperCase();
        return stat == _selectedStatus.toUpperCase();
      }).toList();
    }

    // 4. Sort
    items = _sortItems(items);

    if (items.isEmpty) {
      return _buildEmptyStateForCategory(categoryId);
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150.0,
        mainAxisExtent: 248.0,
        crossAxisSpacing: 14.0,
        mainAxisSpacing: 14.0,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final media = items[index];
        return _LibraryMediaCard(
          media: media,
          mode: widget.mode,
          onTap: () {
            if (widget.mode == AppMode.anime) {
              widget.navigationState.selectAnime(media['id']);
            } else if (widget.mode == AppMode.manga) {
              widget.navigationState.selectManga(media['id'].toString());
            } else {
              final type = media['format'] == 'MOVIE' ? 'movie' : 'series';
              final rawIdStr = media['id'].toString();
              final isNumericOnly = RegExp(r'^\d+$').hasMatch(rawIdStr);
              final realId = isNumericOnly ? 'tt${rawIdStr.padLeft(7, '0')}' : rawIdStr;
              widget.navigationState.selectMovie('$type:$realId');
            }
          },
        );
      },
    );
  }

  // Options for Format dropdown
  List<String> get _formatOptions {
    if (widget.mode == AppMode.anime) {
      return ['ALL', 'TV', 'MOVIE', 'SPECIAL', 'OVA', 'ONA', 'MUSIC'];
    } else if (widget.mode == AppMode.manga) {
      return ['ALL', 'MANGA', 'NOVEL', 'ONE_SHOT'];
    } else {
      return ['ALL', 'MOVIE', 'TV'];
    }
  }

  // Options for Status dropdown
  List<String> get _statusOptions {
    if (widget.mode == AppMode.movies) {
      return ['ALL', 'Released', 'In Production', 'Post Production'];
    }
    return ['ALL', 'FINISHED', 'RELEASING', 'NOT YET RELEASED', 'CANCELLED', 'HIATUS'];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
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
                'Error loading library:\n$_errorMessage',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit'),
              ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _loadLibraryData();
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

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    if (widget.mode == AppMode.manga) {
      // Manga mode: Category-based layout with swipable TabBar and TabBarView
      final cats = LibraryState().categories.where((cat) => cat.mode == 'manga').toList();
      final savedItems = LibraryState().items.where((item) => item.mode == 'manga').toList();
      final hasUncategorized = savedItems.any((item) => item.categoryIds.isEmpty);

      final List<String> tabIds = [];
      final List<String> tabNames = [];

      for (final cat in cats) {
        tabIds.add(cat.id);
        tabNames.add(cat.name);
      }

      if (hasUncategorized || (cats.isEmpty && savedItems.isNotEmpty)) {
        tabIds.add('UNCATEGORIZED');
        tabNames.add('Uncategorized');
      }

      if (tabIds.isEmpty) {
        // Empty state when library is completely empty
        return Padding(
          padding: EdgeInsets.only(
            top: isMobile ? 16.0 : 48.0,
            left: isMobile ? 12.0 : 24.0,
            right: isMobile ? 12.0 : 24.0,
            bottom: 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.category_outlined, color: Colors.white70),
                  tooltip: 'Manage Categories',
                  onPressed: _showManageCategoriesDialog,
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bookmarks_outlined, size: 48.0, color: Colors.white24),
                      const SizedBox(height: 16.0),
                      const Text(
                        'Your library is empty.',
                        style: TextStyle(color: Colors.white38, fontSize: 14.0, fontFamily: 'Outfit'),
                      ),
                      const SizedBox(height: 24.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Create Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0)),
                            onPressed: _showManageCategoriesDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            ),
                          ),
                          const SizedBox(width: 12.0),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.search, size: 16),
                            label: const Text('Browse Content', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0)),
                            onPressed: () {
                              widget.navigationState.setPage(TabPage.search);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white12,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return DefaultTabController(
        key: ValueKey('tab_controller_${tabIds.length}_manga'),
        length: tabIds.length,
        child: Padding(
          padding: EdgeInsets.only(
            top: isMobile ? 16.0 : 48.0,
            left: isMobile ? 12.0 : 24.0,
            right: isMobile ? 12.0 : 24.0,
            bottom: 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row combining dynamic TabBar and Manage Categories button on the right
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 38.0,
                      alignment: Alignment.centerLeft,
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        dividerColor: Colors.transparent,
                        indicator: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.all(Radius.circular(2.0)),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorPadding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
                        labelColor: Colors.black,
                        unselectedLabelColor: Colors.white70,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 18.0),
                        labelStyle: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 12.0),
                        unselectedLabelStyle: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 12.0),
                        tabs: tabNames.map((name) => Tab(text: name)).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    tooltip: 'Update Library',
                    onPressed: () => _showUpdateLibraryDialog(tabIds, tabNames),
                  ),
                  const SizedBox(width: 4.0),
                  IconButton(
                    icon: const Icon(Icons.category_outlined, color: Colors.white70),
                    tooltip: 'Manage Categories',
                    onPressed: _showManageCategoriesDialog,
                  ),
                ],
              ),
              const SizedBox(height: 16.0),

              // Search & Filter row
              isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSearchBar(),
                        const SizedBox(height: 12.0),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _buildFormatFilter(),
                              const SizedBox(width: 8.0),
                              _buildStatusFilter(),
                              const SizedBox(width: 8.0),
                              _buildSortFilter(),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(flex: 3, child: _buildSearchBar()),
                        const SizedBox(width: 16.0),
                        _buildFormatFilter(),
                        const SizedBox(width: 12.0),
                        _buildStatusFilter(),
                        const SizedBox(width: 12.0),
                        _buildSortFilter(),
                      ],
                    ),
              const SizedBox(height: 20.0),

              // Swipable category grids TabBarView
              Expanded(
                child: TabBarView(
                  physics: const BouncingScrollPhysics(),
                  children: tabIds.map((id) => _buildCategoryGrid(id, isMobile)).toList(),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Anime & Movies Mode: Original status tabs layout with status button row filters
      final displayItems = _getStatusFilteredItems();

      return Padding(
        padding: EdgeInsets.only(
          top: isMobile ? 16.0 : 48.0,
          left: isMobile ? 12.0 : 24.0,
          right: isMobile ? 12.0 : 24.0,
          bottom: 16.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Status Category Tabs (All, Watching, Planning, Completed, Dropped/Paused, Downloaded)
            _buildStatusTabs(isMobile),
            const SizedBox(height: 16.0),

            // 2. Search & Filter Section (Below Tabs)
            isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSearchBar(),
                      const SizedBox(height: 12.0),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            _buildFormatFilter(),
                            const SizedBox(width: 8.0),
                            _buildStatusFilter(),
                            const SizedBox(width: 8.0),
                            _buildSortFilter(),
                          ],
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(flex: 3, child: _buildSearchBar()),
                      const SizedBox(width: 16.0),
                      _buildFormatFilter(),
                      const SizedBox(width: 12.0),
                      _buildStatusFilter(),
                      const SizedBox(width: 12.0),
                      _buildSortFilter(),
                    ],
                  ),
            const SizedBox(height: 20.0),

            // 3. Main Library Grid or Empty State
            Expanded(
              child: displayItems.isEmpty
                  ? _buildEmptyState()
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 150.0,
                        mainAxisExtent: 248.0,
                        crossAxisSpacing: 14.0,
                        mainAxisSpacing: 14.0,
                      ),
                      itemCount: displayItems.length,
                      itemBuilder: (context, index) {
                        final media = displayItems[index];
                        return _LibraryMediaCard(
                          media: media,
                          mode: widget.mode,
                          onTap: () {
                            if (widget.mode == AppMode.anime) {
                              widget.navigationState.selectAnime(media['id']);
                            } else {
                              final type = media['format'] == 'MOVIE' ? 'movie' : 'series';
                              final rawIdStr = media['id'].toString();
                              final isNumericOnly = RegExp(r'^\d+$').hasMatch(rawIdStr);
                              final realId = isNumericOnly ? 'tt${rawIdStr.padLeft(7, '0')}' : rawIdStr;
                              widget.navigationState.selectMovie('$type:$realId');
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    }
  }

  void _showManageCategoriesDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        final textController = TextEditingController();
        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isMobileSheet = screenWidth < 650;
        final String modeStr = widget.mode.name;

        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: isMobileSheet ? double.infinity : 500.0,
            margin: isMobileSheet ? EdgeInsets.zero : const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F11),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
              border: Border.all(color: Colors.white10, width: 1.0),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15.0)),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                      decoration: const BoxDecoration(
                        color: Colors.white12,
                        border: Border(bottom: BorderSide(color: Colors.white10, width: 1.0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Manage Categories',
                            style: TextStyle(color: Colors.white, fontSize: 15.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    // Add new category
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Create Category',
                            style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                          ),
                          const SizedBox(height: 8.0),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 42.0,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(8.0),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                  child: TextField(
                                    controller: textController,
                                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontFamily: 'Outfit'),
                                    decoration: const InputDecoration(
                                      hintText: 'e.g. Favorites, Must Watch...',
                                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13.0),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(vertical: 12.0),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12.0),
                              ElevatedButton(
                                onPressed: () async {
                                  final name = textController.text.trim();
                                  if (name.isNotEmpty) {
                                    await LibraryState().createCategory(name, modeStr);
                                    textController.clear();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                ),
                                child: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20.0),
                          const Text(
                            'Existing Categories',
                            style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                          ),
                          const SizedBox(height: 8.0),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 250.0),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ListenableBuilder(
                              listenable: LibraryState(),
                              builder: (context, _) {
                                final cats = LibraryState().categories;
                                if (cats.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(24.0),
                                    child: Center(
                                      child: Text(
                                        'No custom categories created yet.',
                                        style: TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
                                      ),
                                    ),
                                  );
                                }
                                return ListView.separated(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.all(8.0),
                                  itemCount: cats.length,
                                  separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1.0),
                                  itemBuilder: (context, index) {
                                    final cat = cats[index];
                                    return ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12.0),
                                      title: Text(
                                        cat.name,
                                        style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500, fontFamily: 'Outfit'),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, color: Colors.white54, size: 16),
                                            onPressed: () async {
                                              final renameController = TextEditingController(text: cat.name);
                                              final confirmRename = await showDialog<bool>(
                                                context: context,
                                                builder: (context) => AlertDialog(
                                                  backgroundColor: const Color(0xFF0F0F11),
                                                  title: const Text('Rename Category', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 15.0, fontWeight: FontWeight.bold)),
                                                  content: TextField(
                                                    controller: renameController,
                                                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
                                                    decoration: const InputDecoration(
                                                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                                                    ),
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(context, false),
                                                      child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(context, true),
                                                      child: const Text('Rename', style: TextStyle(color: Colors.white)),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirmRename == true && renameController.text.trim().isNotEmpty) {
                                                await LibraryState().renameCategory(cat.id, renameController.text.trim());
                                              }
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                                            onPressed: () async {
                                              final confirmDelete = await showDialog<bool>(
                                                context: context,
                                                builder: (context) => AlertDialog(
                                                  backgroundColor: const Color(0xFF0F0F11),
                                                  title: const Text('Delete Category?', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 15.0, fontWeight: FontWeight.bold)),
                                                  content: Text('Are you sure you want to delete "${cat.name}"? Entries in this category will not be deleted.', style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontSize: 13.0)),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(context, false),
                                                      child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(context, true),
                                                      child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirmDelete == true) {
                                                await LibraryState().deleteCategory(cat.id);
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12.0),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }



  Widget _buildSearchBar() {
    return Container(
      height: 38.0,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white10),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
        textAlignVertical: TextAlignVertical.center,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8.0),
          hintText: 'Search library...',
          hintStyle: TextStyle(color: Colors.white24, fontSize: 13.0, fontFamily: 'Outfit'),
          prefixIcon: Icon(Icons.search, color: Colors.white38, size: 16),
          prefixIconConstraints: BoxConstraints(
            minWidth: 38,
            maxHeight: 38,
          ),
          border: InputBorder.none,
        ),
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
      ),
    );
  }

  Widget _buildFormatFilter() {
    return _buildDropdownFilter(
      label: 'Format',
      value: _selectedFormat,
      options: _formatOptions,
      onChanged: (val) {
        if (val != null) setState(() => _selectedFormat = val);
      },
    );
  }

  Widget _buildStatusFilter() {
    return _buildDropdownFilter(
      label: 'Status',
      value: _selectedStatus,
      options: _statusOptions,
      onChanged: (val) {
        if (val != null) setState(() => _selectedStatus = val);
      },
    );
  }

  Widget _buildSortFilter() {
    final sortMap = {
      'DATE_ADDED_DESC': 'Newest Added',
      'DATE_ADDED_ASC': 'Oldest Added',
      'RATING_DESC': 'Top Rated',
      'TITLE_ASC': 'Title (A-Z)',
      'TITLE_DESC': 'Title (Z-A)',
    };

    return _buildDropdownFilter(
      label: 'Sort',
      value: _selectedSort,
      options: sortMap.keys.toList(),
      displayValues: sortMap,
      onChanged: (val) {
        if (val != null) setState(() => _selectedSort = val);
      },
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required String value,
    required List<String> options,
    Map<String, String>? displayValues,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 38.0,
      padding: const EdgeInsets.symmetric(horizontal: 10.0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: const Color(0xFF0F0F11),
              borderRadius: BorderRadius.circular(8.0),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white38, size: 16),
              style: const TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
              onChanged: onChanged,
              items: options.map((opt) {
                final display = displayValues != null ? displayValues[opt]! : opt;
                return DropdownMenuItem<String>(
                  value: opt,
                  child: Text(display),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    String emptyMsg = 'Your library is empty.';
    switch (widget.mode) {
      case AppMode.anime:
        emptyMsg = 'No anime matching filters/status.';
        break;
      case AppMode.manga:
        emptyMsg = 'No manga matching filters/status.';
        break;
      case AppMode.movies:
        emptyMsg = 'No movies or series matching filters/status.';
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bookmark_border, size: 48.0, color: Colors.white24),
          const SizedBox(height: 16.0),
          Text(
            emptyMsg,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 14.0,
              fontFamily: 'Outfit',
            ),
          ),
          const SizedBox(height: 20.0),
          ElevatedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Browse Content', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0)),
            onPressed: () {
              widget.navigationState.setPage(TabPage.search);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
            ),
          ),
        ],
      ),
    );
  }

  List<dynamic> _getStatusFilteredItems() {
    final modeStr = widget.mode.name;
    List<dynamic> items = List.from(_fetchedMedia);

    // 1. Filter by Status Tabs (All, Watching, Planning, Completed, Dropped/Paused, Downloaded)
    if (_activeStatusTab != 'ALL') {
      if (_activeStatusTab == 'downloaded') {
        items = items.where((media) {
          return DownloadService().tasks.any((task) =>
              task.anilistId == media['id'] &&
              task.status == DownloadStatus.completed);
        }).toList();
      } else {
        items = items.where((media) => _getLibraryStatus(media['id']) == _activeStatusTab).toList();
      }
    }

    // 2. Filter by Search Query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      items = items.where((media) {
        final title = (media['title']?['english'] ?? media['title']?['romaji'] ?? '').toString().toLowerCase();
        final nativeTitle = (media['title']?['native'] ?? '').toString().toLowerCase();
        return title.contains(query) || nativeTitle.contains(query);
      }).toList();
    }

    // 3. Filter by Format
    if (_selectedFormat != 'ALL') {
      items = items.where((media) {
        final fmt = (media['format'] ?? '').toString().toUpperCase();
        final sel = _selectedFormat.toUpperCase();
        if (sel == 'TV') {
          return fmt == 'TV' || fmt == 'SERIES';
        }
        return fmt == sel;
      }).toList();
    }

    // 4. Filter by Status (API)
    if (_selectedStatus != 'ALL') {
      items = items.where((media) {
        final stat = (media['status'] ?? '').toString().replaceAll('_', ' ').toUpperCase();
        return stat == _selectedStatus.toUpperCase();
      }).toList();
    }

    // 5. Sort
    return _sortItems(items);
  }

  Widget _buildStatusTabs(bool isMobile) {
    final Map<String, String> statusTabs = {
      'ALL': 'All',
      'watching': widget.mode == AppMode.manga ? 'Reading' : 'Watching',
      'planning': 'Planning',
      'completed': 'Completed',
      'paused_dropped': 'Dropped / Paused',
      'downloaded': 'Downloaded',
    };

    final children = statusTabs.entries.map((entry) {
      final bool isActive = _activeStatusTab == entry.key;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _activeStatusTab = entry.key;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 12.0),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(
              color: isActive ? Colors.white : Colors.white10,
              width: 1.0,
            ),
          ),
          child: Text(
            entry.value,
            style: TextStyle(
              color: isActive ? Colors.black : Colors.white70,
              fontSize: 12.0,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
              fontFamily: 'Outfit',
            ),
          ),
        ),
      );
    }).toList();

    return isMobile
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(children: children),
          )
        : Row(children: children);
  }


}

class _LibraryMediaCard extends StatefulWidget {
  final dynamic media;
  final AppMode mode;
  final VoidCallback onTap;

  const _LibraryMediaCard({
    required this.media,
    required this.mode,
    required this.onTap,
  });

  @override
  State<_LibraryMediaCard> createState() => _LibraryMediaCardState();
}

class _LibraryMediaCardState extends State<_LibraryMediaCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final String coverUrl = widget.mode == AppMode.manga
        ? (widget.media['thumbnailUrl'] ?? '')
        : (widget.media['coverImage']?['large'] ?? '');
    final String title = widget.mode == AppMode.manga
        ? (widget.media['title'] ?? 'Untitled')
        : (widget.media['title']?['english'] ?? widget.media['title']?['romaji'] ?? 'Untitled');
    final double? rating = widget.mode == AppMode.manga
        ? null
        : (widget.media['averageScore'] != null
            ? (widget.media['averageScore'] as num).toDouble()
            : null);
    final String format = widget.mode == AppMode.manga
        ? 'MANGA'
        : (widget.media['format'] ?? '');
    final bool isMovie = format == 'MOVIE';

    // Retrieve user progress details from LibraryState
    final modeStr = widget.mode.name;
    final savedItem = LibraryState().getItem(widget.media['id'], modeStr);
    
    final int progress = savedItem?.watchedEpisodes ?? 0;
    final int? total = savedItem?.totalEpisodes;
    final double userRating = savedItem?.rating ?? 0.0;
    final String status = savedItem?.libraryStatus ?? 'watching';

    // Status colors
    Color statusColor = Colors.white38;
    String statusName = 'Planning';
    if (status == 'watching') {
      statusColor = Colors.blueAccent;
      statusName = widget.mode == AppMode.manga ? 'Reading' : 'Watching';
    } else if (status == 'completed') {
      statusColor = Colors.green;
      statusName = 'Completed';
    } else if (status == 'paused_dropped') {
      statusColor = Colors.redAccent;
      statusName = 'Dropped';
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Cover Image
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(
                    color: _isHovered ? Colors.white24 : Colors.white10,
                    width: 1.0,
                  ),
                  boxShadow: [
                    if (_isHovered)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.8),
                        blurRadius: 12.0,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7.0),
                  child: Stack(
                    children: [
                      // Image
                      Positioned.fill(
                        child: coverUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: coverUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 250,
                                placeholder: (context, url) => Container(color: Colors.white.withValues(alpha: 0.02)),
                                errorWidget: (context, url, error) => Container(color: Colors.white.withValues(alpha: 0.02)),
                              )
                            : Container(color: Colors.white.withValues(alpha: 0.02)),
                      ),

                      // Overlay Format badge
                      if (format.isNotEmpty)
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
                              format,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9.0,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ),
                        ),

                      // Status dot overlay on top right
                      if (widget.mode != AppMode.manga)
                        Positioned(
                          top: 8.0,
                          right: 8.0,
                          child: Container(
                            width: 8.0,
                            height: 8.0,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusColor,
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withValues(alpha: 0.5),
                                  blurRadius: 4.0,
                                  spreadRadius: 1.0,
                                ),
                              ],
                            ),
                          ),
                        ),

                      // User Rating overlay (personal score) at bottom left
                      if (userRating > 0.0)
                        Positioned(
                          bottom: 8.0,
                          left: 8.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4.0),
                              border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.3), width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.favorite, color: Colors.pinkAccent, size: 8.0),
                                const SizedBox(width: 2.0),
                                Text(
                                  userRating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.pinkAccent,
                                    fontSize: 9.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Global Rating badge at bottom right
                      if (rating != null)
                        Positioned(
                          bottom: 8.0,
                          right: 8.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4.0),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.2), width: 0.5),
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
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8.0),

            // Card Title text
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _isHovered ? Colors.white : Colors.white70,
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
                fontFamily: 'Outfit',
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4.0),

            // Custom Progress UI (e.g. 12 / 24 ep)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.mode != AppMode.manga)
                  Text(
                    statusName,
                    style: TextStyle(
                      color: statusColor.withValues(alpha: 0.8),
                      fontSize: 10.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  )
                else
                  const SizedBox.shrink(),
                if (!isMovie)
                  Text(
                    total != null 
                        ? '$progress/$total ${widget.mode == AppMode.manga ? 'ch' : 'ep'}'
                        : '$progress ${widget.mode == AppMode.manga ? 'ch' : 'ep'}',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10.0,
                      fontFamily: 'Outfit',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2.0),
            
            // Linear Progress Bar
            if (!isMovie && total != null && total > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(2.0),
                child: LinearProgressIndicator(
                  value: progress / total,
                  minHeight: 2.0,
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              )
            else
              Container(
                height: 2.0,
                color: Colors.white.withValues(alpha: 0.02),
              ),
          ],
        ),
      ),
    );
  }
}
