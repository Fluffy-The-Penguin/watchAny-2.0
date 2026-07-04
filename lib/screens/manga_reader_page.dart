import '../services/notification_service.dart';
import 'package:flutter/material.dart';
import '../services/suwayomi_service.dart';
import '../state/navigation_state.dart';
import '../state/library_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:async';
import 'package:async/async.dart';

class MangaReaderPage extends StatefulWidget {
  final String chapterId;
  final int chapterNumber;
  final String mangaId;
  final String mangaTitle;
  final List<dynamic> chapters;
  final NavigationState navigationState;

  const MangaReaderPage({
    super.key,
    required this.chapterId,
    required this.chapterNumber,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapters,
    required this.navigationState,
  });

  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

class _MangaReaderPageState extends State<MangaReaderPage> {
  final SuwayomiService _suwayomiService = SuwayomiService();
  bool _isLoading = true;
  String? _errorMessage;

  List<String> _pageUrls = [];
  String _readingFormat = 'webtoon'; // 'webtoon', 'paging_ltr', 'paging_rtl', 'paging_double'
  String _colorFilterMode = 'none'; // 'none', 'grayscale', 'sepia', 'warm', 'inverted', 'boost'
  int _currentPageIndex = 0;
  MangaPageLoader? _pageLoader;
  
  late PageController _pageController;
  late ScrollController _scrollController;
  bool _showOverlay = true;

  late String _currentChapterId;
  late int _currentChapterNumber;

  @override
  void initState() {
    super.initState();
    // Hide status bar and system navigation bar for full screen reading
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    _currentChapterId = widget.chapterId;
    _currentChapterNumber = widget.chapterNumber;
    _pageController = PageController();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadSettings().then((_) {
      _loadPages();
      _updateLibraryProgress();
    });
  }

  @override
  void dispose() {
    // Restore status bar and navigation bar when leaving
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    _scrollController.removeListener(_onScroll);
    _pageLoader?.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_readingFormat != 'webtoon') return;
    if (_scrollController.hasClients && _pageUrls.isNotEmpty) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;
      final percent = _scrollController.offset / maxScroll;
      final estimatedIndex = (percent * (_pageUrls.length - 1)).round().clamp(0, _pageUrls.length - 1);
      if (estimatedIndex != _currentPageIndex) {
        _updatePageIndex(estimatedIndex);
      }
    }
  }

  void _saveCurrentPage(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('manga_chapter_page_$_currentChapterId', index);
  }

  void _updatePageIndex(int index, {bool jump = false}) {
    if (index < 0 || index >= _pageUrls.length) return;
    setState(() {
      _currentPageIndex = index;
    });
    _pageLoader?.setPriorityIndex(index);
    _saveCurrentPage(index);
    if (jump && _readingFormat != 'webtoon' && _pageController.hasClients) {
      if (_readingFormat == 'paging_double') {
        final groups = _getDoublePageIndices();
        final groupIdx = groups.indexWhere((g) => g.contains(index));
        if (groupIdx != -1) {
          _pageController.jumpToPage(groupIdx);
        }
      } else {
        _pageController.jumpToPage(index);
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _readingFormat = prefs.getString('manga_reading_format') ?? 'webtoon';
        _colorFilterMode = prefs.getString('manga_color_filter_mode') ?? 'none';
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manga_reading_format', _readingFormat);
    await prefs.setString('manga_color_filter_mode', _colorFilterMode);
  }

  Future<void> _loadPages() async {
    final int parsedId = int.tryParse(_currentChapterId) ?? 0;
    if (parsedId == 0) {
      if (mounted) {
        setState(() {
          _errorMessage = "Invalid Chapter ID";
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final urls = await _suwayomiService.getChapterPages(parsedId);
      final prefs = await SharedPreferences.getInstance();
      final savedPage = prefs.getInt('manga_chapter_page_$_currentChapterId') ?? 0;

      if (mounted) {
        setState(() {
          _pageUrls = urls;
          _isLoading = false;
          _currentPageIndex = savedPage < urls.length ? savedPage : 0;
          _pageLoader?.dispose();
          _pageLoader = MangaPageLoader(
            chapterId: parsedId,
            urls: urls,
            onPageDownloaded: () {
              if (mounted) setState(() {});
            },
          );
        });

        // Jump or scroll to the saved page on startup
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_readingFormat == 'webtoon') {
            if (_scrollController.hasClients && _currentPageIndex > 0) {
              _scrollController.jumpTo(_currentPageIndex * 1000.0);
            }
          } else {
            if (_pageController.hasClients && _currentPageIndex > 0) {
              if (_readingFormat == 'paging_double') {
                final groups = _getDoublePageIndices();
                final groupIdx = groups.indexWhere((g) => g.contains(_currentPageIndex));
                if (groupIdx != -1) {
                  _pageController.jumpToPage(groupIdx);
                }
              } else {
                _pageController.jumpToPage(_currentPageIndex);
              }
            }
          }
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


  void _updateLibraryProgress() {
    final int parsedMangaId = int.tryParse(widget.mangaId) ?? 0;
    if (parsedMangaId == 0) return;

    final library = LibraryState();
    final item = library.getItem(parsedMangaId, 'manga');
    if (item != null) {
      library.setChapterReadStatus(parsedMangaId, _currentChapterId, true);
    }
  }

  void _nextPage() {
    if (_readingFormat == 'webtoon') {
      _scrollController.animateTo(
        _scrollController.offset + 450,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      if (_readingFormat == 'paging_double') {
        final groups = _getDoublePageIndices();
        final currentGroupIdx = groups.indexWhere((g) => g.contains(_currentPageIndex));
        if (currentGroupIdx != -1 && currentGroupIdx < groups.length - 1) {
          _updatePageIndex(groups[currentGroupIdx + 1][0], jump: true);
        } else {
          _navigateToNextChapter();
        }
      } else {
        if (_currentPageIndex < _pageUrls.length - 1) {
          _updatePageIndex(_currentPageIndex + 1, jump: true);
        } else {
          _navigateToNextChapter();
        }
      }
    }
  }

  void _prevPage() {
    if (_readingFormat == 'webtoon') {
      _scrollController.animateTo(
        _scrollController.offset - 450,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      if (_readingFormat == 'paging_double') {
        final groups = _getDoublePageIndices();
        final currentGroupIdx = groups.indexWhere((g) => g.contains(_currentPageIndex));
        if (currentGroupIdx != -1 && currentGroupIdx > 0) {
          _updatePageIndex(groups[currentGroupIdx - 1][0], jump: true);
        } else {
          _navigateToPrevChapter();
        }
      } else {
        if (_currentPageIndex > 0) {
          _updatePageIndex(_currentPageIndex - 1, jump: true);
        } else {
          _navigateToPrevChapter();
        }
      }
    }
  }

  void _navigateToNextChapter() {
    final chapters = widget.chapters;
    final currentIdx = chapters.indexWhere((c) => c['id']?.toString() == _currentChapterId);
    if (currentIdx != -1 && currentIdx > 0) {
      final nextChapter = chapters[currentIdx - 1];
      final String? nextId = nextChapter['id']?.toString();
      final double? nextNum = double.tryParse(nextChapter['chapterNumber']?.toString() ?? '');
      
      if (nextId != null) {
        setState(() {
          _currentChapterId = nextId;
          _currentChapterNumber = nextNum?.toInt() ?? (_currentChapterNumber + 1);
          _isLoading = true;
          _pageUrls = [];
          _currentPageIndex = 0;
        });
        _loadPages();
        _updateLibraryProgress();
      }
    } else {
      NotificationService().show(context, 'You have reached the latest chapter.');
    }
  }

  void _navigateToPrevChapter() {
    final chapters = widget.chapters;
    final currentIdx = chapters.indexWhere((c) => c['id']?.toString() == _currentChapterId);
    if (currentIdx != -1 && currentIdx < chapters.length - 1) {
      final prevChapter = chapters[currentIdx + 1];
      final String? prevId = prevChapter['id']?.toString();
      final double? prevNum = double.tryParse(prevChapter['chapterNumber']?.toString() ?? '');
      
      if (prevId != null) {
        setState(() {
          _currentChapterId = prevId;
          _currentChapterNumber = prevNum?.toInt() ?? (_currentChapterNumber - 1);
          _isLoading = true;
          _pageUrls = [];
          _currentPageIndex = 0;
        });
        _loadPages();
        _updateLibraryProgress();
      }
    } else {
      NotificationService().show(context, 'No previous chapters available.');
    }
  }

  List<List<int>> _getDoublePageIndices() {
    final indices = <List<int>>[];
    if (_pageUrls.isEmpty) return indices;
    
    // Page 0 is cover
    indices.add([0]);
    
    for (int i = 1; i < _pageUrls.length; i += 2) {
      if (i + 1 < _pageUrls.length) {
        indices.add([i, i + 1]);
      } else {
        indices.add([i]);
      }
    }
    return indices;
  }

  Widget _buildColorFilteredWidget(Widget child) {
    if (_colorFilterMode == 'none') return child;
    
    ColorFilter filter;
    switch (_colorFilterMode) {
      case 'grayscale':
        filter = const ColorFilter.matrix([
          0.33, 0.59, 0.11, 0, 0,
          0.33, 0.59, 0.11, 0, 0,
          0.33, 0.59, 0.11, 0, 0,
          0,    0,    0,    1, 0,
        ]);
        break;
      case 'sepia':
        filter = const ColorFilter.matrix([
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0,     0,     0,     1, 0,
        ]);
        break;
      case 'warm':
        filter = const ColorFilter.matrix([
          1.05, 0,    0,    0, 10,
          0,    0.95, 0,    0, 0,
          0,    0,    0.85, 0, -10,
          0,    0,    0,    1, 0,
        ]);
        break;
      case 'inverted':
        filter = const ColorFilter.matrix([
          -1.0, 0,    0,    0, 255,
          0,    -1.0, 0,    0, 255,
          0,    0,    -1.0, 0, 255,
          0,    0,    0,    1, 0,
        ]);
        break;
      case 'boost':
        filter = const ColorFilter.matrix([
          1.2,  0,    0,    0, 0,
          0,    1.2,  0,    0, 0,
          0,    0,    1.2,  0, 0,
          0,    0,    0,    1.0, 0,
        ]);
        break;
      default:
        return child;
    }
    return ColorFiltered(
      colorFilter: filter,
      child: child,
    );
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F11),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget buildFormatTile(String value, String label, IconData icon) {
              final isSelected = _readingFormat == value;
              return ListTile(
                leading: Icon(icon, color: isSelected ? const Color(0xFFFF9F1C) : Colors.white70),
                title: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontFamily: 'Outfit',
                  ),
                ),
                trailing: isSelected ? const Icon(Icons.check, color: Color(0xFFFF9F1C)) : null,
                onTap: () {
                  setState(() {
                    _readingFormat = value;
                  });
                  setSheetState(() {});
                  _saveSettings();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (_readingFormat == 'webtoon') {
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(_currentPageIndex * 1000.0);
                      }
                    } else {
                      if (_pageController.hasClients) {
                        if (_readingFormat == 'paging_double') {
                          final groups = _getDoublePageIndices();
                          final groupIdx = groups.indexWhere((g) => g.contains(_currentPageIndex));
                          if (groupIdx != -1) {
                            _pageController.jumpToPage(groupIdx);
                          }
                        } else {
                          _pageController.jumpToPage(_currentPageIndex);
                        }
                      }
                    }
                  });
                },
              );
            }

            Widget buildFilterTile(String value, String label, IconData icon) {
              final isSelected = _colorFilterMode == value;
              return ListTile(
                leading: Icon(icon, color: isSelected ? const Color(0xFFFF9F1C) : Colors.white70),
                title: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontFamily: 'Outfit',
                  ),
                ),
                trailing: isSelected ? const Icon(Icons.check, color: Color(0xFFFF9F1C)) : null,
                onTap: () {
                  setState(() {
                    _colorFilterMode = value;
                  });
                  setSheetState(() {});
                  _saveSettings();
                },
              );
            }

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                      child: Text(
                        'Reading Format',
                        style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                      ),
                    ),
                    buildFormatTile('webtoon', 'Webtoon (Continuous Vertical)', Icons.swap_vert),
                    buildFormatTile('paging_ltr', 'Paging (Left-to-Right)', Icons.arrow_forward),
                    buildFormatTile('paging_rtl', 'Paging (Right-to-Left)', Icons.arrow_back),
                    buildFormatTile('paging_double', 'Double Page (Landscape)', Icons.chrome_reader_mode),
                    
                    const Divider(color: Colors.white12, height: 24.0),

                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                      child: Text(
                        'Color Enhancers (GPU Shaders)',
                        style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                      ),
                    ),
                    buildFilterTile('none', 'None (Original)', Icons.image),
                    buildFilterTile('grayscale', 'Grayscale (High Contrast Lineart)', Icons.contrast),
                    buildFilterTile('inverted', 'OLED Night (Inverted)', Icons.invert_colors),
                    buildFilterTile('warm', 'Warm Tone (Eye Protection)', Icons.remove_red_eye),
                    buildFilterTile('sepia', 'Sepia (Paper Nostalgia)', Icons.history_edu),
                    buildFilterTile('boost', 'Color Boost (Vivid Saturation)', Icons.palette),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Content Viewer
          GestureDetector(
            onTapUp: (details) {
              final width = MediaQuery.of(context).size.width;
              final dx = details.localPosition.dx;
              
              if (dx < width * 0.3) {
                // Left margin tap: prev page
                if (_readingFormat == 'paging_rtl') {
                  _nextPage();
                } else {
                  _prevPage();
                }
              } else if (dx > width * 0.7) {
                // Right margin tap: next page
                if (_readingFormat == 'paging_rtl') {
                  _prevPage();
                } else {
                  _nextPage();
                }
              } else {
                // Center tap: toggle overlay
                setState(() => _showOverlay = !_showOverlay);
              }
            },
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
                    ),
                  )
                : _errorMessage != null
                    ? _buildErrorView()
                    : _readingFormat == 'webtoon'
                        ? _buildWebtoonViewer()
                        : _buildPagingViewer(),
          ),

          // Top Header Overlay Controls
          if (_showOverlay)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopOverlay(),
            ),

          // Bottom Slider & Mode Overlay Controls
          if (_showOverlay && !_isLoading && _errorMessage == null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomOverlay(),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 40.0),
          const SizedBox(height: 12.0),
          Text(
            _errorMessage ?? 'Failed to load chapter pages',
            style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 16.0),
          ElevatedButton(
            onPressed: _loadPages,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9F1C),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildPageImage(int index) {
    final localPath = _pageLoader?.localPaths[index];
    if (localPath != null) {
      return Image.file(
        File(localPath),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white30, size: 40),
        ),
      );
    }
    return Container(
      height: 500,
      color: Colors.black12,
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
        ),
      ),
    );
  }

  Widget _buildWebtoonViewer() {
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 4.0,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          itemCount: _pageUrls.length,
          itemBuilder: (context, index) {
            _pageLoader?.setPriorityIndex(index);
            return Center(
              child: _buildColorFilteredWidget(
                _buildPageImage(index),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPagingViewer() {
    final bool isDouble = _readingFormat == 'paging_double';
    final bool isRtl = _readingFormat == 'paging_rtl';
    
    if (isDouble) {
      final groups = _getDoublePageIndices();
      return PageView.builder(
        controller: _pageController,
        itemCount: groups.length,
        reverse: isRtl,
        onPageChanged: (index) {
          if (index < groups.length) {
            _updatePageIndex(groups[index][0]);
          }
        },
        itemBuilder: (context, index) {
          final group = groups[index];
          final children = <Widget>[];
          
          if (group.length == 2) {
            final leftIdx = isRtl ? group[1] : group[0];
            final rightIdx = isRtl ? group[0] : group[1];
            
            children.addAll([
              Expanded(
                child: Center(
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: _buildColorFilteredWidget(
                      _buildPageImage(leftIdx),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: Center(
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: _buildColorFilteredWidget(
                      _buildPageImage(rightIdx),
                    ),
                  ),
                ),
              ),
            ]);
          } else {
            children.add(
              Expanded(
                child: Center(
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: _buildColorFilteredWidget(
                      _buildPageImage(group[0]),
                    ),
                  ),
                ),
              ),
            );
          }
          
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          );
        },
      );
    } else {
      return PageView.builder(
        controller: _pageController,
        itemCount: _pageUrls.length,
        reverse: isRtl,
        onPageChanged: (index) {
          _updatePageIndex(index);
        },
        itemBuilder: (context, index) {
          return Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: _buildColorFilteredWidget(
                _buildPageImage(index),
              ),
            ),
          );
        },
      );
    }
  }

  Widget _buildTopOverlay() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black87, Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 40.0, bottom: 20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28.0),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.mangaTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                Text(
                  'Chapter $_currentChapterNumber',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12.0,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomOverlay() {
    final bool isDouble = _readingFormat == 'paging_double';
    final int doublePageCount = isDouble ? _getDoublePageIndices().length : _pageUrls.length;
    final int activeSliderVal = isDouble 
        ? _getDoublePageIndices().indexWhere((g) => g.contains(_currentPageIndex)).clamp(0, doublePageCount - 1)
        : _currentPageIndex;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black87],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 20.0, bottom: 32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slider navigation (only in paging mode)
          if (_readingFormat != 'webtoon' && _pageUrls.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  '${activeSliderVal + 1}',
                  style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: Slider(
                    value: activeSliderVal.toDouble(),
                    min: 0.0,
                    max: (doublePageCount - 1).toDouble(),
                    activeColor: const Color(0xFFFF9F1C),
                    inactiveColor: Colors.white12,
                    onChanged: (val) {
                      final idx = val.toInt();
                      final targetPageIdx = isDouble ? _getDoublePageIndices()[idx][0] : idx;
                      _updatePageIndex(targetPageIdx);
                      if (_readingFormat == 'webtoon') {
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(targetPageIdx * 1000.0);
                        }
                      } else {
                        if (_pageController.hasClients) {
                          _pageController.jumpToPage(idx);
                        }
                      }
                    },
                  ),
                ),
                Text(
                  '$doublePageCount',
                  style: const TextStyle(color: Colors.white30, fontFamily: 'Outfit'),
                ),
              ],
            ),
            const SizedBox(height: 12.0),
          ],

          // Footer Controls: Mode Selector & Chapter Jumper
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Direction Selector
              IconButton(
                icon: const Icon(Icons.tune, color: Colors.white),
                tooltip: 'Reader Settings',
                onPressed: _showSettingsBottomSheet,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF16161A),
                  padding: const EdgeInsets.all(12.0),
                ),
              ),

              // Chapter Jumpers
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white70),
                    tooltip: 'Previous Chapter',
                    onPressed: _navigateToPrevChapter,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    'Ch. $_currentChapterNumber',
                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 13.0),
                  ),
                  const SizedBox(width: 8.0),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white70),
                    tooltip: 'Next Chapter',
                    onPressed: _navigateToNextChapter,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MangaPageLoader {
  final int chapterId;
  final List<String> urls;
  final VoidCallback onPageDownloaded;
  
  final List<String?> localPaths;
  int _priorityIndex = 0;
  bool _isDisposed = false;
  
  CancelableOperation<void>? _currentOp;
  http.Client? _client;
  
  MangaPageLoader({
    required this.chapterId,
    required this.urls,
    required this.onPageDownloaded,
  }) : localPaths = List<String?>.filled(urls.length, null) {
    _startDownloadLoop();
  }

  void setPriorityIndex(int idx) {
    if (idx < 0 || idx >= urls.length) return;
    if (localPaths[idx] != null) {
      // Already downloaded, but let's pre-cache next ones
      _priorityIndex = idx;
      return;
    }
    if (_priorityIndex == idx) return;
    
    _priorityIndex = idx;
    // Cancel current download to prioritize the new one!
    _cancelCurrent();
  }

  void _cancelCurrent() {
    _currentOp?.cancel();
    _client?.close();
    _client = null;
  }

  void dispose() {
    _isDisposed = true;
    _cancelCurrent();
  }

  Future<void> _startDownloadLoop() async {
    while (!_isDisposed) {
      // Find the next index to download based on priority
      int nextIdx = _getNextIndexToDownload();
      if (nextIdx == -1) {
        // All downloaded! We can rest.
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      await _downloadPage(nextIdx);
      // Brief pause to prevent CPU/Network thrashing
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  int _getNextIndexToDownload() {
    // 1. Check if the priority index itself needs download
    if (localPaths[_priorityIndex] == null) {
      return _priorityIndex;
    }
    
    // 2. Check adjacent indices (forward first, up to 3 pages)
    for (int i = 1; i <= 3; i++) {
      final idx = _priorityIndex + i;
      if (idx < urls.length && localPaths[idx] == null) {
        return idx;
      }
    }
    
    // 3. Check adjacent indices (backward, up to 2 pages)
    for (int i = 1; i <= 2; i++) {
      final idx = _priorityIndex - i;
      if (idx >= 0 && localPaths[idx] == null) {
        return idx;
      }
    }

    // 4. Fallback to first undownloaded page from start
    for (int i = 0; i < urls.length; i++) {
      if (localPaths[i] == null) {
        return i;
      }
    }
    
    return -1; // Everything downloaded
  }

  Future<void> _downloadPage(int index) async {
    final url = urls[index];
    
    // Create local path
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}${Platform.pathSeparator}manga_ch_${chapterId}_p_$index.jpg');
    
    // If it already exists on disk (e.g. from a previous view), use it!
    if (await file.exists() && await file.length() > 100) {
      localPaths[index] = file.path;
      onPageDownloaded();
      return;
    }

    _client = http.Client();
    final client = _client!;
    
    final completer = Completer<void>();
    
    final requestFuture = Future(() async {
      try {
        final response = await client.get(Uri.parse(url));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await file.writeAsBytes(response.bodyBytes);
          localPaths[index] = file.path;
          onPageDownloaded();
        }
      } catch (_) {
        // Fail silently so it can retry later
      } finally {
        completer.complete();
      }
    });

    _currentOp = CancelableOperation.fromFuture(
      requestFuture,
      onCancel: () {
        completer.complete();
      },
    );

    await completer.future;
  }
}
