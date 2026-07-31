import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import 'package:flutter/material.dart';
import '../state/library_state.dart';
import '../state/navigation_state.dart';
import '../services/anilist_service.dart';
import '../services/tmdb_service.dart';
import '../services/download_service.dart';
import '../services/suwayomi_service.dart';
import '../services/image_cache_service.dart';
import '../widgets/smooth_scroll_area.dart';

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
  SharedPreferences? _prefs;
  bool _showCategoryCounts = true;

  final AnilistService _anilistService = AnilistService();
  final TmdbService _tmdbService = TmdbService();

  bool _isLoading = true;
  String? _errorMessage;
  bool _isBackgroundFetchingMissing = false;
  bool _isBackgroundFetchingMissingAnime = false;
  bool _isUpdatingLibrary = false;
  double _mangaUpdateProgress = 0.0;
  String _mangaUpdateStatusText = '';
  final Set<int> _attemptedFetchIds = {};
  bool _isSelectionMode = false;
  final Set<int> _selectedItemIds = {};
  Timer? _libraryChangedDebounce;

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
    _initPrefs();
    _loadLibraryData();
    LibraryState().addListener(_onLibraryChanged);
    DownloadService().addListener(_onLibraryChanged);
    widget.navigationState.addListener(_onNavigationChanged);
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _showCategoryCounts = _prefs?.getBool('show_category_item_counts') ?? true;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _libraryChangedDebounce?.cancel();
    LibraryState().removeListener(_onLibraryChanged);
    DownloadService().removeListener(_onLibraryChanged);
    widget.navigationState.removeListener(_onNavigationChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onNavigationChanged() {
    final nav = widget.navigationState;
    final isCurrentMode = nav.currentMode == widget.mode;
    final isCurrentPage = nav.currentPage == TabPage.library;
    if (isCurrentMode && isCurrentPage) {
      _loadLibraryData();
    }
  }

  void _onLibraryChanged() {
    _libraryChangedDebounce?.cancel();
    _libraryChangedDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      final nav = widget.navigationState;
      final isCurrentMode = nav.currentMode == widget.mode;
      final isCurrentPage = nav.currentPage == TabPage.library;
      if (isCurrentMode && isCurrentPage) {
        _loadLibraryData();
      }
    });
  }

  // Load basic details for all saved IDs in this mode
  // Load basic details for all saved IDs in this mode
  void _loadLibraryData() {
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
      final List<int> missingIds = [];

      if (widget.mode == AppMode.anime) {
        final cache = LibraryState().animeCache;
        final list = <Map<String, dynamic>>[];
        
        for (final item in savedItems) {
          if (cache.containsKey(item.id)) {
            list.add(cache[item.id]!);
          } else if (!_attemptedFetchIds.contains(item.id)) {
            missingIds.add(item.id);
          }
        }
        
        loadedMedia = list;

        if (missingIds.isNotEmpty) {
          _triggerBackgroundFetchMissingAnime(missingIds);
        }
      } else if (widget.mode == AppMode.manga) {
        final cache = LibraryState().mangaCache;
        final list = <Map<String, dynamic>>[];
        
        for (final item in savedItems) {
          if (cache.containsKey(item.id)) {
            list.add(cache[item.id]!);
          } else if (!_attemptedFetchIds.contains(item.id)) {
            missingIds.add(item.id);
          }
        }
        
        loadedMedia = list;

        if (missingIds.isNotEmpty) {
          _triggerBackgroundFetchMissing(missingIds);
        }
      } else {
        // Movies/Series (TMDB)
        final cache = LibraryState().movieCache;
        final list = <Map<String, dynamic>>[];
        
        for (final item in savedItems) {
          if (cache.containsKey(item.id)) {
            list.add(cache[item.id]!);
          } else if (!_attemptedFetchIds.contains(item.id)) {
            missingIds.add(item.id);
          }
        }
        
        loadedMedia = list;

        if (missingIds.isNotEmpty) {
          _triggerBackgroundFetchMissingMovies(missingIds);
        }
      }

      if (mounted) {
        setState(() {
          _fetchedMedia = loadedMedia;
          _isLoading = loadedMedia.isEmpty && missingIds.isNotEmpty;
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
    _attemptedFetchIds.addAll(missingIds);

    try {
      final List<Map<String, dynamic>> fetchedDetails = [];
      await Future.wait(missingIds.map((id) async {
        try {
          final details = await SuwayomiService().getMangaDetails(id);
          if (details != null) {
            fetchedDetails.add(details);
          }
        } catch (_) {}
      }));

      if (fetchedDetails.isNotEmpty) {
        final Map<int, Map<String, dynamic>> cacheBatch = {};
        for (final details in fetchedDetails) {
          final int id = details['id'] as int;
          cacheBatch[id] = details;

          final item = LibraryState().getItem(id, 'manga');
          if (item != null) {
            final int totalChapters = (details['chapters'] as List?)?.length ?? 0;
            LibraryState().updateItemEpisodesInMemory(id, 'manga', totalChapters);
          }
        }
        LibraryState().updateMangaCacheBatch(cacheBatch);
      }
    } catch (_) {} finally {
      _isBackgroundFetchingMissing = false;
      if (mounted) {
        _loadLibraryData();
      }
    }
  }

  void _triggerBackgroundFetchMissingMovies(List<int> missingIds) async {
    _attemptedFetchIds.addAll(missingIds);
    try {
      final Map<int, Map<String, dynamic>> batch = {};
      await Future.wait(missingIds.map((id) async {
        try {
          final item = LibraryState().getItem(id, 'movies');
          if (item != null) {
            final details = await _tmdbService.fetchTmdbBasicDetails(id, item.format);
            if (details != null) {
              batch[id] = details;
            }
          }
        } catch (_) {}
      }));
      if (batch.isNotEmpty) {
        LibraryState().updateMovieCacheBatch(batch);
        if (mounted) {
          _loadLibraryData();
        }
      }
    } catch (_) {}
  }

  void _triggerBackgroundFetchMissingAnime(List<int> missingIds) async {
    if (_isBackgroundFetchingMissingAnime) return;
    _isBackgroundFetchingMissingAnime = true;
    _attemptedFetchIds.addAll(missingIds);

    try {
      for (int i = 0; i < missingIds.length; i += 40) {
        final chunk = missingIds.sublist(i, i + 40 > missingIds.length ? missingIds.length : i + 40);
        try {
          final rawList = await _anilistService.fetchMultipleMedia(chunk, 'ANIME');
          final Map<int, Map<String, dynamic>> batch = {};
          for (var media in rawList) {
            final int id = media['id'];
            batch[id] = media;
          }
          if (batch.isNotEmpty) {
            LibraryState().updateAnimeCacheBatch(batch);
            if (mounted) {
              _loadLibraryData();
            }
          }
        } catch (_) {}
        // Sleep 400ms between batches to stay well under rate limits
        await Future.delayed(const Duration(milliseconds: 400));
      }
    } catch (_) {} finally {
      _isBackgroundFetchingMissingAnime = false;
    }
  }

  Future<void> _forceRefreshAnimeLibrary() async {
    final modeStr = widget.mode.name;
    final savedItems = LibraryState().items.where((item) => item.mode == modeStr).toList();
    if (savedItems.isEmpty) {
      NotificationService().show(context, 'No library items to refresh.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final ids = savedItems.map((item) => item.id).toList();
      for (int i = 0; i < ids.length; i += 40) {
        final chunk = ids.sublist(i, i + 40 > ids.length ? ids.length : i + 40);
        final rawList = await _anilistService.fetchMultipleMedia(chunk, 'ANIME');
        final Map<int, Map<String, dynamic>> batch = {};
        for (var media in rawList) {
          final int id = media['id'];
          batch[id] = media;
        }
        if (batch.isNotEmpty) {
          LibraryState().updateAnimeCacheBatch(batch);
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (mounted) {
        NotificationService().show(context, 'Library details refreshed successfully.');
      }
    } catch (e) {
      if (mounted) {
        NotificationService().show(context, 'Failed to refresh library: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _loadLibraryData();
      }
    }
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
      NotificationService().show(context, 'No manga items to update.');
      return;
    }

    setState(() {
      _isUpdatingLibrary = true;
      _mangaUpdateProgress = 0.0;
      _mangaUpdateStatusText = 'Initializing update...';
    });

    int updatedCount = 0;
    try {
      for (int i = 0; i < savedItems.length; i++) {
        final item = savedItems[i];
        final cached = LibraryState().mangaCache[item.id];
        final String displayName = cached?['title'] ?? 'Manga #${item.id}';
        
        setState(() {
          _mangaUpdateStatusText = 'Updating: $displayName';
          _mangaUpdateProgress = i / savedItems.length;
        });

        final freshDetails = await SuwayomiService().getMangaDetails(item.id);
        if (freshDetails != null) {
          final chaptersList = await SuwayomiService().getChapters(item.id);
          final totalChapters = chaptersList.length;

          LibraryState().updateMangaCache(item.id, freshDetails);

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

        setState(() {
          _mangaUpdateProgress = (i + 1) / savedItems.length;
        });
      }
    } catch (e) {
      debugPrint('[LibraryPage] Manga library update error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingLibrary = false;
          _mangaUpdateProgress = 1.0;
          _mangaUpdateStatusText = '';
        });
        _loadLibraryData();
        NotificationService().show(context, 'Manga update complete! Updated $updatedCount of ${savedItems.length} manga.');
        NotificationService().showNativeNotification(
          'Manga Library Updated',
          'Successfully updated $updatedCount of ${savedItems.length} manga.',
        );
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



  String _getMediaTitle(dynamic media) {
    if (widget.mode == AppMode.manga) {
      return (media['title'] ?? '').toString();
    }
    if (widget.mode == AppMode.movies) {
      if (media['title'] is Map) {
        return (media['title']?['english'] ?? media['title']?['romaji'] ?? 'Untitled').toString();
      } else if (media['title'] is String) {
        return media['title'] as String;
      } else if (media['name'] is String) {
        return media['name'] as String;
      }
      return 'Untitled';
    }
    return (media['title']?['english'] ?? media['title']?['romaji'] ?? 'Untitled').toString();
  }

  double _getMediaRating(dynamic media) {
    if (widget.mode == AppMode.movies) {
      if (media['averageScore'] != null) {
        return (media['averageScore'] as num).toDouble();
      } else if (media['imdbRating'] != null) {
        final score = double.tryParse(media['imdbRating'].toString()) ?? 0.0;
        return score * 10.0;
      }
      return 0.0;
    }
    return media['averageScore'] != null ? (media['averageScore'] as num).toDouble() : 0.0;
  }

  int _getMediaId(dynamic media) {
    if (media == null) return 0;
    final rawId = media['id'];
    if (rawId is int) return rawId;
    if (rawId is String) {
      if (widget.mode == AppMode.movies) {
        final digits = RegExp(r'\d+').allMatches(rawId).map((m) => m.group(0)!).join();
        final parsed = int.tryParse(digits);
        if (parsed != null && parsed > 0) return parsed;
      }
      return int.tryParse(rawId) ?? rawId.hashCode.abs();
    }
    return 0;
  }

  List<dynamic> _sortItems(List<dynamic> items) {
    items.sort((a, b) {
      switch (_selectedSort) {
        case 'DATE_ADDED_DESC':
          return _getAddedDate(_getMediaId(b)).compareTo(_getAddedDate(_getMediaId(a)));
        case 'DATE_ADDED_ASC':
          return _getAddedDate(_getMediaId(a)).compareTo(_getAddedDate(_getMediaId(b)));
        case 'RATING_DESC':
          final rA = _getMediaRating(a);
          final rB = _getMediaRating(b);
          return rB.compareTo(rA);
        case 'TITLE_ASC':
          return _getMediaTitle(a).toLowerCase().compareTo(_getMediaTitle(b).toLowerCase());
        case 'TITLE_DESC':
          return _getMediaTitle(b).toLowerCase().compareTo(_getMediaTitle(a).toLowerCase());
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

  List<dynamic> _applyFilters(List<dynamic> items) {
    // 1. Search Query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      items = items.where((media) {
        if (widget.mode == AppMode.manga) {
          final title = (media['title'] ?? '').toString().toLowerCase();
          return title.contains(query);
        }
        if (widget.mode == AppMode.movies) {
          String t = '';
          if (media['title'] is Map) {
            t = (media['title']?['english'] ?? media['title']?['romaji'] ?? '').toString();
          } else if (media['title'] is String) {
            t = media['title'] as String;
          } else if (media['name'] is String) {
            t = media['name'] as String;
          }
          return t.toLowerCase().contains(query);
        }
        final title = (media['title']?['english'] ?? media['title']?['romaji'] ?? '').toString().toLowerCase();
        final nativeTitle = (media['title']?['native'] ?? '').toString().toLowerCase();
        return title.contains(query) || nativeTitle.contains(query);
      }).toList();
    }

    // 2. Format / Read Status Filter
    if (_selectedFormat != 'ALL') {
      items = items.where((media) {
        if (widget.mode == AppMode.manga) {
          final savedItem = LibraryState().getItem(media['id'], 'manga');
          if (savedItem == null) return false;
          final readCount = savedItem.watchedEpisodes;
          final totalCount = savedItem.totalEpisodes ?? 0;
          
          final sel = _selectedFormat.toUpperCase();
          if (sel == 'UNREAD') {
            return readCount == 0;
          } else if (sel == 'STARTED') {
            return readCount > 0 && (totalCount == 0 || readCount < totalCount);
          } else if (sel == 'COMPLETED') {
            return readCount > 0 && totalCount > 0 && readCount == totalCount;
          }
          return true;
        }

        final fmt = (media['format'] ?? media['type'] ?? '').toString().toUpperCase();
        final sel = _selectedFormat.toUpperCase();
        if (sel == 'TV') {
          return fmt == 'TV' || fmt == 'SERIES';
        }
        return fmt == sel;
      }).toList();
    }

    // 3. Status Filter
    if (_selectedStatus != 'ALL') {
      items = items.where((media) {
        if (widget.mode == AppMode.movies) {
          final userStatus = _getLibraryStatus(_getMediaId(media));
          return userStatus.toLowerCase() == _selectedStatus.toLowerCase();
        } else {
          final stat = (media['status'] ?? '').toString().replaceAll('_', ' ').toUpperCase();
          return stat == _selectedStatus.toUpperCase();
        }
      }).toList();
    }

    // 4. Sort
    return _sortItems(items);
  }

  void _selectAllVisibleItems([String? activeCategoryId]) {
    List<dynamic> items = List.from(_fetchedMedia);

    if (widget.mode == AppMode.manga && activeCategoryId != null && activeCategoryId.isNotEmpty) {
      final modeStr = widget.mode.name;
      items = items.where((media) {
        final savedItem = LibraryState().getItem(_getMediaId(media), modeStr);
        if (activeCategoryId == 'UNCATEGORIZED') {
          return savedItem == null || savedItem.categoryIds.isEmpty;
        } else {
          return savedItem != null && savedItem.categoryIds.contains(activeCategoryId);
        }
      }).toList();
    }

    final filteredMedia = _applyFilters(items);
    final visibleIds = filteredMedia.map((m) => _getMediaId(m)).where((id) => id > 0).toSet();

    setState(() {
      _isSelectionMode = true;
      final isAllSelected = visibleIds.isNotEmpty && visibleIds.every((id) => _selectedItemIds.contains(id));
      if (isAllSelected) {
        _selectedItemIds.removeAll(visibleIds);
      } else {
        _selectedItemIds.addAll(visibleIds);
      }
    });
  }

  Widget _buildCategoryGrid(String categoryId, bool isMobile) {
    final modeStr = widget.mode.name;
    var items = _fetchedMedia.where((media) {
      final savedItem = LibraryState().getItem(_getMediaId(media), modeStr);
      if (categoryId == 'UNCATEGORIZED') {
        return savedItem == null || savedItem.categoryIds.isEmpty;
      } else {
        return savedItem != null && savedItem.categoryIds.contains(categoryId);
      }
    }).toList();

    items = _applyFilters(items);

    if (items.isEmpty) {
      return _buildEmptyStateForCategory(categoryId);
    }

    return SmoothScrollArea(
      builder: (controller, physics) => GridView.builder(
        controller: controller,
        physics: physics,
        addAutomaticKeepAlives: false,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150.0,
          mainAxisExtent: 248.0,
          crossAxisSpacing: 14.0,
          mainAxisSpacing: 14.0,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final media = items[index];
          final int id = _getMediaId(media);
          return _LibraryMediaCard(
            key: ValueKey('${widget.mode.name}_$id'),
            media: media,
            mode: widget.mode,
            isSelectionMode: _isSelectionMode,
            isSelected: _selectedItemIds.contains(id),
            onTap: () {
              if (_isSelectionMode) {
                setState(() {
                  if (_selectedItemIds.contains(id)) {
                    _selectedItemIds.remove(id);
                  } else {
                    _selectedItemIds.add(id);
                  }
                });
              } else {
                if (widget.mode == AppMode.anime) {
                  widget.navigationState.selectAnime(id);
                } else if (widget.mode == AppMode.manga) {
                  widget.navigationState.selectManga(id.toString());
                } else {
                  final type = media['format'] == 'MOVIE' ? 'movie' : 'series';
                  final rawIdStr = id.toString();
                  final isNumericOnly = RegExp(r'^\d+$').hasMatch(rawIdStr);
                  final realId = isNumericOnly ? 'tt${rawIdStr.padLeft(7, '0')}' : rawIdStr;
                  widget.navigationState.selectMovie('$type:$realId');
                }
              }
            },
          );
        },
      ),
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
      return ['ALL', 'watching', 'planning', 'completed', 'paused_dropped'];
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
      final cats = LibraryState().categories.where((cat) => cat.mode == 'manga').toList();
      final savedItems = LibraryState().items.where((item) => item.mode == 'manga').toList();
      final hasUncategorized = savedItems.any((item) => item.categoryIds.isEmpty);

      final List<String> tabIds = [];
      final List<String> tabNames = [];

      for (final cat in cats) {
        tabIds.add(cat.id);
        if (_showCategoryCounts) {
          final count = savedItems.where((item) => item.categoryIds.contains(cat.id)).length;
          tabNames.add('${cat.name} ($count)');
        } else {
          tabNames.add(cat.name);
        }
      }

      if (hasUncategorized || (cats.isEmpty && savedItems.isNotEmpty)) {
        tabIds.add('UNCATEGORIZED');
        if (_showCategoryCounts) {
          final count = savedItems.where((item) => item.categoryIds.isEmpty).length;
          tabNames.add('Uncategorized ($count)');
        } else {
          tabNames.add('Uncategorized');
        }
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
        child: Builder(
          builder: (context) {
            final controller = DefaultTabController.of(context);
            return ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final activeIndex = controller.index;
                final activeId = tabIds.isNotEmpty && activeIndex < tabIds.length ? tabIds[activeIndex] : '';

                return Scaffold(
                  backgroundColor: Colors.transparent,
              bottomNavigationBar: _buildSelectionActionBar(activeCategoryId: activeId),
              body: Padding(
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
                        if (isMobile) ...[
                          const SizedBox(width: 8.0),
                          Builder(
                            builder: (context) {
                              final controller = DefaultTabController.of(context);
                              final activeIndex = controller.index;
                              final activeId = tabIds.isNotEmpty && activeIndex < tabIds.length ? tabIds[activeIndex] : '';
                              final activeName = tabNames.isNotEmpty && activeIndex < tabNames.length ? tabNames[activeIndex] : '';

                              return PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: Colors.white70),
                                tooltip: 'Library Options',
                                onSelected: (String value) {
                                  if (value == 'full') {
                                    _runMangaUpdate(onlyCategory: false);
                                  } else if (value == 'category') {
                                    if (activeId.isNotEmpty) {
                                      _runMangaUpdate(onlyCategory: true, categoryId: activeId, categoryName: activeName);
                                    }
                                  } else if (value == 'manage') {
                                    _showManageCategoriesDialog();
                                  } else if (value == 'select') {
                                    setState(() {
                                      _isSelectionMode = !_isSelectionMode;
                                      _selectedItemIds.clear();
                                    });
                                  } else if (value == 'select_all') {
                                    _selectAllVisibleItems(activeId);
                                  }
                                },
                                itemBuilder: (BuildContext context) {
                                  return <PopupMenuEntry<String>>[
                                    const PopupMenuItem<String>(
                                      value: 'full',
                                      child: Row(
                                        children: [
                                          Icon(Icons.refresh, size: 18, color: Colors.white70),
                                          SizedBox(width: 8.0),
                                          Text('Update Full Library', style: TextStyle(fontFamily: 'Outfit')),
                                        ],
                                      ),
                                    ),
                                    if (activeId.isNotEmpty && activeId != 'UNCATEGORIZED')
                                      PopupMenuItem<String>(
                                        value: 'category',
                                        child: Row(
                                          children: [
                                            const Icon(Icons.sync, size: 18, color: Colors.white70),
                                            const SizedBox(width: 8.0),
                                            Text('Update Current Category', style: const TextStyle(fontFamily: 'Outfit')),
                                          ],
                                        ),
                                      ),
                                    const PopupMenuDivider(),
                                    const PopupMenuItem<String>(
                                      value: 'manage',
                                      child: Row(
                                        children: [
                                          Icon(Icons.category_outlined, size: 18, color: Colors.white70),
                                          SizedBox(width: 8.0),
                                          Text('Manage Categories', style: TextStyle(fontFamily: 'Outfit')),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'select_all',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.select_all, size: 18, color: Color(0xFF2EC4B6)),
                                          const SizedBox(width: 8.0),
                                          Text('Select Category Items', style: const TextStyle(fontFamily: 'Outfit', color: Color(0xFF2EC4B6), fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'select',
                                      child: Row(
                                        children: [
                                          Icon(
                                            _isSelectionMode ? Icons.check_box : Icons.check_box_outlined,
                                            size: 18,
                                            color: _isSelectionMode ? Colors.blueAccent : Colors.white70,
                                          ),
                                          const SizedBox(width: 8.0),
                                          Text(
                                            _isSelectionMode ? 'Cancel Selection' : 'Select Items',
                                            style: const TextStyle(fontFamily: 'Outfit'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ];
                                },
                              );
                            }
                          ),
                        ] else ...[
                          const SizedBox(width: 8.0),
                          Builder(
                            builder: (context) {
                              return PopupMenuButton<String>(
                                icon: const Icon(Icons.refresh, color: Colors.white70),
                                tooltip: 'Update Options',
                                onSelected: (String value) {
                                  final controller = DefaultTabController.of(context);
                                  final activeIndex = controller.index;
                                  final activeId = tabIds[activeIndex];
                                  final activeName = tabNames[activeIndex];
                                  if (value == 'full') {
                                    _runMangaUpdate(onlyCategory: false);
                                  } else if (value == 'category') {
                                    _runMangaUpdate(onlyCategory: true, categoryId: activeId, categoryName: activeName);
                                  }
                                },
                                itemBuilder: (BuildContext context) {
                                  return <PopupMenuEntry<String>>[
                                    const PopupMenuItem<String>(
                                      value: 'full',
                                      child: Text('Update Full Library', style: TextStyle(fontFamily: 'Outfit')),
                                    ),
                                    const PopupMenuItem<String>(
                                      value: 'category',
                                      child: Text('Update Current Category', style: TextStyle(fontFamily: 'Outfit')),
                                    ),
                                  ];
                                },
                              );
                            }
                          ),
                          const SizedBox(width: 4.0),
                          IconButton(
                            icon: const Icon(Icons.category_outlined, color: Colors.white70),
                            tooltip: 'Manage Categories',
                            onPressed: _showManageCategoriesDialog,
                          ),
                          const SizedBox(width: 4.0),
                          IconButton(
                            icon: Icon(
                              _isSelectionMode ? Icons.check_box : Icons.check_box_outlined,
                              color: _isSelectionMode ? Colors.blueAccent : Colors.white70,
                            ),
                            tooltip: 'Select Items',
                            onPressed: () {
                              setState(() {
                                _isSelectionMode = !_isSelectionMode;
                                _selectedItemIds.clear();
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                    if (_isUpdatingLibrary) ...[
                      const SizedBox(height: 12.0),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(10.0),
                          border: Border.all(color: Colors.blueAccent.withOpacity(0.3), width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const SizedBox(
                                  width: 14.0,
                                  height: 14.0,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                                const SizedBox(width: 10.0),
                                Expanded(
                                  child: Text(
                                    _mangaUpdateStatusText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Outfit',
                                      fontSize: 13.0,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${(_mangaUpdateProgress * 100).toInt()}%',
                                  style: const TextStyle(
                                    color: Colors.blueAccent,
                                    fontFamily: 'Outfit',
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8.0),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4.0),
                              child: LinearProgressIndicator(
                                value: _mangaUpdateProgress,
                                backgroundColor: Colors.white10,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                                minHeight: 4.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
          },
        );
      }
    ),
  );
    } else if (widget.mode == AppMode.movies) {
      final displayItems = _applyFilters(List.from(_fetchedMedia));

      return Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: _buildSelectionActionBar(),
        body: Padding(
          padding: EdgeInsets.only(
            top: isMobile ? 16.0 : 48.0,
            left: isMobile ? 12.0 : 24.0,
            right: isMobile ? 12.0 : 24.0,
            bottom: 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Movies & TV Shows',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.0,
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16.0),

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
                              const SizedBox(width: 8.0),
                              _buildSelectionModeToggle(),
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
                        const SizedBox(width: 12.0),
                        _buildSelectionModeToggle(),
                      ],
                    ),
              const SizedBox(height: 20.0),

              Expanded(
                child: displayItems.isEmpty
                    ? _buildEmptyState()
                    : SmoothScrollArea(
                        builder: (controller, physics) => GridView.builder(
                          controller: controller,
                          physics: physics,
                          addAutomaticKeepAlives: false,
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 150.0,
                            mainAxisExtent: 248.0,
                            crossAxisSpacing: 14.0,
                            mainAxisSpacing: 14.0,
                          ),
                          itemCount: displayItems.length,
                          itemBuilder: (context, index) {
                            final media = displayItems[index];
                            final int id = _getMediaId(media);
                            return _LibraryMediaCard(
                              key: ValueKey('${widget.mode.name}_$id'),
                              media: media,
                              mode: widget.mode,
                              isSelectionMode: _isSelectionMode,
                              isSelected: _selectedItemIds.contains(id),
                              onTap: () {
                                if (_isSelectionMode) {
                                  setState(() {
                                    if (_selectedItemIds.contains(id)) {
                                      _selectedItemIds.remove(id);
                                    } else {
                                      _selectedItemIds.add(id);
                                    }
                                  });
                                } else {
                                  final type = media['format'] == 'MOVIE' ? 'movie' : 'series';
                                  final rawIdStr = id.toString();
                                  final isNumericOnly = RegExp(r'^\d+$').hasMatch(rawIdStr);
                                  final realId = isNumericOnly ? 'tt${rawIdStr.padLeft(7, '0')}' : rawIdStr;
                                  widget.navigationState.selectMovie('$type:$realId');
                                }
                              },
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    } else {
      final displayItems = _getStatusFilteredItems();

      return Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: _buildSelectionActionBar(),
        body: Padding(
          padding: EdgeInsets.only(
            top: isMobile ? 16.0 : 48.0,
            left: isMobile ? 12.0 : 24.0,
            right: isMobile ? 12.0 : 24.0,
            bottom: 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusTabs(isMobile),
              const SizedBox(height: 16.0),

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
                              const SizedBox(width: 8.0),
                              IconButton(
                                icon: const Icon(Icons.refresh, color: Colors.white70, size: 18.0),
                                tooltip: 'Refresh Library Details',
                                onPressed: _forceRefreshAnimeLibrary,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(alpha: 0.03),
                                  padding: const EdgeInsets.all(12.0),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              _buildSelectionModeToggle(),
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
                        const SizedBox(width: 12.0),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70, size: 18.0),
                          tooltip: 'Refresh Library Details',
                          onPressed: _forceRefreshAnimeLibrary,
                          style: IconButton.styleFrom(
                             backgroundColor: Colors.white.withValues(alpha: 0.03),
                             padding: const EdgeInsets.all(12.0),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        _buildSelectionModeToggle(),
                      ],
                    ),
              const SizedBox(height: 20.0),

              Expanded(
                child: displayItems.isEmpty
                    ? _buildEmptyState()
                    : SmoothScrollArea(
                        builder: (controller, physics) => GridView.builder(
                          controller: controller,
                          physics: physics,
                          addAutomaticKeepAlives: false,
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 150.0,
                            mainAxisExtent: 248.0,
                            crossAxisSpacing: 14.0,
                            mainAxisSpacing: 14.0,
                          ),
                          itemCount: displayItems.length,
                          itemBuilder: (context, index) {
                            final media = displayItems[index];
                            final int id = _getMediaId(media);
                            return _LibraryMediaCard(
                              key: ValueKey('${widget.mode.name}_$id'),
                              media: media,
                              mode: widget.mode,
                              isSelectionMode: _isSelectionMode,
                              isSelected: _selectedItemIds.contains(id),
                              onTap: () {
                                if (_isSelectionMode) {
                                  setState(() {
                                    if (_selectedItemIds.contains(id)) {
                                      _selectedItemIds.remove(id);
                                    } else {
                                      _selectedItemIds.add(id);
                                    }
                                  });
                                } else {
                                  if (widget.mode == AppMode.anime) {
                                    widget.navigationState.selectAnime(id);
                                  } else {
                                    final type = media['format'] == 'MOVIE' ? 'movie' : 'series';
                                    final rawIdStr = id.toString();
                                    final isNumericOnly = RegExp(r'^\d+$').hasMatch(rawIdStr);
                                    final realId = isNumericOnly ? 'tt${rawIdStr.padLeft(7, '0')}' : rawIdStr;
                                    widget.navigationState.selectMovie('$type:$realId');
                                  }
                                }
                              },
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    }
  }

  List<dynamic> _getStatusFilteredItems() {
    List<dynamic> items = List.from(_fetchedMedia);

    if (_activeStatusTab != 'ALL') {
      if (_activeStatusTab == 'downloaded') {
        items = items.where((media) {
          return DownloadService().tasks.any((task) =>
              task.anilistId == _getMediaId(media) &&
              task.status == DownloadStatus.completed);
        }).toList();
      } else {
        items = items.where((media) => _getLibraryStatus(_getMediaId(media)) == _activeStatusTab).toList();
      }
    }
    return _applyFilters(items);
  }

  Widget _buildStatusTabs(bool isMobile) {
    final modeStr = widget.mode.name;
    final savedItems = LibraryState().items.where((item) => item.mode == modeStr).toList();

    final Map<String, String> statusTabs = {
      'ALL': 'All',
      'watching': 'Watching',
      'planning': 'Planning',
      'completed': 'Completed',
      'paused_dropped': 'Dropped / Paused',
      'downloaded': 'Downloaded',
    };

    final children = statusTabs.entries.map((entry) {
      final bool isActive = _activeStatusTab == entry.key;
      String label = entry.value;

      if (_showCategoryCounts) {
        int count = 0;
        if (entry.key == 'ALL') {
          count = savedItems.length;
        } else if (entry.key == 'downloaded') {
          count = savedItems.where((item) {
            return DownloadService().tasks.any((task) =>
                task.anilistId == item.id &&
                task.status == DownloadStatus.completed);
          }).length;
        } else {
          count = savedItems.where((item) => item.libraryStatus == entry.key).length;
        }
        label = '$label ($count)';
      }

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
            label,
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

  Widget _buildSelectionModeToggle() {
    return IconButton(
      icon: Icon(
        _isSelectionMode ? Icons.check_box : Icons.check_box_outlined,
        color: _isSelectionMode ? Colors.blueAccent : Colors.white70,
        size: 18.0,
      ),
      tooltip: 'Select Items',
      onPressed: () {
        setState(() {
          _isSelectionMode = !_isSelectionMode;
          _selectedItemIds.clear();
        });
      },
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.03),
        padding: const EdgeInsets.all(12.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      ),
    );
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
                          StatefulBuilder(
                            builder: (context, setDialogState) {
                              return SwitchListTile(
                                title: const Text('Show Item Counts on Categories', style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                                subtitle: const Text('Display total items next to category tab names', style: TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit')),
                                value: _showCategoryCounts,
                                activeColor: const Color(0xFF2EC4B6),
                                contentPadding: EdgeInsets.zero,
                                onChanged: (val) async {
                                  setState(() => _showCategoryCounts = val);
                                  setDialogState(() {});
                                  if (_prefs != null) {
                                    await _prefs!.setBool('show_category_item_counts', val);
                                  }
                                },
                              );
                            },
                          ),
                          const Divider(color: Colors.white10, height: 20),
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
                                final cats = LibraryState().categories.where((c) => c.mode == modeStr).toList();
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
    Map<String, String>? displayMap;
    if (widget.mode == AppMode.movies) {
      displayMap = {
        'ALL': 'All Types',
        'MOVIE': 'Movies',
        'TV': 'TV Series',
      };
    }

    return _buildDropdownFilter(
      label: widget.mode == AppMode.movies ? 'Type' : 'Format',
      value: _selectedFormat,
      options: _formatOptions,
      displayValues: displayMap,
      onChanged: (val) {
        if (val != null) setState(() => _selectedFormat = val);
      },
    );
  }

  Widget _buildStatusFilter() {
    Map<String, String>? displayMap;
    if (widget.mode == AppMode.movies) {
      displayMap = {
        'ALL': 'All Statuses',
        'watching': 'Watching',
        'planning': 'Planning',
        'completed': 'Completed',
        'paused_dropped': 'Dropped / Paused',
      };
    }

    return _buildDropdownFilter(
      label: 'Status',
      value: _selectedStatus,
      options: _statusOptions,
      displayValues: displayMap,
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





  Widget _buildSelectionActionBar({String? activeCategoryId}) {
    if (!_isSelectionMode) {
      return const SizedBox.shrink();
    }

    List<dynamic> items = List.from(_fetchedMedia);
    if (widget.mode == AppMode.manga && activeCategoryId != null && activeCategoryId.isNotEmpty) {
      final modeStr = widget.mode.name;
      items = items.where((media) {
        final savedItem = LibraryState().getItem(_getMediaId(media), modeStr);
        if (activeCategoryId == 'UNCATEGORIZED') {
          return savedItem == null || savedItem.categoryIds.isEmpty;
        } else {
          return savedItem != null && savedItem.categoryIds.contains(activeCategoryId);
        }
      }).toList();
    }

    final filteredMedia = _applyFilters(items);
    final visibleIds = filteredMedia.map((m) => _getMediaId(m)).where((id) => id > 0).toSet();
    final bool allSelected = visibleIds.isNotEmpty && visibleIds.every((id) => _selectedItemIds.contains(id));
    final String buttonLabel = widget.mode == AppMode.manga
        ? (allSelected ? 'Deselect Category' : 'Select Category')
        : (allSelected ? 'Deselect All' : 'Select All');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF141417),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10.0,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                TextButton.icon(
                  icon: Icon(allSelected ? Icons.deselect : Icons.select_all, size: 18, color: const Color(0xFF2EC4B6)),
                  label: Text(
                    buttonLabel,
                    style: const TextStyle(color: Color(0xFF2EC4B6), fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                  onPressed: () => _selectAllVisibleItems(activeCategoryId),
                ),
                const SizedBox(width: 12.0),
                Text(
                  '${_selectedItemIds.length} selected',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.0,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                if (widget.mode == AppMode.manga) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.category, size: 18, color: Colors.blueAccent),
                    label: const Text('Categories', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                    onPressed: _selectedItemIds.isNotEmpty ? _showMassCategoryDialog : null,
                  ),
                  const SizedBox(width: 12.0),
                ],
                TextButton.icon(
                  icon: const Icon(Icons.playlist_add_check, size: 18, color: Colors.green),
                  label: const Text('Status', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  onPressed: _selectedItemIds.isNotEmpty ? _showMassStatusDialog : null,
                ),
                const SizedBox(width: 12.0),
                TextButton.icon(
                  icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                  label: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  onPressed: _selectedItemIds.isNotEmpty ? _showMassDeleteConfirmDialog : null,
                ),
                const SizedBox(width: 16.0),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedItemIds.clear();
                    });
                  },
                  tooltip: 'Close selection mode',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMassDeleteConfirmDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141414),
          title: const Text('Confirm Delete', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
          content: Text(
            'Are you sure you want to delete ${_selectedItemIds.length} items from your library?',
            style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38, fontFamily: 'Outfit')),
            ),
            ElevatedButton(
              onPressed: () async {
                final scaffoldContext = context;
                Navigator.pop(context);
                final modeStr = widget.mode.name;
                for (final id in _selectedItemIds) {
                  await LibraryState().removeItem(id, modeStr);
                }
                setState(() {
                  _selectedItemIds.clear();
                  _isSelectionMode = false;
                });
                _loadLibraryData();
                if (mounted) {
                  NotificationService().show(scaffoldContext, 'Successfully deleted items from library.');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showMassStatusDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      constraints: const BoxConstraints(maxWidth: 500.0),
      builder: (BuildContext context) {
        final isManga = widget.mode == AppMode.manga;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isManga ? 'Mark ${_selectedItemIds.length} items' : 'Change Status for ${_selectedItemIds.length} items',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                  ),
                ),
                const SizedBox(height: 20.0),
                if (isManga) ...[
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                    title: const Text('Mark as Read', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                    onTap: () => _updateMassStatus('completed'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.history_toggle_off_outlined, color: Colors.blueAccent),
                    title: const Text('Mark as Unread', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                    onTap: () => _updateMassStatus('watching'),
                  ),
                ] else ...[
                  ListTile(
                    leading: const Icon(Icons.play_circle_outline, color: Colors.blueAccent),
                    title: const Text('Watching', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                    onTap: () => _updateMassStatus('watching'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bookmark_outline, color: Colors.white70),
                    title: const Text('Planning', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                    onTap: () => _updateMassStatus('planning'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                    title: const Text('Completed', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                    onTap: () => _updateMassStatus('completed'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.pause_circle_outline, color: Colors.redAccent),
                    title: const Text('Dropped / Paused', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                    onTap: () => _updateMassStatus('paused_dropped'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateMassStatus(String newStatus) async {
    Navigator.pop(context);
    final modeStr = widget.mode.name;
    for (final id in _selectedItemIds) {
      final item = LibraryState().getItem(id, modeStr);
      if (item != null) {
        await LibraryState().saveItem(
          id: item.id,
          mode: item.mode,
          format: item.format,
          libraryStatus: newStatus,
          rating: item.rating,
          watchedEpisodes: item.watchedEpisodes,
          totalEpisodes: item.totalEpisodes,
          categoryIds: item.categoryIds,
        );
      }
    }
    setState(() {
      _selectedItemIds.clear();
      _isSelectionMode = false;
    });
    _loadLibraryData();
    if (mounted) {
      NotificationService().show(context, 'Successfully updated status for selected items.');
    }
  }

  void _showMassCategoryDialog() {
    final modeStr = widget.mode.name;
    final cats = LibraryState().categories.where((cat) => cat.mode == modeStr).toList();
    if (cats.isEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF141414),
            title: const Text('No Categories', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
            content: const Text(
              'You don\'t have any categories created yet. Please create categories first.',
              style: TextStyle(color: Colors.white70, fontFamily: 'Outfit'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: Colors.blueAccent, fontFamily: 'Outfit')),
              ),
            ],
          );
        },
      );
      return;
    }

    final List<String> selectedCatIds = [];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      constraints: const BoxConstraints(maxWidth: 500.0),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Assign Categories to ${_selectedItemIds.length} items',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.bold,
                        fontSize: 16.0,
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: cats.length,
                        itemBuilder: (context, index) {
                          final cat = cats[index];
                          final bool isChecked = selectedCatIds.contains(cat.id);
                          return CheckboxListTile(
                            title: Text(cat.name, style: const TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                            value: isChecked,
                            activeColor: Colors.blueAccent,
                            checkColor: Colors.white,
                            onChanged: (bool? val) {
                              setModalState(() {
                                if (val == true) {
                                  selectedCatIds.add(cat.id);
                                } else {
                                  selectedCatIds.remove(cat.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white38, fontFamily: 'Outfit')),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final scaffoldContext = context;
                              Navigator.pop(context);
                              final modeStr = widget.mode.name;
                              for (final id in _selectedItemIds) {
                                final item = LibraryState().getItem(id, modeStr);
                                if (item != null) {
                                  await LibraryState().saveItem(
                                    id: item.id,
                                    mode: item.mode,
                                    format: item.format,
                                    libraryStatus: item.libraryStatus,
                                    rating: item.rating,
                                    watchedEpisodes: item.watchedEpisodes,
                                    totalEpisodes: item.totalEpisodes,
                                    categoryIds: selectedCatIds,
                                  );
                                }
                              }
                              setState(() {
                                _selectedItemIds.clear();
                                _isSelectionMode = false;
                              });
                              _loadLibraryData();
                              if (mounted) {
                                NotificationService().show(scaffoldContext, 'Successfully updated categories.');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            ),
                            child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

}

class _LibraryMediaCard extends StatefulWidget {
  final dynamic media;
  final AppMode mode;
  final VoidCallback onTap;

  final bool isSelectionMode;
  final bool isSelected;

  const _LibraryMediaCard({
    super.key,
    required this.media,
    required this.mode,
    required this.onTap,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  @override
  State<_LibraryMediaCard> createState() => _LibraryMediaCardState();
}

class _LibraryMediaCardState extends State<_LibraryMediaCard> {
  bool _isHovered = false;
  String? _localCoverPath;

  @override
  void initState() {
    super.initState();
    _loadLocalCoverPath();
  }

  @override
  void didUpdateWidget(_LibraryMediaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media != widget.media || oldWidget.mode != widget.mode) {
      _loadLocalCoverPath();
    }
  }

  Future<void> _loadLocalCoverPath() async {
    final id = _getMediaId();
    if (id == 0) return;
    final modeStr = widget.mode.name;
    final path = await LibraryImageCache().getLocalPath(id, modeStr, 'cover');
    if (mounted) setState(() => _localCoverPath = path);
  }

  int _getMediaId() {
    final rawId = widget.media['id'];
    if (rawId is int) return rawId;
    if (rawId is String) {
      if (widget.mode == AppMode.movies) {
        final digits = RegExp(r'\d+').allMatches(rawId).map((m) => m.group(0)!).join();
        final parsed = int.tryParse(digits);
        if (parsed != null && parsed > 0) return parsed;
      }
      return int.tryParse(rawId) ?? rawId.hashCode.abs();
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    String coverUrl = '';
    String title = 'Untitled';
    double? rating;
    String format = '';

    if (widget.mode == AppMode.manga) {
      coverUrl = widget.media['thumbnailUrl'] ?? '';
      title = widget.media['title'] ?? 'Untitled';
      format = 'MANGA';
    } else if (widget.mode == AppMode.movies) {
      if (widget.media['title'] is Map) {
        title = widget.media['title']?['english'] ?? widget.media['title']?['romaji'] ?? 'Untitled';
      } else if (widget.media['title'] is String) {
        title = widget.media['title'] as String;
      } else if (widget.media['name'] is String) {
        title = widget.media['name'] as String;
      }

      if (widget.media['coverImage'] is Map) {
        coverUrl = widget.media['coverImage']?['large'] ?? '';
      } else if (widget.media['coverImage'] is String) {
        coverUrl = widget.media['coverImage'] as String;
      } else if (widget.media['poster'] is String) {
        coverUrl = widget.media['poster'] as String;
      } else if (widget.media['poster_path'] is String) {
        coverUrl = 'https://image.tmdb.org/t/p/w300${widget.media['poster_path']}';
      }

      if (widget.media['averageScore'] != null) {
        rating = (widget.media['averageScore'] as num).toDouble();
      } else if (widget.media['imdbRating'] != null) {
        final score = double.tryParse(widget.media['imdbRating'].toString()) ?? 0.0;
        rating = score * 10;
      }

      if (widget.media['format'] is String) {
        format = widget.media['format'] as String;
      } else if (widget.media['type']?.toString() == 'series') {
        format = 'TV';
      } else if (widget.media['type']?.toString() == 'movie') {
        format = 'MOVIE';
      }
    } else {
      coverUrl = widget.media['coverImage']?['large'] ?? '';
      title = widget.media['title']?['english'] ?? widget.media['title']?['romaji'] ?? 'Untitled';
      rating = widget.media['averageScore'] != null ? (widget.media['averageScore'] as num).toDouble() : null;
      format = widget.media['format'] ?? '';
    }
    final bool isMovie = format == 'MOVIE';

    // Retrieve user progress details from LibraryState
    final modeStr = widget.mode.name;
    final int libId = _getMediaId();
    final savedItem = LibraryState().getItem(libId, modeStr);
    
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

    return RepaintBoundary(
      child: MouseRegion(
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
                        child: LibraryImageCache().buildWidget(
                          localPath: _localCoverPath,
                          networkUrl: coverUrl.isNotEmpty ? coverUrl : null,
                          fit: BoxFit.cover,
                          memCacheWidth: 250,
                        ),
                      ),

                      // Selection checkbox overlay
                      if (widget.isSelectionMode) ...[
                        Positioned.fill(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            color: widget.isSelected
                                ? Colors.blueAccent.withValues(alpha: 0.25)
                                : Colors.black.withValues(alpha: 0.1),
                          ),
                        ),
                        Positioned(
                          top: 8.0,
                          right: 8.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.isSelected ? Colors.blueAccent : Colors.black54,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            padding: const EdgeInsets.all(2.0),
                            child: widget.isSelected
                                ? const Icon(Icons.check, size: 12.0, color: Colors.white)
                                : const SizedBox(width: 12.0, height: 12.0),
                          ),
                        ),
                      ],

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
    ),);
  }
}

