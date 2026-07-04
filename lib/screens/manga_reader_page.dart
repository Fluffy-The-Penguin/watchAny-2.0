import '../services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/suwayomi_service.dart';
import '../state/navigation_state.dart';
import '../state/library_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  
  late PageController _pageController;
  late ScrollController _scrollController;
  bool _showOverlay = true;

  late String _currentChapterId;
  late int _currentChapterNumber;

  @override
  void initState() {
    super.initState();
    _currentChapterId = widget.chapterId;
    _currentChapterNumber = widget.chapterNumber;
    _pageController = PageController();
    _scrollController = ScrollController();
    _loadSettings().then((_) {
      _loadPages();
      _updateLibraryProgress();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
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
      if (mounted) {
        setState(() {
          _pageUrls = urls;
          _isLoading = false;
          _currentPageIndex = 0;
          _precacheAdjacentPages(0);
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

  void _precacheAdjacentPages(int currentIndex) {
    if (_pageUrls.isEmpty) return;
    for (int i = 1; i <= 2; i++) {
      final nextIdx = currentIndex + i;
      if (nextIdx < _pageUrls.length) {
        precacheImage(
          CachedNetworkImageProvider(_pageUrls[nextIdx]),
          context,
        );
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
          setState(() {
            _currentPageIndex = groups[currentGroupIdx + 1][0];
            _pageController.jumpToPage(currentGroupIdx + 1);
            _precacheAdjacentPages(_currentPageIndex);
          });
        } else {
          _navigateToNextChapter();
        }
      } else {
        if (_currentPageIndex < _pageUrls.length - 1) {
          setState(() {
            _currentPageIndex++;
            _pageController.jumpToPage(_currentPageIndex);
            _precacheAdjacentPages(_currentPageIndex);
          });
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
          setState(() {
            _currentPageIndex = groups[currentGroupIdx - 1][0];
            _pageController.jumpToPage(currentGroupIdx - 1);
            _precacheAdjacentPages(_currentPageIndex);
          });
        } else {
          _navigateToPrevChapter();
        }
      } else {
        if (_currentPageIndex > 0) {
          setState(() {
            _currentPageIndex--;
            _pageController.jumpToPage(_currentPageIndex);
            _precacheAdjacentPages(_currentPageIndex);
          });
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
            return Center(
              child: _buildColorFilteredWidget(
                CachedNetworkImage(
                  imageUrl: _pageUrls[index],
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Container(
                    height: 500,
                    color: Colors.black12,
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 300,
                    color: Colors.white10,
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.white30, size: 40),
                    ),
                  ),
                ),
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
            setState(() {
              _currentPageIndex = groups[index][0];
              _precacheAdjacentPages(_currentPageIndex);
            });
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
                      CachedNetworkImage(
                        imageUrl: _pageUrls[leftIdx],
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C))),
                        ),
                      ),
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
                      CachedNetworkImage(
                        imageUrl: _pageUrls[rightIdx],
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C))),
                        ),
                      ),
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
                      CachedNetworkImage(
                        imageUrl: _pageUrls[group[0]],
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C))),
                        ),
                      ),
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
          setState(() {
            _currentPageIndex = index;
            _precacheAdjacentPages(index);
          });
        },
        itemBuilder: (context, index) {
          return Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: _buildColorFilteredWidget(
                CachedNetworkImage(
                  imageUrl: _pageUrls[index],
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
                    ),
                  ),
                  errorWidget: (context, url, error) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.white30, size: 40),
                  ),
                ),
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
                      setState(() {
                        final idx = val.toInt();
                        if (isDouble) {
                          _currentPageIndex = _getDoublePageIndices()[idx][0];
                        } else {
                          _currentPageIndex = idx;
                        }
                        _pageController.jumpToPage(idx);
                        _precacheAdjacentPages(_currentPageIndex);
                      });
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
