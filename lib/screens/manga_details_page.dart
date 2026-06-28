import 'package:flutter/material.dart';
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
      backgroundColor: const Color(0xFF0F0F11),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return _MangaLibraryEditPanel(
          mangaId: _parsedMangaId,
          title: _details!['title'] ?? 'Manga Details',
          totalChapters: _chapters.length,
          onSaved: () => setState(() {}),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => widget.navigationState.selectManga(null),
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
    final author = _details!['author'] ?? 'Unknown Author';
    final description = _details!['description'] ?? 'No description available.';
    final status = _details!['status'] ?? 'Unknown';
    final genres = (_details!['genre'] as List? ?? []).map((g) => g.toString()).toList();

    final libraryState = LibraryState();
    final libraryItem = libraryState.getItem(_parsedMangaId, 'manga');
    final bool inLibrary = libraryItem != null;

    final displayChapters = _isChaptersReversed ? _chapters.reversed.toList() : _chapters;

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          // Header / Banner & Back controls
          SliverAppBar(
            backgroundColor: Colors.black,
            expandedHeight: 280.0,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => widget.navigationState.selectManga(null),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  inLibrary ? Icons.bookmark : Icons.bookmark_border,
                  color: inLibrary ? const Color(0xFFFF9F1C) : Colors.white70,
                ),
                onPressed: _showLibraryEditPanel,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverUrl.isNotEmpty) ...[
                    Image.network(coverUrl, fit: BoxFit.cover),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black, Colors.transparent, Colors.black87],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Main Info Details
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  const SizedBox(height: 8.0),

                  // Author & Status
                  Row(
                    children: [
                      Text(
                        'By $author',
                        style: const TextStyle(color: Colors.white54, fontSize: 13.0, fontFamily: 'Outfit'),
                      ),
                      const SizedBox(width: 12.0),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9F1C).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(
                          status,
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

                  const SizedBox(height: 16.0),

                  // Genres tags
                  if (genres.isNotEmpty) ...[
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

                  // Description
                  Text(
                    description,
                    style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5, fontFamily: 'Outfit'),
                  ),

                  const SizedBox(height: 32.0),

                  // Chapters Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Chapters (${_chapters.length})',
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
                  const SizedBox(height: 12.0),
                ],
              ),
            ),
          ),

          // Chapters list
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final chapter = displayChapters[index];
                final String chName = chapter['name'] ?? 'Chapter';
                final String chId = chapter['id']?.toString() ?? '';
                final double? chNum = double.tryParse(chapter['chapterNumber']?.toString() ?? '');
                final bool read = chapter['read'] ?? false;

                // Check local library watched episodes to highlight read chapters
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
              childCount: displayChapters.length,
            ),
          ),

          // Safety bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 64.0),
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
  final VoidCallback onSaved;

  const _MangaLibraryEditPanel({
    required this.mangaId,
    required this.title,
    required this.totalChapters,
    required this.onSaved,
  });

  @override
  State<_MangaLibraryEditPanel> createState() => _MangaLibraryEditPanelState();
}

class _MangaLibraryEditPanelState extends State<_MangaLibraryEditPanel> {
  String _status = 'planning';
  double _rating = 0.0;
  int _chaptersRead = 0;

  @override
  void initState() {
    super.initState();
    final item = LibraryState().getItem(widget.mangaId, 'manga');
    if (item != null) {
      _status = item.libraryStatus;
      _rating = item.rating;
      _chaptersRead = item.watchedEpisodes;
    }
  }

  void _save() {
    LibraryState().saveItem(
      id: widget.mangaId,
      mode: 'manga',
      format: 'MANGA',
      libraryStatus: _status,
      rating: _rating,
      watchedEpisodes: _chaptersRead,
      totalEpisodes: widget.totalChapters,
    );
    widget.onSaved();
    Navigator.pop(context);
  }

  void _remove() {
    LibraryState().removeItem(widget.mangaId, 'manga');
    widget.onSaved();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final item = LibraryState().getItem(widget.mangaId, 'manga');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.white10),
            const SizedBox(height: 12.0),

            // Status Row Selector
            const Text('Status', style: TextStyle(color: Colors.white54, fontSize: 12.0, fontFamily: 'Outfit')),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 8.0,
              children: ['reading', 'planning', 'completed', 'dropped'].map((statusOption) {
                final isSelected = _status == statusOption;
                return ChoiceChip(
                  label: Text(
                    statusOption.replaceFirst('_', ' ').toUpperCase(),
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontSize: 10.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFFFF9F1C),
                  backgroundColor: const Color(0xFF16161A),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _status = statusOption;
                        if (statusOption == 'completed') {
                          _chaptersRead = widget.totalChapters;
                        }
                      });
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 20.0),

            // Progress Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Chapters Read', style: TextStyle(color: Colors.white54, fontSize: 12.0, fontFamily: 'Outfit')),
                Text('$_chaptersRead / ${widget.totalChapters}', style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
              ],
            ),
            if (widget.totalChapters > 0)
              Slider(
                value: _chaptersRead.toDouble().clamp(0.0, widget.totalChapters.toDouble()),
                min: 0.0,
                max: widget.totalChapters.toDouble(),
                activeColor: const Color(0xFFFF9F1C),
                inactiveColor: Colors.white10,
                onChanged: (val) {
                  setState(() {
                    _chaptersRead = val.toInt();
                    if (_chaptersRead == widget.totalChapters) {
                      _status = 'completed';
                    }
                  });
                },
              ),

            const SizedBox(height: 20.0),

            // Rating Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Rating Score', style: TextStyle(color: Colors.white54, fontSize: 12.0, fontFamily: 'Outfit')),
                Text(_rating > 0.0 ? _rating.toStringAsFixed(1) : 'No Rating', style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: _rating,
              min: 0.0,
              max: 10.0,
              divisions: 100,
              activeColor: const Color(0xFFFF9F1C),
              inactiveColor: Colors.white10,
              onChanged: (val) => setState(() => _rating = val),
            ),

            const SizedBox(height: 24.0),

            // Footer Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (item != null)
                  TextButton.icon(
                    onPressed: _remove,
                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18.0),
                    label: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontFamily: 'Outfit')),
                  )
                else
                  const SizedBox.shrink(),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9F1C),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                  ),
                  child: const Text('Save Entry', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
