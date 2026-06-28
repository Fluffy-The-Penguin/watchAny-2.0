import 'package:flutter/material.dart';
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

  // Real-time fetched items
  List<dynamic> _fetchedMedia = [];

  // Tab & Filter states
  String _activeStatusTab = 'ALL'; // 'ALL', 'watching', 'planning', 'completed', 'paused_dropped'
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

      // Safeguard tab state
      final cats = LibraryState().categories;
      if (cats.isEmpty) {
        const validDefaultTabs = {'ALL', 'watching', 'planning', 'completed', 'paused_dropped', 'downloaded'};
        if (!validDefaultTabs.contains(_activeStatusTab)) {
          setState(() {
            _activeStatusTab = 'ALL';
          });
        }
      } else {
        final List<String> validCatTabs = ['ALL', 'UNCATEGORIZED'] + cats.map((c) => c.id).toList();
        if (!validCatTabs.contains(_activeStatusTab)) {
          setState(() {
            _activeStatusTab = 'ALL';
          });
        }
      }
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
        final futures = savedItems.map((item) => SuwayomiService().getMangaDetails(item.id));
        final results = await Future.wait(futures);
        loadedMedia = results.whereType<Map<String, dynamic>>().toList();
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



  // Filtered & Sorted list
  List<dynamic> get _filteredAndSortedItems {
    final modeStr = widget.mode.name;
    List<dynamic> items = List.from(_fetchedMedia);

    // 1. Filter by Status Tabs or Custom Category Tabs
    if (_activeStatusTab != 'ALL') {
      final List<LibraryCategory> cats = LibraryState().categories;
      if (cats.isEmpty) {
        // Fallback to default status tabs filter
        if (_activeStatusTab == 'downloaded') {
          items = items.where((media) {
            return DownloadService().tasks.any((task) =>
                task.anilistId == media['id'] &&
                task.status == DownloadStatus.completed);
          }).toList();
        } else {
          items = items.where((media) => _getLibraryStatus(media['id']) == _activeStatusTab).toList();
        }
      } else {
        // Filter by custom categories
        if (_activeStatusTab == 'UNCATEGORIZED') {
          items = items.where((media) {
            final item = LibraryState().getItem(media['id'], modeStr);
            return item == null || item.categoryIds.isEmpty;
          }).toList();
        } else {
          items = items.where((media) {
            final item = LibraryState().getItem(media['id'], modeStr);
            return item != null && item.categoryIds.contains(_activeStatusTab);
          }).toList();
        }
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

    final displayItems = _filteredAndSortedItems;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

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
          // 1. Status Category Tabs (All, Watching, Planning, Completed, Dropped/Paused)
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
                      mainAxisExtent: 248.0, // Expanded height to display watched status / rating
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
                  ),
          ),
        ],
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
                                                // Reset tab if active tab was the deleted category
                                                if (_activeStatusTab == cat.id) {
                                                  setState(() {
                                                    _activeStatusTab = 'ALL';
                                                  });
                                                }
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

  Widget _buildStatusTabs(bool isMobile) {
    final List<LibraryCategory> cats = LibraryState().categories;

    final Map<String, String> tabs = {};
    if (cats.isEmpty) {
      tabs['ALL'] = 'All';
      tabs['watching'] = widget.mode == AppMode.manga ? 'Reading' : 'Watching';
      tabs['planning'] = 'Planning';
      tabs['completed'] = 'Completed';
      tabs['paused_dropped'] = 'Dropped / Paused';
      tabs['downloaded'] = 'Downloaded';
    } else {
      tabs['ALL'] = 'All';
      tabs['UNCATEGORIZED'] = 'Uncategorized';
      for (final cat in cats) {
        tabs[cat.id] = cat.name;
      }
    }

    final children = tabs.entries.map((entry) {
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

    // Add Manage Categories button at the end
    children.add(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showManageCategoriesDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(
              color: Colors.white10,
              width: 1.0,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_note, color: Colors.white70, size: 16),
              SizedBox(width: 4.0),
              Text(
                'Categories',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12.0,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return isMobile
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(children: children),
          )
        : Row(children: children);
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
                            ? Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheWidth: 250, // Optimize RAM cache
                                errorBuilder: (context, e, s) => Container(color: Colors.white.withValues(alpha: 0.02)),
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
