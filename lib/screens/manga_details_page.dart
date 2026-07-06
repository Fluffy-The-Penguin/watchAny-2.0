import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/suwayomi_service.dart';
import '../state/navigation_state.dart';
import '../state/library_state.dart';
import 'manga_reader_page.dart';

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
      
      if (info != null && LibraryState().isSaved(_parsedMangaId, 'manga')) {
        await LibraryState().updateMangaCache(_parsedMangaId, info);
      }
      
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
          chapters: _chapters,
          totalChapters: _chapters.length,
          savedItem: savedItem,
          mangaDetails: _details!,
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





    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000.0),
          child: Stack(
            children: [
              // 1. Background Banner Backdrop Image
              if (coverUrl.isNotEmpty)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 250.0,
                  child: Stack(
                    children: [
                      CachedNetworkImage(
                        imageUrl: coverUrl,
                        width: double.infinity,
                        height: 250.0,
                        fit: BoxFit.cover,
                        memCacheWidth: 400,
                        placeholder: (context, url) => const SizedBox(),
                        errorWidget: (context, url, error) => const SizedBox(),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.25),
                              Colors.black.withValues(alpha: 0.8),
                              Colors.black,
                            ],
                          ),
                        ),
                      ),
                    ],
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

                        const SizedBox(height: 24.0),

                        _MangaChaptersSection(
                          chapters: _chapters,
                          mangaId: _parsedMangaId,
                          title: title,
                          inLibrary: inLibrary,
                          libraryItem: libraryItem,
                          navigationState: widget.navigationState,
                          onSetChapterReadStatus: (chapterId, read) async {
                            await libraryState.setChapterReadStatus(_parsedMangaId, chapterId, read);
                            setState(() {});
                          },
                          onUpdated: () {
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
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
    ),
  ),
);
  }
}

class _MangaLibraryEditPanel extends StatefulWidget {
  final int mangaId;
  final String title;
  final List<dynamic> chapters;
  final int totalChapters;
  final LibraryItem? savedItem;
  final Map<String, dynamic> mangaDetails;
  final VoidCallback onSaved;

  const _MangaLibraryEditPanel({
    required this.mangaId,
    required this.title,
    required this.chapters,
    required this.totalChapters,
    required this.savedItem,
    required this.mangaDetails,
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

  bool _isCreatingCategory = false;
  late final TextEditingController _newCategoryController;

  @override
  void initState() {
    super.initState();
    _activeStatus = widget.savedItem?.libraryStatus ?? 'watching';
    _activeRating = widget.savedItem?.rating ?? 0.0;
    _chaptersRead = widget.savedItem?.watchedEpisodes ?? 0;
    _selectedCategoryIds = List<String>.from(widget.savedItem?.categoryIds ?? <String>[]);
    _newCategoryController = TextEditingController();
  }

  @override
  void dispose() {
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
                      children: [
                        ListenableBuilder(
                          listenable: LibraryState(),
                          builder: (context, _) {
                            final cats = LibraryState().categories.where((cat) => cat.mode == 'manga').toList();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                            await LibraryState().updateMangaCache(widget.mangaId, widget.mangaDetails);
                            await LibraryState().saveItem(
                              id: widget.mangaId,
                              mode: 'manga',
                              format: 'MANGA',
                              libraryStatus: _activeStatus,
                              rating: _activeRating,
                              watchedEpisodes: _chaptersRead,
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

class _MangaChaptersSection extends StatefulWidget {
  final List<dynamic> chapters;
  final int mangaId;
  final String title;
  final bool inLibrary;
  final LibraryItem? libraryItem;
  final NavigationState navigationState;
  final Function(String, bool) onSetChapterReadStatus;
  final VoidCallback onUpdated;

  const _MangaChaptersSection({
    required this.chapters,
    required this.mangaId,
    required this.title,
    required this.inLibrary,
    required this.libraryItem,
    required this.navigationState,
    required this.onSetChapterReadStatus,
    required this.onUpdated,
  });

  @override
  State<_MangaChaptersSection> createState() => _MangaChaptersSectionState();
}

class _MangaChaptersSectionState extends State<_MangaChaptersSection> {
  String _chapterSearchQuery = '';
  String _chapterFilter = 'ALL'; // 'ALL', 'UNREAD', 'READ'
  bool _isChaptersReversed = false;

  int _currentPage = 1;
  static const int _chaptersPerPage = 20;
  String _lastQuery = '';
  String _lastFilter = 'ALL';

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

  @override
  Widget build(BuildContext context) {
    final libraryState = LibraryState();
    final List<String> readChapterIds = libraryState.getReadChapterIds(widget.mangaId);

    // Auto-migration check: If they have sequential progress but empty read chapter list
    if (widget.inLibrary && widget.libraryItem != null && widget.libraryItem!.watchedEpisodes > 0 && readChapterIds.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final list = widget.chapters.reversed.toList();
        final int episodes = widget.libraryItem!.watchedEpisodes;
        final chaptersToMark = list.take(episodes > list.length ? list.length : episodes);
        for (var ch in chaptersToMark) {
          final id = ch['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            await libraryState.setChapterReadStatus(widget.mangaId, id, true);
          }
        }
        if (mounted) {
          setState(() {}); // trigger rebuild after migration
        }
      });
    }

    var displayChapters = _isChaptersReversed ? widget.chapters.reversed.toList() : widget.chapters;

    // Filter by search query
    if (_chapterSearchQuery.trim().isNotEmpty) {
      final q = _chapterSearchQuery.trim().toLowerCase();
      displayChapters = displayChapters.where((ch) {
        final name = (ch['name'] ?? '').toString().toLowerCase();
        final chNum = (ch['chapterNumber'] ?? '').toString().toLowerCase();
        return name.contains(q) || chNum.contains(q);
      }).toList();
    }

    // Filter by Read/Unread
    if (_chapterFilter != 'ALL') {
      displayChapters = displayChapters.where((ch) {
        final String chId = ch['id']?.toString() ?? '';
        final bool isRead = readChapterIds.contains(chId);
        return _chapterFilter == 'READ' ? isRead : !isRead;
      }).toList();
    }

    // Reset pagination if query or filters change
    if (_chapterSearchQuery != _lastQuery || _chapterFilter != _lastFilter) {
      _currentPage = 1;
      _lastQuery = _chapterSearchQuery;
      _lastFilter = _chapterFilter;
    }

    // Pagination slicing
    final int totalPages = (displayChapters.length / _chaptersPerPage).ceil().clamp(1, double.infinity).toInt();
    if (_currentPage > totalPages) {
      _currentPage = totalPages;
    }
    final int startIndex = (_currentPage - 1) * _chaptersPerPage;
    final int endIndex = (startIndex + _chaptersPerPage).clamp(0, displayChapters.length);
    final pageChapters = displayChapters.sublist(startIndex, endIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

        // Chapters list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: pageChapters.length,
          itemBuilder: (context, index) {
            final chapter = pageChapters[index];
            final String chName = chapter['name'] ?? 'Chapter';
            final String chId = chapter['id']?.toString() ?? '';
            final double? chNum = double.tryParse(chapter['chapterNumber']?.toString() ?? '');
            final bool isRead = readChapterIds.contains(chId);

            final int currentChapterIdx = (chNum?.toInt() ?? 1);

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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isRead ? Icons.check_circle : Icons.check_circle_outline,
                        color: isRead ? const Color(0xFFFF9F1C) : Colors.white24,
                        size: 18.0,
                      ),
                      onPressed: () {
                        widget.onSetChapterReadStatus(chId, !isRead);
                      },
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20.0),
                      color: const Color(0xFF16161A),
                      offset: const Offset(0, 30),
                      onSelected: (action) async {
                        final libraryState = LibraryState();
                        final list = widget.chapters.reversed.toList();
                        final currentIdx = list.indexWhere((ch) => ch['id']?.toString() == chId);
                        if (currentIdx == -1) return;

                        if (action == 'toggle') {
                          await libraryState.setChapterReadStatus(widget.mangaId, chId, !isRead);
                        } else if (action == 'prev_read') {
                          for (int i = 0; i <= currentIdx; i++) {
                            final id = list[i]['id']?.toString() ?? '';
                            if (id.isNotEmpty) {
                              await libraryState.setChapterReadStatus(widget.mangaId, id, true);
                            }
                          }
                        } else if (action == 'prev_unread') {
                          for (int i = 0; i <= currentIdx; i++) {
                            final id = list[i]['id']?.toString() ?? '';
                            if (id.isNotEmpty) {
                              await libraryState.setChapterReadStatus(widget.mangaId, id, false);
                            }
                          }
                        } else if (action == 'next_read') {
                          for (int i = currentIdx; i < list.length; i++) {
                            final id = list[i]['id']?.toString() ?? '';
                            if (id.isNotEmpty) {
                              await libraryState.setChapterReadStatus(widget.mangaId, id, true);
                            }
                          }
                        } else if (action == 'next_unread') {
                          for (int i = currentIdx; i < list.length; i++) {
                            final id = list[i]['id']?.toString() ?? '';
                            if (id.isNotEmpty) {
                              await libraryState.setChapterReadStatus(widget.mangaId, id, false);
                            }
                          }
                        }
                        setState(() {});
                        widget.onUpdated();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(isRead ? 'Mark as Unread' : 'Mark as Read', style: const TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                        ),
                        const PopupMenuItem(
                          value: 'prev_read',
                          child: Text('Mark Previous as Read', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                        ),
                        const PopupMenuItem(
                          value: 'prev_unread',
                          child: Text('Mark Previous as Unread', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                        ),
                        const PopupMenuItem(
                          value: 'next_read',
                          child: Text('Mark Next as Read', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                        ),
                        const PopupMenuItem(
                          value: 'next_unread',
                          child: Text('Mark Next as Unread', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                        ),
                      ],
                    ),
                  ],
                ),
                onTap: () {
                  if (chId.isNotEmpty) {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (context) => MangaReaderPage(
                          chapterId: chId,
                          chapterNumber: currentChapterIdx,
                          mangaId: widget.mangaId.toString(),
                          mangaTitle: widget.title,
                          chapters: widget.chapters,
                          navigationState: widget.navigationState,
                        ),
                      ),
                    ).then((_) {
                      setState(() {});
                    });
                  }
                },
              ),
            );
          },
        ),

        // Sliced pagination controller
        if (totalPages > 1) ...[
          const SizedBox(height: 20.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left, color: _currentPage > 1 ? Colors.white : Colors.white24),
                onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
              ),
              const SizedBox(width: 16),
              Text(
                'Page $_currentPage of $totalPages',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: Icon(Icons.chevron_right, color: _currentPage < totalPages ? Colors.white : Colors.white24),
                onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
