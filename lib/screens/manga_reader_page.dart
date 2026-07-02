import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/suwayomi_service.dart';
import '../state/navigation_state.dart';
import '../state/library_state.dart';

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
  bool _isWebtoonMode = true; // Webtoon continuous vertical scroll by default
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
    _loadPages();
    _updateLibraryProgress();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
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
      if (_currentChapterNumber > item.watchedEpisodes) {
        library.saveItem(
          id: parsedMangaId,
          mode: 'manga',
          format: 'MANGA',
          libraryStatus: item.libraryStatus,
          rating: item.rating,
          watchedEpisodes: _currentChapterNumber,
          totalEpisodes: widget.chapters.length,
        );
      }
    }
  }

  void _navigateToNextChapter() {
    final chapters = widget.chapters;
    // Find index of current chapter using local currentChapterId state
    final currentIdx = chapters.indexWhere((c) => c['id']?.toString() == _currentChapterId);
    if (currentIdx != -1 && currentIdx > 0) {
      // Chapters list is usually descending by default, so index 0 is latest chapter
      // To go to next chapter (e.g. Chapter 2 -> 3), we actually go left in list (descending)
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have reached the latest chapter.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous chapters available.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Content Viewer
          GestureDetector(
            onTap: () => setState(() => _showOverlay = !_showOverlay),
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9F1C)),
                    ),
                  )
                : _errorMessage != null
                    ? _buildErrorView()
                    : _isWebtoonMode
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
              child: CachedNetworkImage(
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildPagingViewer() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _pageUrls.length,
      onPageChanged: (index) {
        setState(() => _currentPageIndex = index);
      },
      itemBuilder: (context, index) {
        return Center(
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: CachedNetworkImage(
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
        );
      },
    );
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
          if (!_isWebtoonMode && _pageUrls.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  '${_currentPageIndex + 1}',
                  style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: Slider(
                    value: _currentPageIndex.toDouble(),
                    min: 0.0,
                    max: (_pageUrls.length - 1).toDouble(),
                    activeColor: const Color(0xFFFF9F1C),
                    inactiveColor: Colors.white12,
                    onChanged: (val) {
                      setState(() {
                        _currentPageIndex = val.toInt();
                        _pageController.jumpToPage(_currentPageIndex);
                      });
                    },
                  ),
                ),
                Text(
                  '${_pageUrls.length}',
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
              Wrap(
                spacing: 8.0,
                children: [
                  ChoiceChip(
                    label: const Text('Webtoon', style: TextStyle(fontSize: 10.0, fontFamily: 'Outfit')),
                    selected: _isWebtoonMode,
                    selectedColor: const Color(0xFFFF9F1C),
                    backgroundColor: const Color(0xFF16161A),
                    onSelected: (selected) {
                      if (selected) setState(() => _isWebtoonMode = true);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Pages', style: TextStyle(fontSize: 10.0, fontFamily: 'Outfit')),
                    selected: !_isWebtoonMode,
                    selectedColor: const Color(0xFFFF9F1C),
                    backgroundColor: const Color(0xFF16161A),
                    onSelected: (selected) {
                      if (selected) setState(() => _isWebtoonMode = false);
                    },
                  ),
                ],
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
