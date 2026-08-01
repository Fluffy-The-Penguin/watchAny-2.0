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
  bool _descriptionExpanded = false;
  String? _errorMessage;

  Map<String, dynamic>? _details;
  List<dynamic> _chapters = [];
  dynamic _continueChapter;
  int get _parsedMangaId => int.tryParse(widget.mangaId) ?? 0;

  void _updateContinueChapter() {
    if (LibraryState().isSaved(_parsedMangaId, 'manga') && _chapters.isNotEmpty) {
      final readIds = LibraryState().getReadChapterIds(_parsedMangaId).toSet();
      for (int i = _chapters.length - 1; i >= 0; i--) {
        final chId = _chapters[i]['id']?.toString() ?? '';
        if (!readIds.contains(chId)) {
          _continueChapter = _chapters[i];
          return;
        }
      }
      _continueChapter = _chapters.first;
    } else {
      _continueChapter = null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadMangaDetails();
      }
    });
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
      // 1. Concurrently fetch details AND chapters in background
      final results = await Future.wait([
        _suwayomiService.getMangaDetails(_parsedMangaId).catchError((_) => null),
        _suwayomiService.getChapters(_parsedMangaId).catchError((_) => <dynamic>[]),
      ]);

      final Map<String, dynamic>? info = results[0] as Map<String, dynamic>?;
      final List<dynamic> chaps = results[1] as List<dynamic>;

      // Check cached fallback if network fetch was partial
      final cachedData = LibraryState().mangaCache[_parsedMangaId];
      final finalInfo = info ?? (cachedData != null ? Map<String, dynamic>.from(cachedData) : null);
      final finalChaps = chaps.isNotEmpty ? chaps : ((cachedData?['cachedChapters'] as List?) ?? []);

      if (finalInfo == null && finalChaps.isEmpty) {
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
            '6247824327199706550': 'Asura Scans',
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

      final Map<String, dynamic> resolvedDetails = finalInfo ?? {
        'title': 'Manga Details',
        'thumbnailUrl': '',
        'author': 'Unknown',
        'artist': 'Unknown',
        'description': 'Details could not be fully resolved from source, but chapters are available below.',
        'genres': <String>[],
        'status': 0,
      };

      if (LibraryState().isSaved(_parsedMangaId, 'manga')) {
        resolvedDetails['cachedChapters'] = finalChaps;
        LibraryState().updateMangaCache(_parsedMangaId, resolvedDetails);
      }

      _details = resolvedDetails;
      _chapters = finalChaps;
      _updateContinueChapter();

      // Purposeful micro-delay to let the layout engine settle before revealing the page
      await Future.delayed(const Duration(milliseconds: 150));

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
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





    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    dynamic continueChapter = _continueChapter;
    if (inLibrary && _chapters.isNotEmpty) {
      continueChapter ??= _chapters.last;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: SmoothScrollArea(
        builder: (controller, physics) => SingleChildScrollView(
          controller: controller,
          physics: physics,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. Scrollable Backdrop Banner Header ────────────────────────
              Stack(
                children: [
                  if (coverUrl.isNotEmpty)
                    Positioned.fill(
                      child: ShaderMask(
                        shaderCallback: (rect) {
                          return const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87, Color(0xFF0A0A0C)],
                            stops: [0.0, 0.7, 1.0],
                          ).createShader(rect);
                        },
                        blendMode: BlendMode.darken,
                        child: CachedNetworkImage(
                          imageUrl: coverUrl,
                          width: double.infinity,
                          height: 320.0,
                          fit: BoxFit.cover,
                          memCacheWidth: 600,
                          placeholder: (_, __) => const SizedBox(),
                          errorWidget: (_, __, ___) => const SizedBox(),
                        ),
                      ),
                    ),
                  Container(
                    width: double.infinity,
                    color: Colors.black.withValues(alpha: 0.35),
                    padding: const EdgeInsets.only(top: 36.0, bottom: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top bar: back + title + bookmark
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
                        const SizedBox(height: 20.0),

                        // Hero: cover on LEFT + metadata on RIGHT
                        Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12.0 : 24.0),
                            child: SizedBox(
                              width: isMobile ? double.infinity : screenWidth * 0.85,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Cover on LEFT
                                      if (coverUrl.isNotEmpty)
                                        Container(
                                          height: isMobile ? 165.0 : 210.0,
                                          width: isMobile ? 110.0 : 145.0,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8.0),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.8),
                                                blurRadius: 12.0,
                                                offset: const Offset(0, 4),
                                              )
                                            ],
                                            border: Border.all(color: Colors.white10),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(7.0),
                                            child: CachedNetworkImage(
                                              imageUrl: coverUrl,
                                              fit: BoxFit.cover,
                                              memCacheWidth: isMobile ? 230 : 300,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 16.0),
                                      // Metadata on RIGHT
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (authorStr != 'Unknown Author')
                                              Text(
                                                authorStr,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 13.0,
                                                  fontFamily: 'Outfit',
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            const SizedBox(height: 4.0),
                                            Text(
                                              title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: isMobile ? 19.0 : 24.0,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: -0.5,
                                                fontFamily: 'Outfit',
                                                height: 1.2,
                                              ),
                                            ),
                                            const SizedBox(height: 10.0),
                                            Wrap(
                                              spacing: 6.0,
                                              runSpacing: 6.0,
                                              children: [
                                                _buildBadge(statusStr),
                                                _buildBadge('${_chapters.length} Ch'),
                                              ],
                                            ),
                                            const SizedBox(height: 10.0),
                                            if (inLibrary && continueChapter != null)
                                              _buildContinueButton(continueChapter, false),
                                            const SizedBox(height: 10.0),
                                            Wrap(
                                              spacing: 4.0,
                                              runSpacing: 4.0,
                                              children: genres.take(4).map((g) => Chip(
                                                label: Text(g, style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
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

                                  const SizedBox(height: 20.0),
                                  _buildDescriptionSection(description),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16.0),

              // ── 2. Chapter List Section ─────────────────────────────────────
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 8.0 : 24.0),
                child: RepaintBoundary(
                  child: _MangaChaptersSection(
                    chapters: _chapters,
                    mangaId: _parsedMangaId,
                    title: title,
                    inLibrary: inLibrary,
                    libraryItem: libraryItem,
                    navigationState: widget.navigationState,
                    onSetChapterReadStatus: (chapterId, read) async {
                      await libraryState.setChapterReadStatus(_parsedMangaId, chapterId, read);
                      _updateContinueChapter();
                      setState(() {});
                    },
                    onUpdated: () {
                      _updateContinueChapter();
                      setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(height: 40.0),
            ],
          ),
        ),
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
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => MangaReaderPage(
                      chapterId: chId,
                      chapterNumber: chNum,
                      mangaId: widget.mangaId.toString(),
                      mangaTitle: _details!['title']?.toString() ?? 'Unknown Manga',
                      chapters: _chapters,
                      navigationState: widget.navigationState,
                    ),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      return SlideTransition(
                        position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
                          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                        ),
                        child: child,
                      );
                    },
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
        const SizedBox(height: 12.0),
        AnimatedCrossFade(
          firstChild: Text(
            description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.55, fontFamily: 'Outfit'),
          ),
          secondChild: Text(
            description,
            style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.55, fontFamily: 'Outfit'),
          ),
          crossFadeState: _descriptionExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        const SizedBox(height: 8.0),
        GestureDetector(
          onTap: () {
            setState(() {
              _descriptionExpanded = !_descriptionExpanded;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _descriptionExpanded ? 'Collapse' : 'Read More',
                  style: const TextStyle(
                    color: Color(0xFFFF9F1C),
                    fontSize: 13.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(width: 4.0),
                Icon(
                  _descriptionExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: const Color(0xFFFF9F1C),
                  size: 18.0,
                ),
              ],
            ),
          ),
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
  bool _isSelectionMode = false;
  final Set<String> _selectedChapterIds = {};

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

  String _formatChapterDate(dynamic uploadDate) {
    if (uploadDate == null) return '';
    try {
      DateTime? dt;
      if (uploadDate is int) {
        if (uploadDate > 0) {
          dt = DateTime.fromMillisecondsSinceEpoch(uploadDate);
        }
      } else if (uploadDate is String) {
        dt = DateTime.tryParse(uploadDate);
        if (dt == null && int.tryParse(uploadDate) != null) {
          dt = DateTime.fromMillisecondsSinceEpoch(int.parse(uploadDate));
        }
      }

      if (dt == null) return '';

      final now = DateTime.now();
      final difference = now.difference(dt);

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes.clamp(1, 60)}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
      }
    } catch (_) {
      return '';
    }
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chapter search bar (Vertically centered icon and placeholder)
        Container(
          height: 40.0,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.white10),
          ),
          child: TextField(
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit'),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search chapters by name or number...',
              hintStyle: TextStyle(color: Colors.white24, fontSize: 12.5),
              prefixIcon: Icon(Icons.search, color: Colors.white38, size: 18),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 10.0),
            ),
            onChanged: (val) => setState(() => _chapterSearchQuery = val),
          ),
        ),
        const SizedBox(height: 8.0),

        // Choice chip filters
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
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
        const SizedBox(height: 8.0),

        // Chapters Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Chapters (${displayChapters.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15.0,
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
        const SizedBox(height: 4.0),

        // Bulk Selection Action Bar
        if (_isSelectionMode)
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              decoration: BoxDecoration(
                color: const Color(0xFF18181C),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: const Color(0xFFFF9F1C).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Text(
                    '${_selectedChapterIds.length} Selected',
                    style: const TextStyle(
                      color: Color(0xFFFF9F1C),
                      fontSize: 13.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        final visibleIds = displayChapters.map((c) => c['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
                        if (_selectedChapterIds.containsAll(visibleIds)) {
                          _selectedChapterIds.removeAll(visibleIds);
                        } else {
                          _selectedChapterIds.addAll(visibleIds);
                        }
                      });
                    },
                    child: Text(
                      _selectedChapterIds.containsAll(displayChapters.map((c) => c['id']?.toString() ?? '').where((id) => id.isNotEmpty))
                          ? 'Deselect All'
                          : 'Select All',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.0, fontFamily: 'Outfit'),
                    ),
                  ),
                  TextButton(
                    onPressed: _selectedChapterIds.isEmpty
                        ? null
                        : () async {
                            for (final id in _selectedChapterIds) {
                              await libraryState.setChapterReadStatus(widget.mangaId, id, true);
                            }
                            setState(() {
                              _selectedChapterIds.clear();
                              _isSelectionMode = false;
                            });
                            widget.onUpdated();
                          },
                    child: const Text('Mark Read', style: TextStyle(color: Colors.greenAccent, fontSize: 12.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: _selectedChapterIds.isEmpty
                        ? null
                        : () async {
                            for (final id in _selectedChapterIds) {
                              await libraryState.setChapterReadStatus(widget.mangaId, id, false);
                            }
                            setState(() {
                              _selectedChapterIds.clear();
                              _isSelectionMode = false;
                            });
                            widget.onUpdated();
                          },
                    child: const Text('Mark Unread', style: TextStyle(color: Colors.orangeAccent, fontSize: 12.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = false;
                        _selectedChapterIds.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

        // Continuous Chapters List (No Pagination, Uniform 6px Margins)
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: displayChapters.length,
          itemBuilder: (context, index) {
            final chapter = displayChapters[index];
            final String chName = chapter['name'] ?? 'Chapter';
            final String chId = chapter['id']?.toString() ?? '';
            final double? chNum = double.tryParse(chapter['chapterNumber']?.toString() ?? '');
            final bool isRead = readChapterIds.contains(chId);
            final String scanlator = (chapter['scanlator'] ?? '').toString().trim();
            final String dateStr = _formatChapterDate(chapter['uploadDate'] ?? chapter['dateUpload']);
            final int currentChapterIdx = _parseMangaChapterNumber(chapter);

            final List<String> metaParts = [];
            if (dateStr.isNotEmpty) metaParts.add(dateStr);
            if (scanlator.isNotEmpty) metaParts.add(scanlator);

            final bool isSelected = _selectedChapterIds.contains(chId);

            return Container(
              margin: const EdgeInsets.only(bottom: 6.0),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFF9F1C).withValues(alpha: 0.12) : const Color(0xFF0F0F11),
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(
                  color: isSelected ? const Color(0xFFFF9F1C).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 2.0),
                leading: _isSelectionMode
                    ? Checkbox(
                        value: isSelected,
                        activeColor: const Color(0xFFFF9F1C),
                        checkColor: Colors.black,
                        side: const BorderSide(color: Colors.white38),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedChapterIds.add(chId);
                            } else {
                              _selectedChapterIds.remove(chId);
                              if (_selectedChapterIds.isEmpty) _isSelectionMode = false;
                            }
                          });
                        },
                      )
                    : null,
                title: Text(
                  chName,
                  style: TextStyle(
                    color: isRead ? Colors.white38 : Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Outfit',
                  ),
                ),
                subtitle: metaParts.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 3.0),
                        child: Text(
                          metaParts.join(' • '),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11.5,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                onLongPress: () {
                  setState(() {
                    _isSelectionMode = true;
                    if (_selectedChapterIds.contains(chId)) {
                      _selectedChapterIds.remove(chId);
                      if (_selectedChapterIds.isEmpty) _isSelectionMode = false;
                    } else {
                      _selectedChapterIds.add(chId);
                    }
                  });
                },
                onTap: () {
                  if (_isSelectionMode) {
                    setState(() {
                      if (_selectedChapterIds.contains(chId)) {
                        _selectedChapterIds.remove(chId);
                        if (_selectedChapterIds.isEmpty) _isSelectionMode = false;
                      } else {
                        _selectedChapterIds.add(chId);
                      }
                    });
                  } else {
                    if (chId.isNotEmpty) {
                      Navigator.of(context, rootNavigator: true).push(
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => MangaReaderPage(
                            chapterId: chId,
                            chapterNumber: currentChapterIdx,
                            mangaId: widget.mangaId.toString(),
                            mangaTitle: widget.title,
                            chapters: widget.chapters,
                            navigationState: widget.navigationState,
                          ),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) {
                            return SlideTransition(
                              position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
                                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                              ),
                              child: child,
                            );
                          },
                        ),
                      ).then((_) {
                        setState(() {});
                      });
                    }
                  }
                },
              ),
            );
          },
        ),
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
