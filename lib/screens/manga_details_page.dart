import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/suwayomi_service.dart';
import '../state/navigation_state.dart';
import '../state/library_state.dart';

class MangaDetailsPage extends StatefulWidget {
  final String mangaId;
  final NavigationState navigationState;

  const MangaDetailsPage({
    super.key,
    required this.mangaId,
    required this.navigationState,
  });

  @override
  State<MangaDetailsPage> createState() => _MangaDetailsPageState();
}

class _MangaDetailsPageState extends State<MangaDetailsPage> {
  final SuwayomiService _suwayomiService = SuwayomiService();
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _details;
  List<dynamic> _chapters = [];
  bool _isChaptersReversed = false;
  String _chapterSearchQuery = '';
  String _chapterFilter = 'ALL'; // 'ALL', 'UNREAD', 'READ'

  int get _parsedMangaId => int.tryParse(widget.mangaId) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadMangaDetails();
  }

  Future<void> _loadMangaDetails() async {
    if (_parsedMangaId == 0) {
      if (mounted) {
        setState(() {
          _errorMessage = "Invalid Manga ID";
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final info = await _suwayomiService.getMangaDetails(_parsedMangaId);
      final chaps = await _suwayomiService.getChapters(_parsedMangaId);
      
      if (mounted) {
        setState(() {
          _details = info;
          _chapters = chaps;
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

  void _showLibraryEditPanel() {
    if (_details == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        final savedItem = LibraryState().getItem(_parsedMangaId, 'manga');
        return _MangaLibraryEditPanel(
          mangaId: _parsedMangaId,
          title: _details!['title'] ?? 'Manga Details',
          totalChapters: _chapters.length,
          savedItem: savedItem,
          onSaved: () => setState(() {}),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
          ),
        ),
      );
    }

    if (_errorMessage != null || _details == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          toolbarHeight: isDesktop ? 88.0 : 56.0,
          leading: Padding(
            padding: EdgeInsets.only(top: isDesktop ? 32.0 : 0.0),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18.0),
              onPressed: () => widget.navigationState.selectManga(null),
            ),
          ),
        ),
        body: Center(
          child: Text(
            _errorMessage ?? "Error loading manga details",
            style: const TextStyle(color: Colors.white60, fontFamily: 'Outfit'),
          ),
        ),
      );
    }

    final title = _details!['title'] ?? 'Unknown Manga';
    final coverUrl = _details!['thumbnailUrl']?.toString() ?? '';
    final description = _details!['description'] ?? 'No description available.';

    // Safe Author parser
    String authorStr = 'Unknown Author';
    final rawAuthor = _details!['author'];
    if (rawAuthor is List) {
      authorStr = rawAuthor.join(', ');
    } else if (rawAuthor != null && rawAuthor.toString().trim().isNotEmpty) {
      authorStr = rawAuthor.toString().trim();
    }

    // Safe Status parser (Tachiyomi status is an enum integer)
    String statusStr = 'Unknown';
    final rawStatus = _details!['status'];
    if (rawStatus is int) {
      switch (rawStatus) {
        case 1: statusStr = 'Ongoing'; break;
        case 2: statusStr = 'Completed'; break;
        case 3: statusStr = 'Licensed'; break;
        case 4: statusStr = 'Finished'; break;
        case 5: statusStr = 'Cancelled'; break;
        case 6: statusStr = 'On Hiatus'; break;
        default: statusStr = 'Unknown';
      }
    } else if (rawStatus != null) {
      statusStr = rawStatus.toString();
    }

    // Safe Genres parser
    final rawGenre = _details!['genre'];
    final List<String> genres = [];
    if (rawGenre is List) {
      genres.addAll(rawGenre.map((g) => g.toString()));
    } else if (rawGenre is String) {
      genres.addAll(rawGenre.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty));
    }

    final libraryState = LibraryState();
    final libraryItem = libraryState.getItem(_parsedMangaId, 'manga');
    final bool inLibrary = libraryItem != null;

    Widget _buildChapterFilterChip(String value, String label) {
      final bool isSelected = _chapterFilter == value;
      return ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontSize: 11.0,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'Outfit',
          ),
        ),
        selected: isSelected,
        selectedColor: Colors.white,
        backgroundColor: Colors.transparent,
        checkmarkColor: Colors.black,
        side: BorderSide(
          color: isSelected ? Colors.white : Colors.white24,
        ),
        onSelected: (selected) {
          if (selected) {
            setState(() => _chapterFilter = value);
          }
        },
      );
    }

    var displayChapters = _isChaptersReversed ? _chapters.reversed.toList() : _chapters;
    
    if (_chapterSearchQuery.trim().isNotEmpty) {
      final q = _chapterSearchQuery.trim().toLowerCase();
      displayChapters = displayChapters.where((ch) {
        final name = (ch['name'] ?? '').toString().toLowerCase();
        final chNum = (ch['chapterNumber'] ?? '').toString().toLowerCase();
        return name.contains(q) || chNum.contains(q);
      }).toList();
    }

    if (_chapterFilter != 'ALL') {
      displayChapters = displayChapters.where((ch) {
        final double? chNum = double.tryParse(ch['chapterNumber']?.toString() ?? '');
        final int currentChapterIdx = (chNum?.toInt() ?? 1);
        final bool read = ch['read'] ?? false;
        final bool locallyRead = inLibrary && libraryItem.watchedEpisodes >= currentChapterIdx;
        final bool isRead = read || locallyRead;
        return _chapterFilter == 'READ' ? isRead : !isRead;
      }).toList();
    }



    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Faded blurred banner background (fixed behind scroll)
          if (coverUrl.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 380.0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 600,
                    placeholder: (context, url) => Container(color: Colors.black),
                    errorWidget: (context, url, error) => Container(color: Colors.black),
                  ),
                  ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Banner gradient fade to black
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 382.0,
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
                  stops: [0.0, 0.2, 0.6, 1.0],
                ),
              ),
            ),
          ),

          // 2. Main scrollable content — CustomScrollView for lazy chapter loading
          Positioned.fill(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Header content (back button, banner area, details, filters)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: isDesktop ? 40.0 : 40.0, bottom: 0.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back button row with title and bookmark
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18.0),
                                onPressed: () => widget.navigationState.selectManga(null),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                                  padding: const EdgeInsets.all(10.0),
                                ),
                              ),
                              const SizedBox(width: 16.0),
                              Expanded(
                                child: Text(
                                  title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16.0),
                              IconButton(
                                icon: Icon(
                                  inLibrary ? Icons.bookmark : Icons.bookmark_border,
                                  color: inLibrary ? Colors.amber : Colors.white,
                                  size: 18.0,
                                ),
                                onPressed: _showLibraryEditPanel,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                                  padding: const EdgeInsets.all(10.0),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Spacer to expose the banner
                        const SizedBox(height: 140.0),

                        // Cover art + quick details row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Cover art card
                              Hero(
                                tag: 'manga_cover_${widget.mangaId}',
                                child: Container(
                                  width: 100.0,
                                  height: 145.0,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8.0),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        blurRadius: 10.0,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.0),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(7.0),
                                    child: CachedNetworkImage(
                                      imageUrl: coverUrl,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 250,
                                      placeholder: (context, url) => Container(color: Colors.white12),
                                      errorWidget: (context, url, error) => Container(
                                        color: Colors.white12,
                                        child: const Icon(Icons.book, color: Colors.white24, size: 36.0),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16.0),
                              // Quick details
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Outfit',
                                        fontSize: 18.0,
                                        fontWeight: FontWeight.bold,
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 6.0),
                                    Text(
                                      'By $authorStr',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontFamily: 'Outfit',
                                        fontSize: 12.0,
                                      ),
                                    ),
                                    const SizedBox(height: 8.0),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF9F1C).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4.0),
                                            border: Border.all(color: const Color(0xFFFF9F1C).withValues(alpha: 0.3), width: 0.5),
                                          ),
                                          child: Text(
                                            statusStr,
                                            style: const TextStyle(
                                              color: Color(0xFFFF9F1C),
                                              fontSize: 9.0,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Outfit',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8.0),
                                        Text(
                                          '${_chapters.length} Chapters',
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontFamily: 'Outfit',
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24.0),

                        // Genres tags
                        if (genres.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8.0,
                                  runSpacing: 8.0,
                                  children: genres.map((genre) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(4.0),
                                      ),
                                      child: Text(
                                        genre,
                                        style: const TextStyle(color: Colors.white70, fontSize: 11.0, fontFamily: 'Outfit'),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 16.0),
                              ],
                            ),
                          ),

                        // Description
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Text(
                            description,
                            style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5, fontFamily: 'Outfit'),
                          ),
                        ),

                        const SizedBox(height: 24.0),

                        // Chapter search bar
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Container(
                            height: 38.0,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: TextField(
                              style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                              decoration: const InputDecoration(
                                hintText: 'Search chapters by name or number...',
                                hintStyle: TextStyle(color: Colors.white24, fontSize: 12.0),
                                prefixIcon: Icon(Icons.search, color: Colors.white38, size: 16),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 8.0),
                              ),
                              onChanged: (val) => setState(() => _chapterSearchQuery = val),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12.0),

                        // Choice chip filters
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                _buildChapterFilterChip('ALL', 'All Chapters'),
                                const SizedBox(width: 8.0),
                                _buildChapterFilterChip('UNREAD', 'Unread'),
                                const SizedBox(width: 8.0),
                                _buildChapterFilterChip('READ', 'Read'),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20.0),

                        // Chapters Section Header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Chapters (${displayChapters.length})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16.0,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _isChaptersReversed ? Icons.arrow_upward : Icons.arrow_downward,
                                  color: Colors.white54,
                                  size: 18.0,
                                ),
                                onPressed: () {
                                  setState(() => _isChaptersReversed = !_isChaptersReversed);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12.0),
                      ],
                    ),
                  ),
                ),

                // Lazy-loaded chapter list (only visible items are built)
                SliverList.builder(
                  itemCount: displayChapters.length,
                  itemBuilder: (context, index) {
                    final chapter = displayChapters[index];
                    final String chName = chapter['name'] ?? 'Chapter';
                    final String chId = chapter['id']?.toString() ?? '';
                    final double? chNum = double.tryParse(chapter['chapterNumber']?.toString() ?? '');
                    final bool read = chapter['read'] ?? false;

                    final int currentChapterIdx = (chNum?.toInt() ?? 1);
                    final bool locallyRead = inLibrary && libraryItem.watchedEpisodes >= currentChapterIdx;
                    final bool isRead = read || locallyRead;

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F11),
                        borderRadius: BorderRadius.circular(6.0),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                        title: Text(
                          chName,
                          style: TextStyle(
                            color: isRead ? Colors.white38 : Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        trailing: Icon(
                          isRead ? Icons.check_circle : Icons.play_circle_outline,
                          color: isRead ? const Color(0xFFFF9F1C).withValues(alpha: 0.5) : Colors.white54,
                        ),
                        onTap: () {
                          if (chId.isNotEmpty) {
                            widget.navigationState.startReading(
                              chapterId: chId,
                              chapterNumber: currentChapterIdx,
                              mangaId: widget.mangaId,
                              mangaTitle: title,
                              chapters: _chapters,
                            );
                          }
                        },
                      ),
                    );
                  },
                ),

                // Safety bottom padding
                const SliverToBoxAdapter(
                  child: SizedBox(height: 64.0),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MangaLibraryEditPanel extends StatefulWidget {
  final int mangaId;
  final String title;
  final int totalChapters;
  final LibraryItem? savedItem;
  final VoidCallback onSaved;

  const _MangaLibraryEditPanel({
    required this.mangaId,
    required this.title,
    required this.totalChapters,
    required this.savedItem,
    required this.onSaved,
  });

  @override
  State<_MangaLibraryEditPanel> createState() => _MangaLibraryEditPanelState();
}

class _MangaLibraryEditPanelState extends State<_MangaLibraryEditPanel> {
  late String _activeStatus;
  late double _activeRating;
  late int _chaptersRead;
  late List<String> _selectedCategoryIds;

  late final TextEditingController _chaptersController;
  late final TextEditingController _scoreController;
  
  bool _isCreatingCategory = false;
  late final TextEditingController _newCategoryController;

  @override
  void initState() {
    super.initState();
    _activeStatus = widget.savedItem?.libraryStatus ?? 'watching';
    _activeRating = widget.savedItem?.rating ?? 0.0;
    _chaptersRead = widget.savedItem?.watchedEpisodes ?? 0;
    _selectedCategoryIds = List<String>.from(widget.savedItem?.categoryIds ?? <String>[]);

    _chaptersController = TextEditingController(text: '$_chaptersRead');
    _scoreController = TextEditingController(
      text: _activeRating == 0.0 ? '' : _activeRating.toStringAsFixed(1),
    );
    _newCategoryController = TextEditingController();
  }

  @override
  void dispose() {
    _chaptersController.dispose();
    _scoreController.dispose();
    _newCategoryController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateCategory() async {
    final String name = _newCategoryController.text.trim();
    if (name.isNotEmpty) {
      await LibraryState().createCategory(name, 'manga');
      setState(() {
        _isCreatingCategory = false;
        _newCategoryController.clear();
      });
    }
  }

  void _updateChaptersRead(int val) {
    final int clamped = val.clamp(0, widget.totalChapters > 0 ? widget.totalChapters : 99999);
    setState(() {
      _chaptersRead = clamped;
      _chaptersController.text = '$clamped';
    });
  }

  void _updateRating(double val) {
    final double clamped = val.clamp(0.0, 10.0);
    setState(() {
      _activeRating = clamped;
      _scoreController.text = clamped == 0.0 ? '' : clamped.toStringAsFixed(1);
    });
  }



  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobileSheet = screenWidth < 650;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: isMobileSheet ? double.infinity : 550.0,
        margin: isMobileSheet
            ? EdgeInsets.zero
            : const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F11),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
          border: Border.all(color: Colors.white10, width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Colors.black87,
              blurRadius: 30,
              spreadRadius: 2,
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(15.0)),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: isMobileSheet ? 12.0 : 16.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.01),
                      border: const Border(bottom: BorderSide(color: Colors.white10, width: 1.0)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                  'Manga Library Settings',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15.0,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              const SizedBox(height: 2.0),
                              Text(
                                widget.title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white38, fontSize: 11.0, fontFamily: 'Outfit'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54, size: 22),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // Body
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [


                        // Chapters Read Progress
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Chapters Read',
                                        style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                                      ),
                                      const SizedBox(width: 8.0),
                                      SizedBox(
                                        width: 50.0,
                                        height: 20.0,
                                        child: TextField(
                                          controller: _chaptersController,
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            border: InputBorder.none,
                                          ),
                                          onChanged: (val) {
                                            final int? parsed = int.tryParse(val);
                                            if (parsed != null) {
                                              final int clamped = parsed.clamp(0, widget.totalChapters > 0 ? widget.totalChapters : 99999);
                                              setState(() {
                                                _chaptersRead = clamped;
                                              });
                                            }
                                          },
                                          onSubmitted: (val) {
                                            final int? parsed = int.tryParse(val);
                                            _updateChaptersRead(parsed ?? _chaptersRead);
                                          },
                                        ),
                                      ),
                                      if (widget.totalChapters > 0)
                                        Text(
                                          ' / ${widget.totalChapters}',
                                          style: const TextStyle(color: Colors.white38, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                        ),
                                    ],
                                  ),
                                  if (widget.totalChapters > 0)
                                    Text(
                                      '${((widget.totalChapters > 0 ? _chaptersRead / widget.totalChapters : 0.0) * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16.0),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white10,
                                  thumbColor: Colors.white,
                                  overlayColor: Colors.white.withValues(alpha: 0.1),
                                  valueIndicatorColor: Colors.white,
                                  valueIndicatorTextStyle: const TextStyle(color: Colors.black, fontFamily: 'Outfit'),
                                ),
                                child: Slider(
                                  value: _chaptersRead.toDouble(),
                                  min: 0.0,
                                  max: (widget.totalChapters > 0 ? widget.totalChapters : max(100, _chaptersRead + 50)).toDouble(),
                                  divisions: widget.totalChapters > 0 ? widget.totalChapters : (100 + _chaptersRead),
                                  label: '$_chaptersRead',
                                  onChanged: (val) {
                                    _updateChaptersRead(val.toInt());
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20.0),

                        // Score Rating
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Your Score',
                                    style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 16.0),
                                      const SizedBox(width: 4.0),
                                      SizedBox(
                                        width: 50.0,
                                        height: 20.0,
                                        child: TextField(
                                          controller: _scoreController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(color: Colors.amber, fontSize: 14.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            border: InputBorder.none,
                                            hintText: '0.0',
                                            hintStyle: TextStyle(color: Colors.white38),
                                          ),
                                          onChanged: (val) {
                                            final double? parsed = double.tryParse(val);
                                            if (parsed != null) {
                                              final double clamped = parsed.clamp(0.0, 10.0);
                                              setState(() {
                                                _activeRating = clamped;
                                              });
                                            }
                                          },
                                          onSubmitted: (val) {
                                            final double? parsed = double.tryParse(val);
                                            _updateRating(parsed ?? _activeRating);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16.0),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white10,
                                  thumbColor: Colors.white,
                                  overlayColor: Colors.white.withValues(alpha: 0.1),
                                  valueIndicatorColor: Colors.white,
                                  valueIndicatorTextStyle: const TextStyle(color: Colors.black, fontFamily: 'Outfit'),
                                ),
                                child: Slider(
                                  value: _activeRating,
                                  min: 0.0,
                                  max: 10.0,
                                  divisions: 100,
                                  label: _activeRating == 0.0 ? 'No Rating' : _activeRating.toStringAsFixed(1),
                                  onChanged: _updateRating,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Custom Categories chips selection
                        ListenableBuilder(
                          listenable: LibraryState(),
                          builder: (context, _) {
                            final cats = LibraryState().categories.where((cat) => cat.mode == 'manga').toList();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 20.0),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Categories',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13.0,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Outfit',
                                      ),
                                    ),
                                    if (!_isCreatingCategory)
                                      IconButton(
                                        icon: const Icon(Icons.add, color: Colors.white54, size: 18.0),
                                        onPressed: () {
                                          setState(() {
                                            _isCreatingCategory = true;
                                          });
                                        },
                                        tooltip: 'Create Category',
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8.0),
                                if (_isCreatingCategory) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 36.0,
                                          child: TextField(
                                            controller: _newCategoryController,
                                            style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
                                            decoration: InputDecoration(
                                              hintText: 'Category name...',
                                              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12.0),
                                              filled: true,
                                              fillColor: Colors.white.withValues(alpha: 0.03),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(color: Colors.white10),
                                                borderRadius: BorderRadius.circular(6.0),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(color: Colors.white24),
                                                borderRadius: BorderRadius.circular(6.0),
                                              ),
                                            ),
                                            onSubmitted: (_) => _handleCreateCategory(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8.0),
                                      IconButton(
                                        icon: const Icon(Icons.check, color: Colors.greenAccent, size: 18.0),
                                        onPressed: _handleCreateCategory,
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                      ),
                                      const SizedBox(width: 8.0),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.redAccent, size: 18.0),
                                        onPressed: () {
                                          setState(() {
                                            _isCreatingCategory = false;
                                            _newCategoryController.clear();
                                          });
                                        },
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12.0),
                                ],
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12.0),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(8.0),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: cats.isEmpty
                                      ? const Text(
                                          'No categories. Click + to create one.',
                                          style: TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
                                        )
                                      : Wrap(
                                          spacing: 8.0,
                                          runSpacing: 8.0,
                                          children: cats.map((cat) {
                                            final bool isChecked = _selectedCategoryIds.contains(cat.id);
                                            return FilterChip(
                                              label: Text(
                                                cat.name,
                                                style: TextStyle(
                                                  color: isChecked ? Colors.black : Colors.white70,
                                                  fontSize: 11.5,
                                                  fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                                                  fontFamily: 'Outfit',
                                                ),
                                              ),
                                              selected: isChecked,
                                              selectedColor: Colors.white,
                                              checkmarkColor: Colors.black,
                                              backgroundColor: Colors.transparent,
                                              side: BorderSide(
                                                color: isChecked ? Colors.white : Colors.white24,
                                              ),
                                              onSelected: (bool selected) {
                                                setState(() {
                                                  if (selected) {
                                                    _selectedCategoryIds.add(cat.id);
                                                  } else {
                                                    _selectedCategoryIds.remove(cat.id);
                                                  }
                                                });
                                              },
                                            );
                                          }).toList(),
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // Footer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0C0C0E),
                      border: Border(top: BorderSide(color: Colors.white10, width: 1.0)),
                    ),
                    child: Row(
                      children: [
                        if (widget.savedItem != null)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18.0),
                            label: const Text('Remove', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                            onPressed: () async {
                              await LibraryState().removeItem(widget.mangaId, 'manga');
                              widget.onSaved();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                              elevation: 0,
                              side: const BorderSide(color: Colors.redAccent, width: 1.0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            ),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white38, fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 12.0),
                        ElevatedButton(
                          onPressed: () async {
                            final int finalChaptersRead = int.tryParse(_chaptersController.text)?.clamp(0, widget.totalChapters > 0 ? widget.totalChapters : 99999) ?? _chaptersRead;
                            final double finalRating = double.tryParse(_scoreController.text)?.clamp(0.0, 10.0) ?? _activeRating;

                            await LibraryState().saveItem(
                              id: widget.mangaId,
                              mode: 'manga',
                              format: 'MANGA',
                              libraryStatus: _activeStatus,
                              rating: finalRating,
                              watchedEpisodes: finalChaptersRead,
                              totalEpisodes: widget.totalChapters > 0 ? widget.totalChapters : null,
                              categoryIds: _selectedCategoryIds,
                            );
                            widget.onSaved();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                          ),
                          child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
