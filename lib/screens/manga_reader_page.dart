import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/notification_service.dart';
import '../services/suwayomi_service.dart';
import '../state/navigation_state.dart';
import '../state/library_state.dart';
import '../state/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:window_manager/window_manager.dart';
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

class _MangaReaderPageState extends State<MangaReaderPage> with SingleTickerProviderStateMixin {
  final SuwayomiService _suwayomiService = SuwayomiService();
  bool _isLoading = true;
  bool _isChangingChapter = false;
  String? _errorMessage;

  List<String> _pageUrls = [];
  String _readingFormat = 'webtoon'; // 'webtoon', 'paging_ltr', 'paging_rtl', 'paging_double'
  String _colorFilterMode = 'none'; // 'none', 'grayscale', 'sepia', 'warm', 'inverted', 'boost'
  bool _continuousReading = true; // Mihon-style seamless auto-read toggle
  String _lastTransitionMessage = '';
  int _currentPageIndex = 0;
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(0);
  MangaPageLoader? _pageLoader;
  // Actual pixel heights reported by each rendered webtoon page widget.
  // Used by _onScroll for ground-truth page detection without any estimation.
  final List<double?> _pageRenderedHeights = [];
  // Debounce timer — all disk I/O (SharedPrefs, SQLite) is batched and only
  // written 500 ms after the user stops changing pages, preventing frame drops.
  Timer? _saveDebounce;
  
  late PageController _pageController;
  late ScrollController _scrollController;
  bool _showOverlay = true;

  late String _currentChapterId;
  late int _currentChapterNumber;
  
  late AnimationController _webtoonScaleController;
  late ScrollController _webtoonHorizontalScrollController;
  late TransformationController _webtoonTransformationController;
  Animation<Matrix4>? _webtoonAnimation;
  TapDownDetails? _webtoonDoubleTapDetails;
  bool _isPageZoomed = false;

  @override
  void initState() {
    super.initState();
    // Expand Flutter ImageCache to 256MB to prevent image eviction blackouts during scrolling
    PaintingBinding.instance.imageCache.maximumSizeBytes = 256 * 1024 * 1024;
    PaintingBinding.instance.imageCache.maximumSize = 100;

    // Hide status bar and system navigation bar for full screen reading
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    _currentChapterId = widget.chapterId;
    _currentChapterNumber = widget.chapterNumber;
    _pageController = PageController();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    _webtoonHorizontalScrollController = ScrollController();
    _webtoonTransformationController = TransformationController();
    _webtoonScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (mounted && _webtoonAnimation != null) {
          _webtoonTransformationController.value = _webtoonAnimation!.value;
        }
      });

    _loadSettings().then((_) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) {
          _loadPages();
          _updateLibraryProgress();
        }
      });
    });
  }

  @override
  void dispose() {
    // Restore status bar and navigation bar when leaving
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    
    // Exit fullscreen if windowManager is active
    windowManager.isFullScreen().then((isFS) {
      if (isFS) {
        windowManager.setFullScreen(false);
      }
    });

    _scrollController.removeListener(_onScroll);
    _pageLoader?.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    _webtoonHorizontalScrollController.dispose();
    _webtoonTransformationController.dispose();
    _webtoonScaleController.dispose();
    _saveDebounce?.cancel();
    _currentPageNotifier.dispose();
    super.dispose();
  }

  double _getAverageWebtoonAspectRatio() {
    double loadedAspectSum = 0.0;
    int loadedCount = 0;
    if (_pageLoader != null) {
      for (int i = 0; i < _pageUrls.length; i++) {
        final dims = _pageLoader?.pageDimensions[i];
        if (dims != null && dims.height > 0) {
          loadedAspectSum += (dims.width / dims.height);
          loadedCount++;
        }
      }
    }
    if (loadedCount > 0) {
      return loadedAspectSum / loadedCount;
    }
    return _readingFormat == 'webtoon' ? 0.4 : (2 / 3);
  }

  double _lastScrollOffset = 0.0;
  bool _hasMarkedReadCurrentChapter = false;

  void _onScroll() {
    if (_readingFormat != 'webtoon') return;
    if (!_scrollController.hasClients || _pageUrls.isEmpty) return;

    final double offset = _scrollController.offset;

    // Auto-hide overlay on scroll down
    if (offset > 50.0 && _showOverlay && offset > _lastScrollOffset + 10.0) {
      setState(() => _showOverlay = false);
    }
    _lastScrollOffset = offset;

    // Auto-mark read ONCE when user scrolls past 85% of Webtoon content
    final double maxScroll = _scrollController.position.maxScrollExtent;
    if (!_hasMarkedReadCurrentChapter && maxScroll > 0 && offset >= maxScroll * 0.85) {
      _hasMarkedReadCurrentChapter = true;
      _scheduleSave(_currentPageIndex, isLastPage: true);
    }

    // Auto continuous read: When scrolling past end of chapter (maxScroll + 50px), auto-load next chapter if enabled
    if (_continuousReading && !_isChangingChapter && maxScroll > 100 && offset >= maxScroll + 50.0) {
      _navigateToNextChapter();
    }

    // Use real rendered heights when available; fall back to estimated for unrendered pages.
    // This ensures the page counter never jumps when images load and change total height.
    final double width = MediaQuery.of(context).size.width.clamp(0.0, 800.0);
    final double defaultAspect = _getAverageWebtoonAspectRatio();

    double cumulativeHeight = 40.0; // top ListView padding
    int visibleIndex = _pageUrls.length - 1;

    for (int i = 0; i < _pageUrls.length; i++) {
      // Prefer the actual measured height from the widget; fall back to aspect-ratio estimate
      final double pageHeight;
      final double? rendered = i < _pageRenderedHeights.length ? _pageRenderedHeights[i] : null;
      if (rendered != null && rendered > 0) {
        pageHeight = rendered;
      } else {
        final dims = _pageLoader?.pageDimensions[i];
        final double aspectRatio = (dims != null && dims.height > 0)
            ? (dims.width / dims.height)
            : defaultAspect;
        pageHeight = width / aspectRatio;
      }

      // The page whose top half contains the viewport center is the current page
      if (offset < cumulativeHeight + pageHeight * 0.5) {
        visibleIndex = i;
        break;
      }
      cumulativeHeight += pageHeight;
    }

    if (visibleIndex != _currentPageIndex) {
      _updatePageIndex(visibleIndex);
    }
  }

  SharedPreferences? _prefs;

  /// Debounced save: batches SharedPrefs + SQLite writes into a single
  /// operation that fires 500 ms after the last page change. This prevents
  /// disk I/O on every scroll frame from blocking the UI thread.
  void _scheduleSave(int index, {bool isLastPage = false}) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      _flushSave(index, isLastPage: isLastPage);
    });
  }

  Future<void> _flushSave(int index, {bool isLastPage = false}) async {
    // 1. Save current page position
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setInt('manga_chapter_page_$_currentChapterId', index);

    // 2. Add to history (only once per chapter open, or when chapter changes)
    PlayerState.addMangaToHistory(widget.mangaId, _currentChapterNumber, widget.mangaTitle);

    // 3. Mark chapter read on last page / 85%+ completion
    if (isLastPage) {
      final int parsedMangaId = int.tryParse(widget.mangaId) ?? 0;
      if (parsedMangaId != 0) {
        LibraryState().setChapterReadStatus(parsedMangaId, _currentChapterId, true);
      }
    }
  }

  void _updatePageIndex(int index, {bool jump = false}) {
    if (index < 0 || index >= _pageUrls.length) return;
    if (_currentPageIndex == index && !jump) return;
    
    _currentPageIndex = index;
    _currentPageNotifier.value = index;
    
    _pageLoader?.setPriorityIndex(index);
    _precacheUpcomingPages(index);

    final bool isLastPage = index >= _pageUrls.length - 1 && _pageUrls.isNotEmpty;
    _scheduleSave(index, isLastPage: isLastPage);

    if (jump) {
      if (_readingFormat != 'webtoon' && _pageController.hasClients) {
        if (_readingFormat == 'paging_double') {
          final groups = _getDoublePageIndices();
          final groupIdx = groups.indexWhere((g) => g.contains(index));
          if (groupIdx != -1) {
            _pageController.jumpToPage(groupIdx);
          }
        } else {
          _pageController.jumpToPage(index);
        }
      } else if (_readingFormat == 'webtoon') {
        _scrollToSavedPageWebtoon();
      }
    }
  }

  void _precacheUpcomingPages(int currentIndex) {
    if (!mounted || _pageUrls.isEmpty) return;
    for (int i = 1; i <= 3; i++) {
      final targetIndex = currentIndex + i;
      if (targetIndex < _pageUrls.length) {
        final url = _pageUrls[targetIndex];
        if (url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'))) {
          precacheImage(NetworkImage(url), context).catchError((_) {});
        }
      }
    }
  }


  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _readingFormat = prefs.getString('manga_reading_format') ?? 'webtoon';
        _colorFilterMode = prefs.getString('manga_color_filter_mode') ?? 'none';
        _continuousReading = prefs.getBool('manga_continuous_reading') ?? true;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manga_reading_format', _readingFormat);
    await prefs.setString('manga_color_filter_mode', _colorFilterMode);
    await prefs.setBool('manga_continuous_reading', _continuousReading);
  }

  Future<void> _loadPages() async {
    _hasMarkedReadCurrentChapter = false;
    // Immediately cancel and dispose the old downloader to free sockets and prevent background interference
    _pageLoader?.dispose();
    _pageLoader = null;

    final int parsedId = int.tryParse(_currentChapterId) ?? 0;
    if (parsedId == 0) {
      if (mounted) {
        setState(() {
          _errorMessage = "Invalid Chapter ID";
          _isLoading = false;
          _isChangingChapter = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        if (_pageUrls.isEmpty) {
          _isLoading = true;
        } else {
          _isChangingChapter = true;
        }
        _errorMessage = null;
      });
    }

    try {
      // Check if this chapter is available offline (downloaded)
      final int? parsedMangaId = int.tryParse(widget.mangaId);
      List<String>? localUrls;
      if (parsedMangaId != null) {
        final localDir = LibraryState().getChapterLocalDir(parsedMangaId, _currentChapterId);
        if (localDir != null) {
          final dir = Directory(localDir);
          if (await dir.exists()) {
            final files = await dir.list().where((e) => e is File && (e.path.endsWith('.jpg') || e.path.endsWith('.png') || e.path.endsWith('.webp'))).toList();
            files.sort((a, b) => a.path.compareTo(b.path));
            if (files.isNotEmpty) {
              localUrls = files.map((f) => Uri.file(f.path).toString()).toList();
            }
          }
        }
      }

      final urls = localUrls ?? await _suwayomiService.getChapterPages(parsedId, mangaId: parsedMangaId);
      if (urls.isEmpty) {
        throw Exception("Failed to retrieve pages for this chapter. The source may be down or rate-limiting.");
      }

      final prefs = await SharedPreferences.getInstance();
      int savedPage = prefs.getInt('manga_chapter_page_$_currentChapterId') ?? 0;
      if (savedPage >= urls.length - 1) {
        savedPage = 0;
      }

      if (mounted) {
        setState(() {
          _pageUrls = urls;
          _pageRenderedHeights
            ..clear()
            ..addAll(List.filled(urls.length, null));
          _isLoading = false;
          _isChangingChapter = false;
          _currentPageIndex = savedPage < urls.length ? savedPage : 0;
          
          try {
            _pageController.dispose();
          } catch (_) {}

          int initPage = _currentPageIndex;
          if (_readingFormat == 'paging_double') {
            final groups = _getDoublePageIndices();
            final groupIdx = groups.indexWhere((g) => g.contains(_currentPageIndex));
            initPage = groupIdx != -1 ? groupIdx : 0;
          }
          _pageController = PageController(initialPage: initPage);

          _pageLoader?.dispose();
          _pageLoader = MangaPageLoader(
            chapterId: parsedId,
            urls: urls,
            onPageDownloaded: (index) {
              // No full-screen setState here to prevent overlay flickering/showing
            },
          );
        });

        // Jump or scroll to the saved page on startup (only for webtoon)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_readingFormat == 'webtoon' && _scrollController.hasClients) {
            if (_currentPageIndex > 0) {
              _scrollToSavedPageWebtoon();
            } else {
              _scrollController.jumpTo(0.0);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _pageUrls.isEmpty ? e.toString() : null;
          _isLoading = false;
          _isChangingChapter = false;
        });
        if (_pageUrls.isNotEmpty) {
          NotificationService().show(context, 'Failed to load chapter: ${e.toString().replaceAll('Exception: ', '')}');
        }
      }
    }
  }

  double _getWebtoonScrollOffsetForIndex(int index) {
    final double width = MediaQuery.of(context).size.width.clamp(0.0, 800.0);
    final double defaultAspect = _getAverageWebtoonAspectRatio();
    double cumulativeHeight = 40.0; // matching top padding
    for (int i = 0; i < index; i++) {
      final dims = _pageLoader?.pageDimensions[i];
      final double aspectRatio = (dims != null && dims.height > 0)
          ? (dims.width / dims.height)
          : defaultAspect;
      cumulativeHeight += width / aspectRatio;
    }
    return cumulativeHeight;
  }

  void _scrollToSavedPageWebtoon() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_getWebtoonScrollOffsetForIndex(_currentPageIndex));
  }




  void _updateLibraryProgress() {
    // Record history entry when opening/reading chapter
    PlayerState.addMangaToHistory(widget.mangaId, _currentChapterNumber, widget.mangaTitle);
  }

  void _nextPage() {
    if (_readingFormat == 'webtoon') {
      final double target = (_scrollController.offset + 800).clamp(
        0.0, _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
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
      final double target = (_scrollController.offset - 800).clamp(
        0.0, _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
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

  int _parseChapterNumber(dynamic chapter) {
    final rawNum = chapter['chapterNumber'];
    if (rawNum != null) {
      if (rawNum is num && rawNum >= 0) return rawNum.toInt();
      final double? parsed = double.tryParse(rawNum.toString());
      if (parsed != null && parsed >= 0) return parsed.toInt();
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

  void _navigateToNextChapter() {
    final chapters = widget.chapters;
    final currentIdx = chapters.indexWhere((c) => c['id']?.toString() == _currentChapterId);
    if (currentIdx == -1) return;

    if (chapters.isEmpty) {
      NotificationService().show(context, 'No chapters available.');
      return;
    }

    final firstNum = _parseChapterNumber(chapters.first);
    final lastNum = _parseChapterNumber(chapters.last);
    final bool isDescending = firstNum >= lastNum;

    final int targetIdx = isDescending ? currentIdx - 1 : currentIdx + 1;

    if (targetIdx >= 0 && targetIdx < chapters.length) {
      final targetChapter = chapters[targetIdx];
      final String? targetId = targetChapter['id']?.toString();
      final int targetNum = _parseChapterNumber(targetChapter);
      
      if (targetId != null) {
        final int prevNum = _currentChapterNumber;
        _lastTransitionMessage = 'Chapter $prevNum Ended • Loading Chapter $targetNum...';
        setState(() {
          _currentChapterId = targetId;
          _currentChapterNumber = targetNum;
          _currentPageIndex = 0;
        });
        _loadPages();
        _updateLibraryProgress();
        NotificationService().show(context, 'Chapter $prevNum Ended → Reading Chapter $targetNum');
      }
    } else {
      NotificationService().show(context, 'You have reached the latest chapter.');
    }
  }

  void _navigateToPrevChapter() {
    final chapters = widget.chapters;
    final currentIdx = chapters.indexWhere((c) => c['id']?.toString() == _currentChapterId);
    if (currentIdx == -1) return;

    if (chapters.isEmpty) {
      NotificationService().show(context, 'No chapters available.');
      return;
    }

    final firstNum = _parseChapterNumber(chapters.first);
    final lastNum = _parseChapterNumber(chapters.last);
    final bool isDescending = firstNum >= lastNum;

    final int targetIdx = isDescending ? currentIdx + 1 : currentIdx - 1;

    if (targetIdx >= 0 && targetIdx < chapters.length) {
      final targetChapter = chapters[targetIdx];
      final String? targetId = targetChapter['id']?.toString();
      final int targetNum = _parseChapterNumber(targetChapter);
      
      if (targetId != null) {
        final int prevNum = _currentChapterNumber;
        _lastTransitionMessage = 'Loading Chapter $targetNum...';
        setState(() {
          _currentChapterId = targetId;
          _currentChapterNumber = targetNum;
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
                      _scrollToSavedPageWebtoon();
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
                        'Chapter Transitions',
                        style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                      ),
                    ),
                    SwitchListTile(
                      value: _continuousReading,
                      activeColor: const Color(0xFFFF9F1C),
                      secondary: const Icon(Icons.auto_stories, color: Color(0xFFFF9F1C)),
                      title: const Text(
                        'Seamless Continuous Reading (Mihon)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Outfit', fontSize: 14),
                      ),
                      subtitle: Text(
                        _continuousReading
                            ? 'Auto-loads next chapter on scroll without clicking next'
                            : 'Stops at End-of-Chapter card (requires clicking next button)',
                        style: const TextStyle(color: Colors.white54, fontFamily: 'Outfit', fontSize: 12),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _continuousReading = val;
                        });
                        setSheetState(() {});
                        _saveSettings();
                      },
                    ),

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
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.space) {
          if (_readingFormat == 'paging_rtl') {
            _prevPage();
          } else {
            _nextPage();
          }
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.pageUp) {
          if (_readingFormat == 'paging_rtl') {
            _nextPage();
          } else {
            _prevPage();
          }
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.arrowDown) {
          _nextPage();
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.arrowUp) {
          _prevPage();
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
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

          // Floating Smooth Chapter Switch Indicator
          if (_isChangingChapter)
            Positioned(
              top: _showOverlay ? 75.0 : 35.0,
              left: 20.0,
              right: 20.0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141417).withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(20.0),
                    border: Border.all(color: const Color(0xFFFF9F1C), width: 1.2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black87,
                        blurRadius: 16,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2.0, color: Color(0xFFFF9F1C)),
                      ),
                      const SizedBox(width: 10.0),
                      Text(
                        _lastTransitionMessage.isNotEmpty ? _lastTransitionMessage : 'Loading next chapter...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

          // Page Number Indicator (e.g. 4/27) floating at bottom center
          if (!_isLoading && _errorMessage == null && _pageUrls.isNotEmpty)
            Positioned(
              bottom: _showOverlay ? 110.0 : 20.0,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _showPageJumpBottomSheet,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: ValueListenableBuilder<int>(
                      valueListenable: _currentPageNotifier,
                      builder: (context, currentPage, _) {
                        final bool isDouble = _readingFormat == 'paging_double';
                        String pageText;
                        if (isDouble) {
                          final groups = _getDoublePageIndices();
                          final groupIdx = groups.indexWhere((g) => g.contains(currentPage));
                          if (groupIdx != -1) {
                            final group = groups[groupIdx];
                            if (group.length == 2) {
                              pageText = '${group[0] + 1}-${group[1] + 1}/${_pageUrls.length}';
                            } else {
                              pageText = '${group[0] + 1}/${_pageUrls.length}';
                            }
                          } else {
                            pageText = '${currentPage + 1}/${_pageUrls.length}';
                          }
                        } else {
                          pageText = '${currentPage + 1}/${_pageUrls.length}';
                        }
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              pageText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4.0),
                            const Icon(Icons.touch_app_outlined, color: Color(0xFFFF9F1C), size: 13.0),
                          ],
                        );
                      }
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      ), // Scaffold
    ); // Focus
  } // build

  void _showPageJumpBottomSheet() {
    final double screenWidth = MediaQuery.of(context).size.width;
    const double itemWidth = 55.0;
    const double itemMargin = 8.0;
    const double totalItemWidth = itemWidth + itemMargin; // 63.0

    final int startIdx = _currentPageIndex.clamp(0, max(0, _pageUrls.length - 1)).toInt();
    final double initialOffset = max(0.0, (startIdx * totalItemWidth) - (screenWidth / 2) + (itemWidth / 2));
    final ScrollController listScrollController = ScrollController(
      initialScrollOffset: initialOffset,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141417),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (ctx) {
        double tempPage = (startIdx + 1).toDouble();
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36.0,
                    height: 4.0,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Jump to Page',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                      Text(
                        'Page ${tempPage.toInt()} of ${_pageUrls.length}',
                        style: const TextStyle(
                          color: Color(0xFFFF9F1C),
                          fontSize: 13.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12.0),
                  Slider(
                    value: tempPage,
                    min: 1.0,
                    max: _pageUrls.length.toDouble().clamp(1.0, 999.0),
                    divisions: _pageUrls.length > 1 ? _pageUrls.length - 1 : 1,
                    activeColor: const Color(0xFFFF9F1C),
                    inactiveColor: Colors.white10,
                    onChanged: (val) {
                      setModalState(() {
                        tempPage = val;
                      });
                      final newIdx = val.toInt() - 1;
                      if (listScrollController.hasClients) {
                        final newOffset = max(0.0, (newIdx * totalItemWidth) - (screenWidth / 2) + (itemWidth / 2));
                        listScrollController.jumpTo(newOffset.clamp(0.0, listScrollController.position.maxScrollExtent));
                      }
                      _updatePageIndex(newIdx, jump: true);
                    },
                  ),
                  const SizedBox(height: 12.0),
                  SizedBox(
                    height: 90.0,
                    child: ListView.builder(
                      controller: listScrollController,
                      scrollDirection: Axis.horizontal,
                      itemCount: _pageUrls.length,
                      itemBuilder: (context, idx) {
                        final bool isSelected = idx == (tempPage.toInt() - 1);
                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              tempPage = (idx + 1).toDouble();
                            });
                            _updatePageIndex(idx, jump: true);
                            Navigator.pop(ctx);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 8.0),
                            width: 55.0,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFFF9F1C).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(
                                color: isSelected ? const Color(0xFFFF9F1C) : Colors.white10,
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFFFF9F1C) : Colors.white70,
                                  fontSize: 13.0,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12.0),
                ],
              ),
            );
          },
        );
      },
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

  Widget _buildPageImage(int index, {bool isWebtoon = false}) {
    return ValueListenableBuilder<int>(
      valueListenable: _pageLoader?.onPageDownloadedNotifier ?? ValueNotifier(-1),
      builder: (context, downloadedIdx, _) {
        final localPath = _pageLoader?.localPaths[index];
        final isDownloading = _pageLoader?.isDownloading(index) ?? false;
        final double? progress = _pageLoader?.getProgress(index);

        return LayoutBuilder(
          key: ValueKey('page_${_currentChapterId}_$index'),
          builder: (context, constraints) {
            final double w = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.of(context).size.width;
            final double defaultAspect = _getAverageWebtoonAspectRatio();
            final dims = _pageLoader?.pageDimensions[index];
            final double aspectRatio = (dims != null && dims.height > 0) ? (dims.width / dims.height) : defaultAspect;

            Widget content;
            if (localPath != null) {
              content = _WebtoonImageWithSize(
                file: File(localPath),
                index: index,
                currentChapterId: _currentChapterId,
                isWebtoon: isWebtoon,
                maxWidth: w,
                pageLoader: _pageLoader,
                onDimensionResolved: () {},
                errorBuilder: (context, error, stackTrace) => _buildPageError(index),
              );
            } else {
              final double h = w / aspectRatio;
              content = _MihonPagePlaceholder(
                width: w,
                height: isWebtoon ? h : null,
                pageNumber: index + 1,
                isDownloading: isDownloading,
                progress: progress,
              );
            }

            if (isWebtoon) {
              return SizedBox(
                key: ValueKey('sizedbox_$index'),
                width: w,
                child: content,
              );
            }

            return SizedBox(
              key: ValueKey('sizedbox_$index'),
              width: w,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: content,
              ),
            );
          },
        );
      },
    );
  }


  Widget _buildPageError(int index) {
    return Container(
      constraints: const BoxConstraints(minHeight: 300),
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_outlined, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(
            'Failed to load page ${index + 1}',
            style: const TextStyle(color: Colors.white38, fontFamily: 'Outfit', fontSize: 12),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              _pageLoader?.retryPage(index);
              setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Retry', style: TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }


  void _handleWebtoonDoubleTapDown(TapDownDetails details) {
    _webtoonDoubleTapDetails = details;
  }

  void _handleWebtoonDoubleTap() {
    if (_webtoonDoubleTapDetails == null) return;
    final focalPoint = _webtoonDoubleTapDetails!.localPosition;
    
    final currentScale = _webtoonTransformationController.value.getMaxScaleOnAxis();
    
    _webtoonScaleController.stop();
    
    Matrix4 target;
    if (currentScale > 1.05) {
      target = Matrix4.identity();
    } else {
      // Zoom to 2.5x centered on the double-tap location
      final double scale = 2.5;
      final xTranslation = _webtoonTransformationController.value.storage[12];
      final yTranslation = _webtoonTransformationController.value.storage[13];
      final focalPointSceneX = (focalPoint.dx - xTranslation) / currentScale;
      final focalPointSceneY = (focalPoint.dy - yTranslation) / currentScale;
      
      target = Matrix4.identity()
        ..translate(
          focalPoint.dx - focalPointSceneX * scale,
          focalPoint.dy - focalPointSceneY * scale,
        )
        ..scale(scale);
    }
    
    _webtoonAnimation = Matrix4Tween(
      begin: _webtoonTransformationController.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: _webtoonScaleController,
      curve: Curves.easeOutCubic,
    ));
    
    _webtoonScaleController.forward(from: 0.0);
  }

  Widget _buildWebtoonViewer() {
    return GestureDetector(
      onTap: () {
        setState(() => _showOverlay = !_showOverlay);
      },
      onDoubleTapDown: _handleWebtoonDoubleTapDown,
      onDoubleTap: _handleWebtoonDoubleTap,
      child: InteractiveViewer(
        transformationController: _webtoonTransformationController,
        minScale: 1.0,
        maxScale: 4.0,
        panEnabled: true,
        scaleEnabled: true,
        onInteractionEnd: (_) {
          // Snap back to 1x if barely zoomed
          if (_webtoonTransformationController.value.getMaxScaleOnAxis() < 1.05) {
            _webtoonScaleController.stop();
            _webtoonAnimation = Matrix4Tween(
              begin: _webtoonTransformationController.value,
              end: Matrix4.identity(),
            ).animate(CurvedAnimation(
              parent: _webtoonScaleController,
              curve: Curves.elasticOut,
            ));
            _webtoonScaleController.forward(from: 0.0);
          }
        },
        child: ListView.builder(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          itemCount: _pageUrls.length + 1,
          cacheExtent: 1200.0,
          itemBuilder: (context, index) {
            if (index == _pageUrls.length) {
              return RepaintBoundary(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800.0),
                    child: _buildEndOfChapterCard(),
                  ),
                ),
              );
            }
            _pageLoader?.setPriorityIndex(index);
            return _WebtoonPageHeightReporter(
              index: index,
              onHeightChanged: (h) {
                if (index < _pageRenderedHeights.length && _pageRenderedHeights[index] != h) {
                  _pageRenderedHeights[index] = h;
                  _onScroll();
                }
              },
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800.0),
                  child: _buildColorFilteredWidget(
                    _buildPageImage(index, isWebtoon: true),
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
        physics: _isPageZoomed ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
        itemCount: groups.length,
        reverse: isRtl,
        onPageChanged: (index) {
          setState(() {
            _isPageZoomed = false;
          });
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
                child: _ZoomablePageImage(
                  onZoomChanged: (zoomed) {
                    setState(() {
                      _isPageZoomed = zoomed;
                    });
                  },
                  child: Center(
                    child: _buildColorFilteredWidget(
                      _buildPageImage(leftIdx),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: _ZoomablePageImage(
                  onZoomChanged: (zoomed) {
                    setState(() {
                      _isPageZoomed = zoomed;
                    });
                  },
                  child: Center(
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
                child: _ZoomablePageImage(
                  onZoomChanged: (zoomed) {
                    setState(() {
                      _isPageZoomed = zoomed;
                    });
                  },
                  child: Center(
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
        physics: _isPageZoomed ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
        itemCount: _pageUrls.length,
        reverse: isRtl,
        onPageChanged: (index) {
          setState(() {
            _isPageZoomed = false;
          });
          _updatePageIndex(index);
        },
        itemBuilder: (context, index) {
          return _ZoomablePageImage(
            key: ValueKey('zoom_${_currentChapterId}_$index'),
            onZoomChanged: (zoomed) {
              setState(() {
                _isPageZoomed = zoomed;
              });
            },
            child: Center(
              child: _buildColorFilteredWidget(
                _buildPageImage(index),
              ),
            ),
          );
        },
      );
    }
  }

  Widget _buildEndOfChapterCard() {
    final int currentIdx = widget.chapters.indexWhere((c) => c['id']?.toString() == _currentChapterId);
    final bool firstNumIsLarger = (widget.chapters.isNotEmpty &&
        _parseChapterNumber(widget.chapters.first) >= _parseChapterNumber(widget.chapters.last));
    final int targetIdx = firstNumIsLarger ? currentIdx - 1 : currentIdx + 1;
    final bool hasNext = targetIdx >= 0 && targetIdx < widget.chapters.length;
    final nextChap = hasNext ? widget.chapters[targetIdx] : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: Colors.white12, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFFFF9F1C), size: 22.0),
              const SizedBox(width: 8.0),
              Text(
                'Finished Chapter $_currentChapterNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Text(
            widget.mangaTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 12.0, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 16.0),
          if (hasNext && nextChap != null) ...[
            ElevatedButton.icon(
              onPressed: _isChangingChapter ? null : _navigateToNextChapter,
              icon: _isChangingChapter
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.black),
                    )
                  : const Icon(Icons.arrow_forward_rounded, size: 18.0),
              label: Text(_isChangingChapter
                  ? 'Loading Next Chapter...'
                  : 'Next Chapter (${nextChap['chapterNumber'] ?? (targetIdx + 1)})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9F1C),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(44.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                textStyle: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: const Text(
                'You have reached the latest chapter!',
                style: TextStyle(color: Colors.white70, fontSize: 12.5, fontFamily: 'Outfit'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _currentChapterDisplayTitle {
    final currentChapter = widget.chapters.firstWhere(
      (c) => c['id']?.toString() == _currentChapterId,
      orElse: () => null,
    );
    if (currentChapter != null) {
      final name = (currentChapter['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }
    if (_currentChapterNumber > 0) {
      return 'Chapter $_currentChapterNumber';
    }
    return 'Chapter';
  }

  void _showChaptersListBottomSheet() {
    final int currentChIdx = max(0, widget.chapters.indexWhere((ch) => (ch['id']?.toString() ?? '') == _currentChapterId));
    final double sheetHeight = MediaQuery.of(context).size.height * 0.75;
    final double initialChOffset = max(0.0, (currentChIdx * 48.0) - (sheetHeight / 2) + 24.0);
    final ScrollController chListController = ScrollController(initialScrollOffset: initialChOffset);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141417),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (ctx) {
        String searchQuery = '';
        final parsedMangaId = int.tryParse(widget.mangaId) ?? 0;
        final readIds = LibraryState().getReadChapterIds(parsedMangaId).toSet();

        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = widget.chapters.where((ch) {
              final name = (ch['name'] ?? '').toString().toLowerCase();
              final numStr = (ch['chapterNumber'] ?? '').toString();
              return searchQuery.isEmpty ||
                  name.contains(searchQuery.toLowerCase()) ||
                  numStr.contains(searchQuery);
            }).toList();

            return Container(
              height: sheetHeight,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                children: [
                  Container(
                    width: 36.0,
                    height: 4.0,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Chapters List',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                      Text(
                        '${widget.chapters.length} Chapters',
                        style: const TextStyle(
                          color: Color(0xFFFF9F1C),
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12.0),
                  TextField(
                    onChanged: (val) => setModalState(() => searchQuery = val),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Search chapters...',
                      hintStyle: const TextStyle(color: Colors.white38, fontFamily: 'Outfit', fontSize: 13.5),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No matching chapters found.',
                              style: TextStyle(color: Colors.white38, fontFamily: 'Outfit'),
                            ),
                          )
                        : ListView.builder(
                            controller: chListController,
                            itemCount: filtered.length,
                            itemBuilder: (context, idx) {
                              final ch = filtered[idx];
                              final chId = ch['id']?.toString() ?? '';
                              final isCurrent = chId == _currentChapterId;
                              final isRead = readIds.contains(chId);
                              final chNum = _parseChapterNumber(ch);
                              final chName = (ch['name'] ?? 'Chapter $chNum').toString().trim();

                              final savedPage = _prefs?.getInt('manga_chapter_page_$chId');
                              final bool isHalfRead = !isRead && !isCurrent && savedPage != null && savedPage > 0;

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 2.0),
                                child: Material(
                                  color: isCurrent
                                      ? const Color(0xFFFF9F1C).withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(8.0),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8.0),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      if (!isCurrent) {
                                        setState(() {
                                          _currentChapterId = chId;
                                          _currentChapterNumber = chNum;
                                          _isLoading = true;
                                          _pageUrls = [];
                                          _currentPageIndex = 0;
                                        });
                                        _loadPages();
                                        _updateLibraryProgress();
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8.0),
                                        border: Border.all(
                                          color: isCurrent
                                              ? const Color(0xFFFF9F1C).withValues(alpha: 0.4)
                                              : Colors.white10,
                                          width: isCurrent ? 1.5 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isCurrent
                                                ? Icons.play_circle_fill_rounded
                                                : (isRead ? Icons.check_circle_rounded : Icons.radio_button_unchecked),
                                            color: isCurrent
                                                ? const Color(0xFFFF9F1C)
                                                : (isRead ? Colors.greenAccent : Colors.white30),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12.0),
                                          Expanded(
                                            child: Text(
                                              chName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isCurrent
                                                    ? const Color(0xFFFF9F1C)
                                                    : (isRead ? Colors.white54 : Colors.white),
                                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                                fontFamily: 'Outfit',
                                                fontSize: 13.5,
                                              ),
                                            ),
                                          ),
                                          if (isCurrent)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFF9F1C),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Text(
                                                'READING',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'Outfit',
                                                ),
                                              ),
                                            )
                                          else if (isHalfRead)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFF9F1C).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFFF9F1C).withValues(alpha: 0.4), width: 0.8),
                                              ),
                                              child: Text(
                                                'Page ${savedPage + 1}',
                                                style: const TextStyle(
                                                  color: Color(0xFFFF9F1C),
                                                  fontSize: 10.0,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'Outfit',
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTopOverlay() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F11).withValues(alpha: 0.95),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 8.0, offset: Offset(0, 2)),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: MediaQuery.of(context).padding.top + 8.0,
        bottom: 12.0,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24.0),
            tooltip: 'Back to details',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                  _currentChapterDisplayTitle,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12.0,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.format_list_bulleted_rounded, color: Colors.white, size: 22.0),
            tooltip: 'Chapters List',
            onPressed: _showChaptersListBottomSheet,
          ),
          if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ...[
            FutureBuilder<bool>(
              future: windowManager.isFullScreen(),
              builder: (context, snapshot) {
                final isFS = snapshot.data ?? false;
                return IconButton(
                  icon: Icon(isFS ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white, size: 24.0),
                  tooltip: isFS ? 'Exit Full Screen' : 'Full Screen',
                  onPressed: () async {
                    final nextFS = !isFS;
                    await windowManager.setFullScreen(nextFS);
                    setState(() {});
                  },
                );
              }
            ),
          ],
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
          // Slider navigation
          if (_pageUrls.isNotEmpty) ...[
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
                          _scrollController.jumpTo(_getWebtoonScrollOffsetForIndex(targetPageIdx));
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
                  GestureDetector(
                    onTap: _showChaptersListBottomSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160.0),
                            child: Text(
                              _currentChapterDisplayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 13.0),
                            ),
                          ),
                          const SizedBox(width: 4.0),
                          const Icon(Icons.format_list_bulleted_rounded, color: Color(0xFFFF9F1C), size: 14.0),
                        ],
                      ),
                    ),
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
  final void Function(int index) onPageDownloaded;
  final ValueNotifier<int> onPageDownloadedNotifier = ValueNotifier<int>(-1);
  
  final List<String?> localPaths;
  final List<ImageDimension?> pageDimensions;
  final List<bool> _downloading;   // which indices are currently in-flight
  final List<double?> _progress;   // 0.0–1.0 or null if not started
  final List<int> _failedCounts;   // track failed download attempts
  int _priorityIndex = 0;
  bool _isDisposed = false;
  
  // Track active clients and operations by index to allow concurrent downloads
  final Map<int, CancelableOperation<void>> _activeOps = {};
  final Map<int, http.Client> _activeClients = {};
  
  MangaPageLoader({
    required this.chapterId,
    required this.urls,
    required this.onPageDownloaded,
  })  : localPaths = List<String?>.filled(urls.length, null),
        pageDimensions = List<ImageDimension?>.filled(urls.length, null),
        _downloading = List<bool>.filled(urls.length, false),
        _progress = List<double?>.filled(urls.length, null),
        _failedCounts = List<int>.filled(urls.length, 0) {
    // Start 4 concurrent download loops for parallel pre-fetching (Mihon priority)
    _startDownloadLoop();
    _startDownloadLoop();
    _startDownloadLoop();
    _startDownloadLoop();
  }

  bool isDownloading(int index) => index >= 0 && index < _downloading.length && _downloading[index];
  double? getProgress(int index) => index >= 0 && index < _progress.length ? _progress[index] : null;

  void retryPage(int index) {
    if (index < 0 || index >= urls.length) return;
    localPaths[index] = null;
    pageDimensions[index] = null;
    _downloading[index] = false;
    _progress[index] = null;
    _failedCounts[index] = 0; // reset failures on manual retry
    _priorityIndex = index;
    _cancelPage(index);
  }

  void setPriorityIndex(int idx) {
    if (idx < 0 || idx >= urls.length) return;
    if (_priorityIndex == idx) return;
    
    _priorityIndex = idx;

    // Mihon optimization: If the focused page is not downloaded yet, cancel in-flight tasks
    // that are far (>3 pages away) to immediately free sockets/HTTP connections for the visible page!
    if (localPaths[idx] == null) {
      final keysToCancel = <int>[];
      _activeOps.forEach((activeIdx, _) {
        if ((activeIdx - idx).abs() > 3) {
          keysToCancel.add(activeIdx);
        }
      });

      for (final cancelIdx in keysToCancel) {
        _cancelPage(cancelIdx);
        _downloading[cancelIdx] = false;
        _progress[cancelIdx] = null;
      }
    }
  }

  void _cancelPage(int index) {
    _activeOps.remove(index)?.cancel();
    _activeClients.remove(index)?.close();
  }

  void _cancelAll() {
    for (final op in _activeOps.values) {
      op.cancel();
    }
    _activeOps.clear();
    for (final client in _activeClients.values) {
      client.close();
    }
    _activeClients.clear();
  }

  void dispose() {
    _isDisposed = true;
    _cancelAll();
    onPageDownloadedNotifier.dispose();
  }

  Future<void> _startDownloadLoop() async {
    while (!_isDisposed) {
      // Find the next index to download based on Mihon priority
      int nextIdx = _getNextIndexToDownload();
      if (nextIdx == -1) {
        // All downloaded or failed! We can rest.
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      await _downloadPage(nextIdx);
      // Brief pause to prevent CPU/Network thrashing
      await Future.delayed(const Duration(milliseconds: 25));
    }
  }

  int _getNextIndexToDownload() {
    if (urls.isEmpty) return -1;
    final int safePriority = _priorityIndex.clamp(0, urls.length - 1);
    
    // 1. Highest Priority: The EXACT page currently visible on screen
    if (localPaths[safePriority] == null && _failedCounts[safePriority] < 3 && !_downloading[safePriority]) {
      return safePriority;
    }
    
    // 2. Next Priority: Immediate forward pages (+1, +2, +3) for smooth reading flow
    for (int offset = 1; offset <= 3; offset++) {
      final int forwardIdx = safePriority + offset;
      if (forwardIdx < urls.length && localPaths[forwardIdx] == null && _failedCounts[forwardIdx] < 3 && !_downloading[forwardIdx]) {
        return forwardIdx;
      }
    }
    
    // 3. Next Priority: Immediate backward page (-1) in case user scrolls back
    final int backIdx = safePriority - 1;
    if (backIdx >= 0 && localPaths[backIdx] == null && _failedCounts[backIdx] < 3 && !_downloading[backIdx]) {
      return backIdx;
    }
    
    // 4. Remaining pages ordered strictly by distance from current visible page (|idx - safePriority|)
    int bestCandidate = -1;
    int minDistance = 999999;
    
    for (int idx = 0; idx < urls.length; idx++) {
      if (localPaths[idx] == null && _failedCounts[idx] < 3 && !_downloading[idx]) {
        final int dist = (idx - safePriority).abs();
        if (dist < minDistance) {
          minDistance = dist;
          bestCandidate = idx;
        }
      }
    }
    
    return bestCandidate;
  }

  Future<void> _downloadPage(int index) async {
    if (index < 0 || index >= urls.length) return;
    _downloading[index] = true;
    _progress[index] = 0.0;
    final url = urls[index];

    // ── Offline shortcut: file:// URLs come from downloaded chapters ──────────
    final uri = Uri.tryParse(url);
    if (uri != null && uri.isScheme('file')) {
      final localFile = File.fromUri(uri);
      if (await localFile.exists()) {
        localPaths[index] = localFile.path;
        _downloading[index] = false;
        _progress[index] = 1.0;
        _failedCounts[index] = 0;
        try {
          final bytes = await localFile.readAsBytes();
          ImageDimension? dims = _parseImageDimensions(bytes);
          pageDimensions[index] = dims;
        } catch (_) {}
        onPageDownloadedNotifier.value = index;
        onPageDownloaded(index);
        return;
      } else {
        _failedCounts[index]++;
        _downloading[index] = false;
        return;
      }
    }
    // ─────────────────────────────────────────────────────────────────────────

    // Create local path
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}${Platform.pathSeparator}manga_ch_${chapterId}_p_$index.jpg');
    
    // If it already exists on disk (e.g. from a previous view), use it!
    if (await file.exists() && await file.length() > 100) {
      localPaths[index] = file.path;
      _downloading[index] = false;
      _progress[index] = 1.0;
      _failedCounts[index] = 0; // reset
      
      try {
        final bytes = await file.readAsBytes();
        ImageDimension? dims = _parseImageDimensions(bytes);
        if (dims == null) {
          final image = await decodeImageFromList(bytes);
          dims = ImageDimension(image.width.toDouble(), image.height.toDouble());
        }
        pageDimensions[index] = dims;
      } catch (_) {}
      
      onPageDownloadedNotifier.value = index;
      onPageDownloaded(index);
      return;
    }

    final client = http.Client();
    _activeClients[index] = client;
    
    final completer = Completer<void>();
    
    final requestFuture = Future(() async {
      try {
        final request = http.Request('GET', Uri.parse(url));
        final streamedResponse = await client.send(request);
        if (streamedResponse.statusCode == 200) {
          final contentLength = streamedResponse.contentLength ?? 0;
          final bytes = <int>[];
          await for (final chunk in streamedResponse.stream) {
            bytes.addAll(chunk);
            if (contentLength > 0) {
              _progress[index] = (bytes.length / contentLength).clamp(0.0, 1.0);
            }
          }
          if (bytes.isNotEmpty) {
            await file.writeAsBytes(bytes);
            localPaths[index] = file.path;
            _failedCounts[index] = 0; // reset
            
            try {
              final uint8bytes = Uint8List.fromList(bytes);
              ImageDimension? dims = _parseImageDimensions(uint8bytes);
              pageDimensions[index] = dims;
            } catch (_) {}
            
            _progress[index] = 1.0;
            onPageDownloadedNotifier.value = index;
            onPageDownloaded(index);
          } else {
            _failedCounts[index]++;
          }
        } else {
          _failedCounts[index]++;
        }
      } catch (_) {
        _failedCounts[index]++;
      } finally {
        _downloading[index] = false;
        _activeClients.remove(index);
        _activeOps.remove(index);
        completer.complete();
      }
    });

    final op = CancelableOperation.fromFuture(
      requestFuture,
      onCancel: () {
        _downloading[index] = false;
        _activeClients.remove(index)?.close();
        _activeOps.remove(index);
        completer.complete();
      },
    );
    _activeOps[index] = op;

    await completer.future;
  }

  ImageDimension? _parseImageDimensions(Uint8List bytes) {
    if (bytes.length < 8) return null;

    // WebP Check: signature RIFF .... WEBP
    if (bytes.length >= 30 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      // Chunk VP8X (Extended WebP)
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x58 && bytes.length >= 30) {
        final int width = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
        final int height = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
        return ImageDimension(width.toDouble(), height.toDouble());
      }
      // Chunk VP8 (Lossy WebP)
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x20 && bytes.length >= 30) {
        final int width = ((bytes[26] | (bytes[27] << 8)) & 0x3FFF);
        final int height = ((bytes[28] | (bytes[29] << 8)) & 0x3FFF);
        return ImageDimension(width.toDouble(), height.toDouble());
      }
      // Chunk VP8L (Lossless WebP)
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x4C && bytes.length >= 25) {
        final int bits = bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
        final int width = 1 + (bits & 0x3FFF);
        final int height = 1 + ((bits >> 14) & 0x3FFF);
        return ImageDimension(width.toDouble(), height.toDouble());
      }
    }

    // PNG Check: signature 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      if (bytes.length >= 24) {
        final int width = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        final int height = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        return ImageDimension(width.toDouble(), height.toDouble());
      }
    }

    // JPEG Check: signature FF D8
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int offset = 2;
      while (offset < bytes.length - 8) {
        if (bytes[offset] == 0xFF) {
          final int marker = bytes[offset + 1];
          if ((marker >= 0xC0 && marker <= 0xCF) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
            final int height = (bytes[offset + 5] << 8) | bytes[offset + 6];
            final int width = (bytes[offset + 7] << 8) | bytes[offset + 8];
            return ImageDimension(width.toDouble(), height.toDouble());
          }
          final int length = (bytes[offset + 2] << 8) | bytes[offset + 3];
          offset += length + 2;
        } else {
          offset++;
        }
      }
    }

    return null;
  }
}

class _ZoomablePageImage extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool>? onZoomChanged;
  const _ZoomablePageImage({super.key, required this.child, this.onZoomChanged});


  @override
  State<_ZoomablePageImage> createState() => _ZoomablePageImageState();
}

class _ZoomablePageImageState extends State<_ZoomablePageImage> {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _lastZoomState = false;

  bool get _isZoomed => _controller.value.getMaxScaleOnAxis() > 1.05;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleZoomChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleZoomChange);
    _controller.dispose();
    super.dispose();
  }

  void _handleZoomChange() {
    final zoomed = _isZoomed;
    if (zoomed != _lastZoomState) {
      _lastZoomState = zoomed;
      if (widget.onZoomChanged != null) {
        widget.onZoomChanged!(zoomed);
      }
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _onDoubleTap() {
    final Offset focalPoint = _doubleTapDetails!.localPosition;
    if (_isZoomed) {
      _controller.value = Matrix4.identity();
    } else {
      _zoomTo(2.0, focalPoint);
    }
    if (mounted) setState(() {});
  }

  // Zoom to [scale] keeping [focalPoint] (in viewport coords) fixed on screen.
  void _zoomTo(double scale, Offset focalPoint) {
    // Convert the focal point from viewport space to scene (child) space
    final Offset focalPointScene = _controller.toScene(focalPoint);
    _controller.value = Matrix4.identity()
      ..translate(
        focalPoint.dx - focalPointScene.dx * scale,
        focalPoint.dy - focalPointScene.dy * scale,
      )
      ..scale(scale);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final bool ctrlHeld = HardwareKeyboard.instance.isControlPressed;
          if (!ctrlHeld) {
            // Don't zoom on plain scroll — let parent handle it
            return;
          }
          // Ctrl+scroll: zoom centered on the mouse cursor
          final double currentScale = _controller.value.getMaxScaleOnAxis();
          final double factor = event.scrollDelta.dy > 0 ? 0.85 : 1.15;
          final double newScale = (currentScale * factor).clamp(1.0, 5.0);
          if (newScale <= 1.02) {
            _controller.value = Matrix4.identity();
          } else {
            _zoomTo(newScale, event.localPosition);
          }
          if (mounted) setState(() {});
        }
      },
      child: GestureDetector(
        onDoubleTapDown: _onDoubleTapDown,
        onDoubleTap: _onDoubleTap,
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1.0,
          maxScale: 5.0,
          // Only pan when zoomed — when at 1x, let PageView handle swipes
          panEnabled: _isZoomed,
          scaleEnabled: true,
          onInteractionEnd: (_) {
            // Snap back to 1x if barely zoomed
            if (_controller.value.getMaxScaleOnAxis() < 1.05) {
              _controller.value = Matrix4.identity();
            }
            if (mounted) setState(() {});
          },
          onInteractionUpdate: (_) {
            if (mounted) setState(() {});
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _MihonPagePlaceholder extends StatelessWidget {
  final double width;
  final double? height;
  final int pageNumber;
  final bool isDownloading;
  final double? progress;

  const _MihonPagePlaceholder({
    required this.width,
    this.height,
    required this.pageNumber,
    required this.isDownloading,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height ?? (width * 1.5),
      color: Colors.black,
      child: Stack(
        children: [
          // Center: page number + spinner/progress
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Spinner
                SizedBox(
                  width: 36,
                  height: 36,
                  child: progress != null && progress! < 1.0
                      ? CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 2.5,
                          color: const Color(0xFFFF9F1C),
                          backgroundColor: Colors.white10,
                        )
                      : const CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFFFF9F1C),
                          backgroundColor: Colors.transparent,
                        ),
                ),
                const SizedBox(height: 12),
                // Percentage text
                if (progress != null && progress! > 0)
                  Text(
                    '${(progress! * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else
                  Text(
                    'Page $pageNumber',
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 11,
                      fontFamily: 'Outfit',
                    ),
                  ),
              ],
            ),
          ),

          // Bottom page number badge
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$pageNumber',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImageDimension {
  final double width;
  final double height;
  ImageDimension(this.width, this.height);
}

class _WebtoonImageWithSize extends StatefulWidget {
  final File file;
  final int index;
  final String currentChapterId;
  final bool isWebtoon;
  final double maxWidth;
  final MangaPageLoader? pageLoader;
  final VoidCallback? onDimensionResolved;
  final Widget Function(BuildContext, Object, StackTrace?) errorBuilder;

  const _WebtoonImageWithSize({
    required this.file,
    required this.index,
    required this.currentChapterId,
    required this.isWebtoon,
    required this.maxWidth,
    required this.pageLoader,
    this.onDimensionResolved,
    required this.errorBuilder,
  });

  @override
  State<_WebtoonImageWithSize> createState() => _WebtoonImageWithSizeState();
}

class _WebtoonImageWithSizeState extends State<_WebtoonImageWithSize> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  @override
  void initState() {
    super.initState();
    _resolveDimensions();
  }

  @override
  void didUpdateWidget(_WebtoonImageWithSize oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _resolveDimensions();
    }
  }

  void _resolveDimensions() {
    if (widget.pageLoader?.pageDimensions[widget.index] != null) return;
    
    final provider = FileImage(widget.file);
    _imageStreamListener = ImageStreamListener((ImageInfo info, bool _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (w > 0 && h > 0 && mounted) {
        widget.pageLoader?.pageDimensions[widget.index] = ImageDimension(w, h);
        widget.onDimensionResolved?.call();
      }
    });
    _imageStream = provider.resolve(const ImageConfiguration());
    _imageStream?.addListener(_imageStreamListener!);
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageStreamListener != null) {
      _imageStream!.removeListener(_imageStreamListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image.file(
      widget.file,
      key: ValueKey('file_${widget.currentChapterId}_${widget.index}_${widget.file.path}'),
      fit: widget.isWebtoon ? BoxFit.fitWidth : BoxFit.contain,
      width: widget.isWebtoon ? double.infinity : null,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return _MihonPagePlaceholder(
          width: widget.maxWidth,
          height: null,
          pageNumber: widget.index + 1,
          isDownloading: false,
          progress: null,
        );
      },
      errorBuilder: widget.errorBuilder,
    );
  }
}

/// Wraps a single webtoon page item and reports its actual rendered pixel height
/// to the parent via [onHeightChanged] every time the widget's size changes.
/// This is the ground truth used by [_onScroll] for accurate page indicator tracking.
class _WebtoonPageHeightReporter extends StatefulWidget {
  final int index;
  final Widget child;
  final ValueChanged<double> onHeightChanged;

  const _WebtoonPageHeightReporter({
    required this.index,
    required this.child,
    required this.onHeightChanged,
  });

  @override
  State<_WebtoonPageHeightReporter> createState() => _WebtoonPageHeightReporterState();
}

class _WebtoonPageHeightReporterState extends State<_WebtoonPageHeightReporter> {
  final GlobalKey _key = GlobalKey();
  double? _lastHeight;

  void _reportHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final h = box.size.height;
        if (h > 0 && h != _lastHeight) {
          _lastHeight = h;
          widget.onHeightChanged(h);
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _reportHeight();
  }

  @override
  void didUpdateWidget(_WebtoonPageHeightReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reportHeight();
  }

  @override
  Widget build(BuildContext context) {
    // NotificationListener catches size changes from children (e.g. image load)
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _reportHeight();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(
          key: _key,
          child: widget.child,
        ),
      ),
    );
  }
}
