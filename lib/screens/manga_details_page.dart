import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/suwayomi_service.dart';
import '../state/navigation_state.dart';
import '../state/library_state.dart';
import '../services/manga_download_service.dart';
import 'manga_reader_page.dart';
import '../widgets/smooth_scroll_area.dart';

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
      Map<String, dynamic>? info;
      try {
        info = await _suwayomiService.getMangaDetails(_parsedMangaId);
      } catch (detailsError) {
        // Fallback: If details endpoint crashed (e.g. Kotlin serialization error), try to fetch chapters anyway.
        try {
          final chaps = await _suwayomiService.getChapters(_parsedMangaId);
          final fallbackDetails = {
            'title': 'Manga Reader',
            'thumbnailUrl': '',
            'author': 'Unknown',
            'artist': 'Unknown',
            'description': 'Details could not be loaded from source because of API serialization changes: ${detailsError.toString().replaceFirst('Exception: ', '')}.\n\nYou can still access and read all chapters below.',
            'genres': <String>[],
            'status': 0,
          };
          if (mounted) {
            setState(() {
              _details = fallbackDetails;
              _chapters = chaps;
              _isLoading = false;
              _errorMessage = null;
            });
          }
          return;
        } catch (_) {
          // If chapters also fail, rethrow the original details error to be handled by the outer catch.
          rethrow;
        }
      }

      if (info == null) {
        final pathInfo = await _suwayomiService.getMangaPath(_parsedMangaId);
        String msg = "Error loading manga details. Please verify your extension is installed.";
        if (pathInfo != null) {
          final sourceId = pathInfo['sourceId'] ?? '';
          final savedExtName = await _suwayomiService.getMangaExtensionName(_parsedMangaId);
          
          final Map<String, String> commonSourceNames = {
            '1797754663718263026': 'IMHentai',
            '2495670732386221764': 'MangaDex',
            '674510793616616656': 'MangaLife',
            '3016480572224097495': 'MangaPark',
            '4778103322122606556': 'MangaSee',
            '6608552103444641979': 'ReadMng',
            '4934091395535313936': 'Mangakakalot',
            '4397756184514589920': 'Asura Scans',
            '8531542650987673943': 'Flame Comics',
            '8934524458823724892': 'MangaReader',
            '6188448937664687595': 'Bato.to',
            '7080517865249514686': 'NHentai',
            '4751475184856950293': 'Webtoons',
            '3297120349812398492': 'MangaHasu',
            '6948512395539502391': 'ReadComicOnline',
          };
          
          final resolvedExtName = savedExtName ?? commonSourceNames[sourceId];
          if (resolvedExtName != null && resolvedExtName.isNotEmpty) {
            msg = "Manga extension '$resolvedExtName' is not installed. Please install it from the Extensions tab to view details.";
          } else if (sourceId.isNotEmpty) {
            msg = "Manga source ID '$sourceId' is not installed. Please install the corresponding extension to view details.";
          }
        }
        if (mounted) {
          setState(() {
            _errorMessage = msg;
            _isLoading = false;
          });
        }
        return;
      }

      final chaps = await _suwayomiService.getChapters(_parsedMangaId);
      
      if (LibraryState().isSaved(_parsedMangaId, 'manga')) {
        info['cachedChapters'] = chaps;
        LibraryState().updateMangaCache(_parsedMangaId, info);
      }
      
      if (mounted) {
        setState(() {
          _details = info;
          _chapters = chaps;
          _isLoading = false;
        });
      }
    } catch (e) {
      final cached = LibraryState().mangaCache[_parsedMangaId];
      if (cached != null) {
        if (mounted) {
          setState(() {
            _details = cached;
            _chapters = cached['cachedChapters'] as List<dynamic>? ?? [];
            _isLoading = false;
            _errorMessage = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString().replaceFirst('Exception: ', '');
            _isLoading = false;
          });
        }
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





    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    // Find the next unread chapter for Continue Reading button
    dynamic continueChapter;
    if (inLibrary && _chapters.isNotEmpty) {
      final readIds = LibraryState().getReadChapterIds(_parsedMangaId).toSet();
      // chapters are ordered newest first — find last unread from the end
      for (int i = _chapters.length - 1; i >= 0; i--) {
        final chId = _chapters[i]['id']?.toString() ?? '';
        if (!readIds.contains(chId)) {
          continueChapter = _chapters[i];
          break;
        }
      }
      continueChapter ??= _chapters.last;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Background Banner Backdrop (blurred cover)
          if (coverUrl.isNotEmpty)
            Positioned(
              top: 0, left: 0, right: 0,
              height: 300.0,
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: coverUrl,
                    width: double.infinity,
                    height: 300.0,
                    fit: BoxFit.cover,
                    memCacheWidth: 600,
                    placeholder: (_, __) => const SizedBox(),
                    errorWidget: (_, __, ___) => const SizedBox(),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black26, Colors.black87, Colors.black],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 2. Main scrollable content
          Positioned.fill(
            child: SmoothScrollArea(
              builder: (controller, physics) => SingleChildScrollView(
                controller: controller,
                physics: physics,
                child: Padding(
                  padding: const EdgeInsets.only(top: 40.0, bottom: 40.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // â”€â”€ Top bar: back + title + bookmark â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                          ListenableBuilder(
                            listenable: LibraryState(),
                            builder: (context, _) {
                              final saved = LibraryState().isSaved(_parsedMangaId, 'manga');
                              return IconButton(
                                icon: Icon(
                                  saved ? Icons.bookmark : Icons.bookmark_border,
                                  color: saved ? Colors.amber : Colors.white,
                                  size: 18.0,
                                ),
                                onPressed: _showLibraryEditPanel,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                                  padding: const EdgeInsets.all(10.0),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 180.0),

                    // â”€â”€ Hero: cover + metadata â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16.0 : 0.0),
                        child: SizedBox(
                          width: isMobile ? double.infinity : screenWidth * 0.7,
                          child: Column(
                            crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                            children: [
                              isMobile
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // Cover
                                        if (coverUrl.isNotEmpty)
                                          Container(
                                            height: 180.0, width: 125.0,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8.0),
                                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 12.0, offset: const Offset(0, 4))],
                                              border: Border.all(color: Colors.white10),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(7.0),
                                              child: CachedNetworkImage(imageUrl: coverUrl, fit: BoxFit.cover, memCacheWidth: 250),
                                            ),
                                          ),
                                        const SizedBox(height: 16.0),
                                        // Author
                                        if (authorStr != 'Unknown Author')
                                          Text(authorStr, textAlign: TextAlign.center,
                                            style: const TextStyle(color: Colors.white54, fontSize: 13.0, fontFamily: 'Outfit', fontWeight: FontWeight.w500)),
                                        const SizedBox(height: 8.0),
                                        // Continue Reading button
                                        if (inLibrary && continueChapter != null)
                                          _buildContinueButton(continueChapter, true),
                                        const SizedBox(height: 12.0),
                                        // Big title
                                        Text(title, textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white, fontSize: 22.0, fontWeight: FontWeight.bold, letterSpacing: -0.5, fontFamily: 'Outfit', height: 1.2)),
                                        const SizedBox(height: 12.0),
                                        // Badges
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          spacing: 8.0, runSpacing: 8.0,
                                          children: [
                                            _buildBadge(statusStr),
                                            _buildBadge('${_chapters.length} Chapters'),
                                          ],
                                        ),
                                        const SizedBox(height: 12.0),
                                        // Genres
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          spacing: 6.0, runSpacing: 6.0,
                                          children: genres.map((g) => Chip(
                                            label: Text(g, style: const TextStyle(fontSize: 11.0, color: Colors.white70)),
                                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                                            padding: EdgeInsets.zero,
                                            side: BorderSide.none,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          )).toList(),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Cover
                                        if (coverUrl.isNotEmpty)
                                          Container(
                                            height: 220.0, width: 155.0,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8.0),
                                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 12.0, offset: const Offset(0, 4))],
                                              border: Border.all(color: Colors.white10),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(7.0),
                                              child: CachedNetworkImage(imageUrl: coverUrl, fit: BoxFit.cover, memCacheWidth: 310),
                                            ),
                                          ),
                                        const SizedBox(width: 24.0),
                                        // Metadata column
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Author
                                              if (authorStr != 'Unknown Author')
                                                Text(authorStr,
                                                  style: const TextStyle(color: Colors.white54, fontSize: 14.0, fontFamily: 'Outfit', fontWeight: FontWeight.w500)),
                                              // Continue Reading button
                                              if (inLibrary && continueChapter != null)
                                                _buildContinueButton(continueChapter, false),
                                              const SizedBox(height: 12.0),
                                              // Big title
                                              Text(title,
                                                style: const TextStyle(color: Colors.white, fontSize: 28.0, fontWeight: FontWeight.bold, letterSpacing: -0.5, fontFamily: 'Outfit', height: 1.2)),
                                              const SizedBox(height: 14.0),
                                              // Badges
                                              Wrap(
                                                spacing: 8.0, runSpacing: 8.0,
                                                children: [
                                                  _buildBadge(statusStr),
                                                  _buildBadge('${_chapters.length} Chapters'),
                                                ],
                                              ),
                                              const SizedBox(height: 16.0),
                                              // Genres
                                              Wrap(
                                                spacing: 6.0, runSpacing: 6.0,
                                                children: genres.map((g) => Chip(
                                                  label: Text(g, style: const TextStyle(fontSize: 11.0, color: Colors.white70)),
                                                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                                                  padding: EdgeInsets.zero,
                                                  side: BorderSide.none,
                                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                )).toList(),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                              const SizedBox(height: 36.0),

                              // â”€â”€ Description â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                              _buildDescriptionSection(description),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40.0),
                    Container(height: 1.0, color: Colors.white10),
                    const SizedBox(height: 24.0),

                    // â”€â”€ Chapter list â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: _MangaChaptersSection(
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
                        onUpdated: () => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, {bool isAccent = false, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: color ?? (isAccent ? Colors.white24 : Colors.white10),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
      ),
    );
  }

  Widget _buildContinueButton(dynamic chapter, bool isMobile) {
    final chapterNum = chapter['chapterNumber']?.toString() ?? chapter['name']?.toString() ?? '?';
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 4.0),
      child: Row(
        mainAxisAlignment: isMobile ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.menu_book, color: Colors.black, size: 18.0),
            label: Text(
              'Continue Ch $chapterNum',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Outfit', fontSize: 13.5),
            ),
            onPressed: () {
              final String chId = chapter['id']?.toString() ?? '';
              final int chNum = _parseMangaChapterNumber(chapter);
              if (chId.isNotEmpty) {
                // Keep navigationState updated
                widget.navigationState.startReading(
                  chapterId: chId,
                  chapterNumber: chNum,
                  mangaId: widget.mangaId.toString(),
                  mangaTitle: _details!['title']?.toString() ?? 'Unknown Manga',
                  chapters: _chapters,
                );
                // Push reader page directly so navigation actually happens
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                    builder: (context) => MangaReaderPage(
                      chapterId: chId,
                      chapterNumber: chNum,
                      mangaId: widget.mangaId.toString(),
                      mangaTitle: _details!['title']?.toString() ?? 'Unknown Manga',
                      chapters: _chapters,
                      navigationState: widget.navigationState,
                    ),
                  ),
                ).then((_) {
                  setState(() {});
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              elevation: 4.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 12.0),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white24, width: 2.0)),
          ),
          child: const Text(
            'Description',
            style: TextStyle(color: Colors.white, fontSize: 15.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
        ),
        const SizedBox(height: 16.0),
        Text(
          description,
          style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.55, fontFamily: 'Outfit'),
        ),
      ],
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
  late final TextEditingController _chaptersController;
  late final TextEditingController _scoreController;

  @override
  void initState() {
    super.initState();
    _activeStatus = widget.savedItem?.libraryStatus ?? 'watching';
    _activeRating = widget.savedItem?.rating ?? 0.0;
    _chaptersRead = widget.savedItem?.watchedEpisodes ?? 0;
    _selectedCategoryIds = List<String>.from(widget.savedItem?.categoryIds ?? <String>[]);
    _newCategoryController = TextEditingController();
    _chaptersController = TextEditingController(text: '$_chaptersRead');
    _scoreController = TextEditingController(
      text: _activeRating == 0.0 ? '' : _activeRating.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    _chaptersController.dispose();
    _scoreController.dispose();
    super.dispose();
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Chapters Read
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
                                              setState(() => _chaptersRead = parsed.clamp(0, widget.totalChapters > 0 ? widget.totalChapters : 99999));
                                            }
                                          },
                                          onSubmitted: (val) => _updateChaptersRead(int.tryParse(val) ?? _chaptersRead),
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
                                      '${((_chaptersRead / widget.totalChapters) * 100).clamp(0, 100).toStringAsFixed(0)}%',
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
                                  max: widget.totalChapters > 0 ? widget.totalChapters.toDouble() : (_chaptersRead + 50).toDouble(),
                                  divisions: widget.totalChapters > 0 ? widget.totalChapters : (_chaptersRead + 50),
                                  label: '$_chaptersRead',
                                  onChanged: (val) => _updateChaptersRead(val.toInt()),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16.0),

                        // Rating Score
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
                                            if (parsed != null) setState(() => _activeRating = parsed.clamp(0.0, 10.0));
                                          },
                                          onSubmitted: (val) => _updateRating(double.tryParse(val) ?? _activeRating),
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

                        // Categories
                        ListenableBuilder(
                          listenable: LibraryState(),
                          builder: (context, _) {
                            final cats = LibraryState().categories.where((cat) => cat.mode == 'manga').toList();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 16.0),
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
                                        onPressed: () => setState(() => _isCreatingCategory = true),
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
                                              side: BorderSide(color: isChecked ? Colors.white : Colors.white24),
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
                            LibraryState().updateMangaCache(widget.mangaId, widget.mangaDetails);
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
    final List<String> downloadedChapterIds = libraryState.getDownloadedChapterIds(widget.mangaId);
    final downloadService = MangaDownloadService();

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

            final int currentChapterIdx = _parseMangaChapterNumber(chapter);

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
                    // Download button / progress / delete
                    _buildDownloadTrailing(
                      chId: chId,
                      chName: chName,
                      chNum: chNum ?? 1.0,
                      downloadedChapterIds: downloadedChapterIds,
                      downloadService: downloadService,
                      libraryState: libraryState,
                    ),
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
                        } else if (action == 'download') {
                          _handleDownloadAction(chId, chName, chNum ?? 1.0, downloadedChapterIds, downloadService, libraryState);
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
                        PopupMenuItem(
                          value: 'download',
                          child: Text(
                            downloadedChapterIds.contains(chId) ? 'Delete Download' : 'Download Chapter',
                            style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
                          ),
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
  // ── Download helpers ────────────────────────────────────────────────────────

  Widget _buildDownloadTrailing({
    required String chId,
    required String chName,
    required double chNum,
    required List<String> downloadedChapterIds,
    required MangaDownloadService downloadService,
    required LibraryState libraryState,
  }) {
    if (chId.isEmpty) return const SizedBox.shrink();

    // Check if actively downloading
    final activeTask = downloadService.tasks.firstWhere(
      (t) => t.id == '${widget.mangaId}_${int.tryParse(chId) ?? chId.hashCode}',
      orElse: () => MangaDownloadTask(
        mangaId: -1, mangaTitle: '', chapterId: -1, chapterName: '', chapterNumber: 0,
      ),
    );
    final isQueued = activeTask.mangaId != -1 &&
        (activeTask.status == MangaDownloadStatus.queued || activeTask.status == MangaDownloadStatus.paused);
    final isDownloading = activeTask.mangaId != -1 && activeTask.status == MangaDownloadStatus.downloading;
    final isDownloaded = downloadedChapterIds.contains(chId);

    if (isDownloading) {
      return SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: activeTask.progress > 0 ? activeTask.progress : null,
              strokeWidth: 2.0,
              color: const Color(0xFFFF9F1C),
            ),
            GestureDetector(
              onTap: () {
                downloadService.cancel(activeTask.id);
                setState(() {});
              },
              child: const Icon(Icons.close, color: Colors.white54, size: 14),
            ),
          ],
        ),
      );
    }

    if (isQueued) {
      return IconButton(
        icon: const Icon(Icons.hourglass_top, color: Colors.white38, size: 18),
        tooltip: 'Queued — tap to cancel',
        onPressed: () {
          downloadService.cancel(activeTask.id);
          setState(() {});
        },
      );
    }

    if (isDownloaded) {
      return IconButton(
        icon: const Icon(Icons.download_done, color: Color(0xFF4CAF50), size: 18),
        tooltip: 'Downloaded — tap to delete',
        onPressed: () => _handleDownloadAction(chId, chName, chNum, downloadedChapterIds, downloadService, libraryState),
      );
    }

    return IconButton(
      icon: const Icon(Icons.download_outlined, color: Colors.white38, size: 18),
      tooltip: 'Download chapter',
      onPressed: () => _handleDownloadAction(chId, chName, chNum, downloadedChapterIds, downloadService, libraryState),
    );
  }

  void _handleDownloadAction(
    String chId,
    String chName,
    double chNum,
    List<String> downloadedChapterIds,
    MangaDownloadService downloadService,
    LibraryState libraryState,
  ) {
    final numericChId = int.tryParse(chId) ?? chId.hashCode;
    if (downloadedChapterIds.contains(chId)) {
      // Delete download
      final localDir = libraryState.getChapterLocalDir(widget.mangaId, chId);
      if (localDir != null) {
        try { Directory(localDir).deleteSync(recursive: true); } catch (_) {}
      }
      libraryState.markChapterNotDownloaded(widget.mangaId, numericChId);
    } else {
      // Enqueue download
      downloadService.enqueue(MangaDownloadTask(
        mangaId: widget.mangaId,
        mangaTitle: widget.title,
        chapterId: numericChId,
        chapterName: chName,
        chapterNumber: chNum,
      ));
    }
    setState(() {});
  }
}

int _parseMangaChapterNumber(dynamic chapter) {
  final rawNum = chapter['chapterNumber'];
  if (rawNum != null) {
    if (rawNum is num) return rawNum.toInt();
    final double? parsed = double.tryParse(rawNum.toString());
    if (parsed != null) return parsed.toInt();
  }
  
  final name = chapter['name']?.toString() ?? '';
  final regex = RegExp(r'(?:chapter|ch\.?|episode|ep\.?)\s*([0-9]+(?:\.[0-9]+)?)', caseSensitive: false);
  final match = regex.firstMatch(name);
  if (match != null) {
    final numStr = match.group(1)!;
    final double? parsed = double.tryParse(numStr);
    if (parsed != null) return parsed.toInt();
  }
  
  final numberRegex = RegExp(r'([0-9]+(?:\.[0-9]+)?)');
  final numMatch = numberRegex.firstMatch(name);
  if (numMatch != null) {
    final numStr = numMatch.group(1)!;
    final double? parsed = double.tryParse(numStr);
    if (parsed != null) return parsed.toInt();
  }
  
  return 1;
}
