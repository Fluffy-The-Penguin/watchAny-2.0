import 'package:flutter/material.dart';
import '../services/anilist_service.dart';
import '../services/tmdb_service.dart';
import '../state/navigation_state.dart';

class SearchPage extends StatefulWidget {
  final AppMode mode;
  final NavigationState navigationState;

  const SearchPage({
    super.key,
    required this.mode,
    required this.navigationState,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final AnilistService _anilistService = AnilistService();
  final TmdbService _tmdbService = TmdbService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  List<dynamic> _results = [];
  int _currentPage = 1;
  bool _hasNextPage = false;
  bool _showMobileFilters = false;

  bool get _hasActiveFilters {
    return _selectedGenres.isNotEmpty ||
        _selectedYear != 'ALL' ||
        _selectedSeason != 'ALL' ||
        _selectedFormats.isNotEmpty ||
        _selectedStatus != 'ALL' ||
        _selectedSorting != 'POPULARITY_DESC';
  }

  // Filter States
  List<String> _selectedGenres = [];
  String _selectedYear = 'ALL';
  String _selectedSeason = 'ALL';
  List<String> _selectedFormats = [];
  String _selectedStatus = 'ALL';
  String _selectedSorting = 'POPULARITY_DESC';

  @override
  void initState() {
    super.initState();
    // Perform an initial empty search to show popular items
    _performSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Clear all filters
  void _clearFilters() {
    setState(() {
      _selectedGenres = [];
      _selectedYear = 'ALL';
      _selectedSeason = 'ALL';
      _selectedFormats = [];
      _selectedStatus = 'ALL';
      _selectedSorting = 'POPULARITY_DESC';
    });
    _performSearch();
  }

  Future<void> _performSearch({bool isLoadMore = false}) async {
    if (_isLoading) return;

    if (!isLoadMore) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _currentPage = 1;
        _results = [];
      });
    } else {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final queryText = _searchController.text.trim();
      List<dynamic> newResults = [];

      if (widget.mode == AppMode.movies) {
        // TMDB Movies Search
        int? parsedYear = int.tryParse(_selectedYear);
        String? formatParam = _selectedFormats.isEmpty 
            ? null 
            : (_selectedFormats.contains('Movie') ? 'MOVIE' : 'TV');
            
        // Map Sorting
        String sortBy = 'popularity.desc';
        if (_selectedSorting == 'SCORE_DESC') {
          sortBy = 'vote_average.desc';
        } else if (_selectedSorting == 'START_DATE_DESC') {
          sortBy = 'release_date.desc';
        }

        // Map Genres
        List<int>? genreIds;
        if (_selectedGenres.isNotEmpty) {
          genreIds = _selectedGenres.map((g) => _mapMovieGenreToId(g)).whereType<int>().toList();
        }

        final rawResults = await _tmdbService.searchAndDiscover(
          query: queryText,
          year: parsedYear,
          format: formatParam,
          genres: genreIds,
          sortBy: sortBy,
        );

        newResults = rawResults;
        _hasNextPage = false; // TMDB simple pagination handled per page if needed, for now false
      } else {
        // AniList Anime/Manga Search
        final mediaType = widget.mode == AppMode.anime ? 'ANIME' : 'MANGA';
        int? parsedYear = int.tryParse(_selectedYear);
        
        final response = await _anilistService.search(
          page: _currentPage,
          perPage: 24,
          searchQuery: queryText.isEmpty ? null : queryText,
          type: mediaType,
          genres: _selectedGenres.isEmpty ? null : _selectedGenres,
          year: parsedYear,
          season: _selectedSeason == 'ALL' ? null : _selectedSeason,
          formats: _selectedFormats.isEmpty ? null : _selectedFormats,
          status: _selectedStatus == 'ALL' ? null : _selectedStatus,
          sort: _selectedSorting,
        );

        final pageInfo = response['Page']?['pageInfo'];
        _hasNextPage = pageInfo?['hasNextPage'] ?? false;
        
        final rawResults = response['Page']?['media'] ?? [];
        newResults = rawResults;
      }

      if (mounted) {
        setState(() {
          if (isLoadMore) {
            _results.addAll(newResults);
          } else {
            _results = newResults;
          }
          _isLoading = false;
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

  void _loadMore() {
    if (_hasNextPage && !_isLoading) {
      _currentPage++;
      _performSearch(isLoadMore: true);
    }
  }

  // TMDB Genre to ID mapping
  int? _mapMovieGenreToId(String genreName) {
    final Map<String, int> mapping = {
      'Action': 28,
      'Adventure': 12,
      'Animation': 16,
      'Comedy': 35,
      'Crime': 80,
      'Documentary': 99,
      'Drama': 18,
      'Family': 10751,
      'Fantasy': 14,
      'History': 36,
      'Horror': 27,
      'Music': 10402,
      'Mystery': 9648,
      'Romance': 10749,
      'Sci-Fi': 878,
      'Thriller': 53,
      'War': 10752,
      'Western': 37,
    };
    return mapping[genreName];
  }

  // Available Genres based on Mode
  List<String> get _availableGenres {
    if (widget.mode == AppMode.movies) {
      return ['Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary', 'Drama', 'Family', 'Fantasy', 'History', 'Horror', 'Music', 'Mystery', 'Romance', 'Sci-Fi', 'Thriller', 'War', 'Western'];
    }
    return ['Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy', 'Horror', 'Mahou Shoujo', 'Mecha', 'Music', 'Mystery', 'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural', 'Thriller'];
  }

  // Available Formats based on Mode
  List<String> get _availableFormats {
    if (widget.mode == AppMode.anime) {
      return ['TV', 'TV_SHORT', 'MOVIE', 'SPECIAL', 'OVA', 'ONA', 'MUSIC'];
    } else if (widget.mode == AppMode.manga) {
      return ['MANGA', 'NOVEL', 'ONE_SHOT'];
    } else {
      return ['Movie', 'TV']; // TMDB formats
    }
  }

  // Available Statuses
  List<String> get _availableStatuses {
    return ['FINISHED', 'RELEASING', 'NOT_YET_RELEASED', 'CANCELLED', 'HIATUS'];
  }

  // Available sorting options
  Map<String, String> get _availableSortings {
    if (widget.mode == AppMode.movies) {
      return {
        'POPULARITY_DESC': 'Popularity',
        'SCORE_DESC': 'Rating',
        'START_DATE_DESC': 'Release Date',
      };
    }
    return {
      'POPULARITY_DESC': 'Popularity',
      'TRENDING_DESC': 'Trending',
      'SCORE_DESC': 'Average Score',
      'START_DATE_DESC': 'Release Date',
      'TITLE_ROMAJI': 'Title',
    };
  }

  // Custom filter chip button
  Widget _buildFilterButton({
    required String label,
    required String valueText,
    required VoidCallback onTap,
    required bool isMobile,
    bool? expand,
  }) {
    final bool shouldExpand = expand ?? !isMobile;
    final Widget buttonContent = Padding(
      padding: EdgeInsets.symmetric(horizontal: (isMobile && !shouldExpand) ? 0.0 : 4.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8.0),
          child: Container(
            width: (isMobile && !shouldExpand) ? 110.0 : null,
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(color: Colors.white38, fontSize: 10.0, fontFamily: 'Outfit'),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        valueText,
                        style: const TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.white38, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
    return shouldExpand ? Expanded(child: buttonContent) : buttonContent;
  }

  Widget _buildRow1(bool isMobile, List<String> years, List<String> seasons) {
    final searchInput = Container(
      width: isMobile ? 180.0 : null,
      height: 38.0,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white10),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
        decoration: InputDecoration(
          hintText: widget.mode == AppMode.manga
              ? 'Search manga...'
              : (widget.mode == AppMode.movies ? 'Search movies & series...' : 'Search anime...'),
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13.0),
          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 16),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
        ),
        onSubmitted: (_) => _performSearch(),
      ),
    );

    final Widget searchWrapper = isMobile ? searchInput : Expanded(flex: 3, child: searchInput);

    final rowContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        searchWrapper,
        const SizedBox(width: 8.0),
        
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
            minimumSize: const Size(0, 38),
          ),
          onPressed: () => _performSearch(),
          child: const Icon(Icons.send, size: 14),
        ),
        const SizedBox(width: 4.0),

        _buildFilterButton(
          label: 'Genre',
          valueText: _selectedGenres.isEmpty 
              ? 'ALL' 
              : (_selectedGenres.length == 1 ? _selectedGenres.first : '${_selectedGenres.length} selected'),
          onTap: _showMultiSelectGenres,
          isMobile: isMobile,
        ),

        _buildFilterButton(
          label: 'Year',
          valueText: _selectedYear,
          onTap: () => _showSingleSelectDialog(
            title: 'Select Year',
            options: years,
            selected: _selectedYear,
            onChanged: (val) => setState(() => _selectedYear = val),
          ),
          isMobile: isMobile,
        ),

        if (widget.mode == AppMode.anime)
          _buildFilterButton(
            label: 'Season',
            valueText: _selectedSeason,
            onTap: () => _showSingleSelectDialog(
              title: 'Select Season',
              options: seasons,
              selected: _selectedSeason,
              onChanged: (val) => setState(() => _selectedSeason = val),
            ),
            isMobile: isMobile,
          ),
      ],
    );

    return isMobile 
        ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: rowContent) 
        : rowContent;
  }

  Widget _buildRow2(bool isMobile, List<String> statuses, List<String> sortOptions) {
    final rowContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFilterButton(
          label: 'Format',
          valueText: _selectedFormats.isEmpty 
              ? 'ALL' 
              : (_selectedFormats.length == 1 ? _selectedFormats.first : '${_selectedFormats.length} selected'),
          onTap: _showMultiSelectFormats,
          isMobile: isMobile,
        ),

        if (widget.mode != AppMode.movies)
          _buildFilterButton(
            label: 'Status',
            valueText: _selectedStatus,
            onTap: () => _showSingleSelectDialog(
              title: 'Select Status',
              options: statuses,
              selected: _selectedStatus,
              onChanged: (val) => setState(() => _selectedStatus = val),
            ),
            isMobile: isMobile,
          ),

        _buildFilterButton(
          label: 'Sorting',
          valueText: _availableSortings[_selectedSorting] ?? 'Popularity',
          onTap: () => _showSingleSelectDialog(
            title: 'Select Sorting',
            options: sortOptions.map((key) => _availableSortings[key]!).toList(),
            selected: _availableSortings[_selectedSorting]!,
            onChanged: (displayVal) {
              final key = _availableSortings.entries
                  .firstWhere((entry) => entry.value == displayVal)
                  .key;
              setState(() => _selectedSorting = key);
            },
          ),
          isMobile: isMobile,
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
            ),
            onPressed: _clearFilters,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Reset', style: TextStyle(fontSize: 12.0, fontFamily: 'Outfit')),
          ),
        ),
      ],
    );

    return isMobile 
        ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: rowContent) 
        : rowContent;
  }

  Widget _buildMobileFilters(List<String> years, List<String> seasons, List<String> statuses, List<String> sortOptions) {
    final List<Widget> mobileFilters = [
      _buildFilterButton(
        label: 'Genre',
        valueText: _selectedGenres.isEmpty 
            ? 'ALL' 
            : (_selectedGenres.length == 1 ? _selectedGenres.first : '${_selectedGenres.length} selected'),
        onTap: _showMultiSelectGenres,
        isMobile: true,
        expand: true,
      ),
      _buildFilterButton(
        label: 'Year',
        valueText: _selectedYear,
        onTap: () => _showSingleSelectDialog(
          title: 'Select Year',
          options: years,
          selected: _selectedYear,
          onChanged: (val) => setState(() => _selectedYear = val),
        ),
        isMobile: true,
        expand: true,
      ),
      if (widget.mode == AppMode.anime)
        _buildFilterButton(
          label: 'Season',
          valueText: _selectedSeason,
          onTap: () => _showSingleSelectDialog(
            title: 'Select Season',
            options: seasons,
            selected: _selectedSeason,
            onChanged: (val) => setState(() => _selectedSeason = val),
          ),
          isMobile: true,
          expand: true,
        ),
      _buildFilterButton(
        label: 'Format',
        valueText: _selectedFormats.isEmpty 
            ? 'ALL' 
            : (_selectedFormats.length == 1 ? _selectedFormats.first : '${_selectedFormats.length} selected'),
        onTap: _showMultiSelectFormats,
        isMobile: true,
        expand: true,
      ),
      if (widget.mode != AppMode.movies)
        _buildFilterButton(
          label: 'Status',
          valueText: _selectedStatus,
          onTap: () => _showSingleSelectDialog(
            title: 'Select Status',
            options: statuses,
            selected: _selectedStatus,
            onChanged: (val) => setState(() => _selectedStatus = val),
          ),
          isMobile: true,
          expand: true,
        ),
      _buildFilterButton(
        label: 'Sorting',
        valueText: _availableSortings[_selectedSorting] ?? 'Popularity',
        onTap: () => _showSingleSelectDialog(
          title: 'Select Sorting',
          options: sortOptions.map((key) => _availableSortings[key]!).toList(),
          selected: _availableSortings[_selectedSorting]!,
          onChanged: (displayVal) {
            final key = _availableSortings.entries
                .firstWhere((entry) => entry.value == displayVal)
                .key;
            setState(() => _selectedSorting = key);
          },
        ),
        isMobile: true,
        expand: true,
      ),
    ];

    final Widget resetButton = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        minimumSize: const Size(double.infinity, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      ),
      onPressed: _clearFilters,
      icon: const Icon(Icons.refresh, size: 14),
      label: const Text('Reset', style: TextStyle(fontSize: 12.0, fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
    );

    List<Widget> filterRows = [];
    for (int i = 0; i < mobileFilters.length; i += 2) {
      if (i + 1 < mobileFilters.length) {
        filterRows.add(
          Row(
            children: [
              mobileFilters[i],
              const SizedBox(width: 8.0),
              mobileFilters[i + 1],
            ],
          ),
        );
      } else {
        filterRows.add(
          Row(
            children: [
              mobileFilters[i],
              const SizedBox(width: 8.0),
              Expanded(child: resetButton),
            ],
          ),
        );
      }
      filterRows.add(const SizedBox(height: 8.0));
    }

    if (mobileFilters.length % 2 == 0) {
      filterRows.add(
        Row(
          children: [
            Expanded(child: resetButton),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 38.0,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                  decoration: InputDecoration(
                    hintText: widget.mode == AppMode.manga
                        ? 'Search manga...'
                        : (widget.mode == AppMode.movies ? 'Search movies & series...' : 'Search anime...'),
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 13.0),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 16),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                  ),
                  onSubmitted: (_) => _performSearch(),
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                minimumSize: const Size(0, 38),
              ),
              onPressed: () => _performSearch(),
              child: const Icon(Icons.send, size: 14),
            ),
            const SizedBox(width: 8.0),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                borderRadius: BorderRadius.circular(8.0),
                child: Container(
                  height: 38.0,
                  width: 38.0,
                  decoration: BoxDecoration(
                    color: _hasActiveFilters 
                        ? Colors.white.withValues(alpha: 0.12) 
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: _hasActiveFilters ? Colors.white30 : Colors.white10,
                    ),
                  ),
                  child: Icon(
                    Icons.tune,
                    color: _hasActiveFilters ? Colors.white : Colors.white70,
                    size: 16.0,
                  ),
                ),
              ),
            ),
          ],
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: filterRows,
            ),
          ),
          crossFadeState: _showMobileFilters ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  void _showMultiSelectGenres() {
    final List<String> tempSelected = List.from(_selectedGenres);
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F0F11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
              title: const Text(
                'Select Genres',
                style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 16.0, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 340,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: _availableGenres.map((genre) {
                      final isSelected = tempSelected.contains(genre);
                      return FilterChip(
                        label: Text(genre),
                        selected: isSelected,
                        selectedColor: Colors.white,
                        checkmarkColor: Colors.black,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : Colors.white70,
                          fontSize: 12.0,
                          fontFamily: 'Outfit',
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                        side: const BorderSide(color: Colors.white10),
                        onSelected: (selected) {
                          setDialogState(() {
                            if (selected) {
                              tempSelected.add(genre);
                            } else {
                              tempSelected.remove(genre);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white38, fontFamily: 'Outfit')),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedGenres = tempSelected;
                    });
                    Navigator.pop(context);
                    _performSearch();
                  },
                  child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMultiSelectFormats() {
    final List<String> tempSelected = List.from(_selectedFormats);
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F0F11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
              title: const Text(
                'Select Formats',
                style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 16.0, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _availableFormats.map((format) {
                    final isSelected = tempSelected.contains(format);
                    return CheckboxListTile(
                      title: Text(format, style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
                      value: isSelected,
                      activeColor: Colors.white,
                      checkColor: Colors.black,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            tempSelected.add(format);
                          } else {
                            tempSelected.remove(format);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white38, fontFamily: 'Outfit')),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedFormats = tempSelected;
                    });
                    Navigator.pop(context);
                    _performSearch();
                  },
                  child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSingleSelectDialog({
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F0F11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 16.0, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 250,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                final isSelected = option == selected;
                return ListTile(
                  title: Text(
                    option,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white54,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13.0,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  trailing: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                  dense: true,
                  onTap: () {
                    onChanged(option);
                    Navigator.pop(context);
                    _performSearch();
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  // UI rendering
  @override
  Widget build(BuildContext context) {
    final years = ['ALL', ...List.generate(37, (index) => (2026 - index).toString())];
    final seasons = ['ALL', 'WINTER', 'SPRING', 'SUMMER', 'FALL'];
    final statuses = ['ALL', ..._availableStatuses];
    final sortOptions = _availableSortings.keys.toList();

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Custom top bar spacing to clear floating titlebar
            SizedBox(height: isMobile ? 0.0 : 50.0),

            // Top Section: Inputs and Double Row Filters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: isMobile
                  ? _buildMobileFilters(years, seasons, statuses, sortOptions)
                  : Column(
                      children: [
                        _buildRow1(isMobile, years, seasons),
                        const SizedBox(height: 8.0),
                        _buildRow2(isMobile, statuses, sortOptions),
                      ],
                    ),
            ),

            const Divider(color: Colors.white10, height: 1.0),

            // Bottom Section: Search Results Grid
            Expanded(
              child: _isLoading && _results.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.redAccent, size: 40.0),
                                const SizedBox(height: 12.0),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70, fontSize: 13.0, fontFamily: 'Outfit'),
                                ),
                                const SizedBox(height: 16.0),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                                  ),
                                  onPressed: () => _performSearch(),
                                  child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _results.isEmpty
                           ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off_outlined, color: Colors.white24, size: 44.0),
                                  SizedBox(height: 12.0),
                                  Text(
                                    'No results found.',
                                    style: TextStyle(color: Colors.white38, fontSize: 14.0, fontFamily: 'Outfit'),
                                  ),
                                  SizedBox(height: 4.0),
                                  Text(
                                    'Try expanding your filters or query text.',
                                    style: TextStyle(color: Colors.white24, fontSize: 11.5, fontFamily: 'Outfit'),
                                  ),
                                ],
                              ),
                            )
                          : NotificationListener<ScrollNotification>(
                              onNotification: (scrollInfo) {
                                if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                                  _loadMore();
                                }
                                return false;
                              },
                              child: GridView.builder(
                                padding: const EdgeInsets.all(16.0),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 150.0,
                                  mainAxisExtent: 240.0,
                                  crossAxisSpacing: 14.0,
                                  mainAxisSpacing: 14.0,
                                ),
                                itemCount: _results.length + (_hasNextPage ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _results.length) {
                                    return const Center(
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                                    );
                                  }
                                  final media = _results[index];
                                  return _SearchMediaCard(
                                    media: media,
                                    onTap: () {
                                      widget.navigationState.selectAnime(media['id']);
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

class _SearchMediaCard extends StatefulWidget {
  final dynamic media;
  final VoidCallback onTap;

  const _SearchMediaCard({
    required this.media,
    required this.onTap,
  });

  @override
  State<_SearchMediaCard> createState() => _SearchMediaCardState();
}

class _SearchMediaCardState extends State<_SearchMediaCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final coverUrl = widget.media['coverImage']?['large'] ?? '';
    final title = widget.media['title']?['english'] ?? widget.media['title']?['romaji'] ?? 'Untitled';
    final double? rating = widget.media['averageScore'] != null
        ? (widget.media['averageScore'] as num).toDouble()
        : null;
    final String? format = widget.media['format'];
    final int? episodes = widget.media['episodes'];

    String infoString = '';
    if (format != null) infoString += format;
    if (episodes != null) infoString += ' · $episodes eps';

    return MouseRegion(
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
                duration: const Duration(milliseconds: 150),
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
                      // Cover image
                      Positioned.fill(
                        child: coverUrl.isNotEmpty
                            ? Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheWidth: 300,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(color: Colors.grey[950]),
                              )
                            : Container(color: Colors.grey[950]),
                      ),
                      
                      // Score Badge (Top-Right)
                      if (rating != null)
                        Positioned(
                          top: 8.0,
                          right: 8.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4.0),
                              border: Border.all(color: Colors.white10),
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

                      // Format Indicator (Bottom-Left)
                      if (format != null)
                        Positioned(
                          bottom: 8.0,
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
                                fontSize: 8.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6.0),
            
            // Media Title
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _isHovered ? Colors.white : Colors.white70,
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
                fontFamily: 'Outfit',
              ),
            ),
            
            // Subtitle Info
            if (infoString.isNotEmpty) ...[
              const SizedBox(height: 1.0),
              Text(
                infoString,
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 10.5,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
