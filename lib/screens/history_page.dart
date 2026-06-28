import 'package:flutter/material.dart';
import '../state/navigation_state.dart';
import '../state/player_state.dart';

class HistoryPage extends StatefulWidget {
  final AppMode mode;
  final NavigationState navigationState;

  const HistoryPage({
    super.key,
    required this.mode,
    required this.navigationState,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _historyItems = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
    });
    final items = await PlayerState.getHistoryList();
    
    // Filter history items by active mode using isAnime flag
    final filtered = items.where((item) {
      final isAnime = item['isAnime'] ?? true;
      if (widget.mode == AppMode.movies) {
        return !isAnime;
      } else if (widget.mode == AppMode.anime) {
        return isAnime;
      } else {
        return false;
      }
    }).toList();

    if (mounted) {
      setState(() {
        _historyItems = filtered;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: const Text(
          'Clear Watch History?',
          style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to clear your entire watch history? This action cannot be undone.',
          style: TextStyle(color: Colors.white70, fontFamily: 'Outfit'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await PlayerState.clearHistory();
      _loadHistory();
    }
  }

  String _formatEpisodeRanges(List<int> episodes) {
    if (episodes.isEmpty) return 'None';
    
    final sorted = List<int>.from(episodes)..sort();
    final List<String> parts = [];
    
    int start = sorted[0];
    int end = sorted[0];
    
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i] == end + 1) {
        end = sorted[i];
      } else {
        if (start == end) {
          parts.add('$start');
        } else {
          parts.add('$start-$end');
        }
        start = sorted[i];
        end = sorted[i];
      }
    }
    
    if (start == end) {
      parts.add('$start');
    } else {
      parts.add('$start-$end');
    }
    
    return parts.join(', ');
  }

  String _formatTimeAgo(int timestamp) {
    if (timestamp == 0) return '';
    final difference = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp));
    
    if (difference.inDays > 7) {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return '${date.day}/${date.month}/${date.year}';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header spacing on desktop
            SizedBox(height: isMobile ? 8.0 : 58.0),
            
            // Watch History Page Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Watch History',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                      SizedBox(height: 4.0),
                      Text(
                        'Track and resume episodes you recently watched.',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13.0,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ],
                  ),
                  if (_historyItems.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18.0),
                      label: const Text(
                        'Clear All',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                      onPressed: _clearAllHistory,
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 12.0),

            // History list content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.0,
                      ),
                    )
                  : _historyItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, color: Colors.white24, size: 48.0),
                              const SizedBox(height: 16.0),
                              const Text(
                                'Your watch history is empty.',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 14.0,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                          itemCount: _historyItems.length,
                          itemBuilder: (context, index) {
                            final item = _historyItems[index];
                            final media = item['media'] ?? {};
                            final title = media['title'] is Map
                                ? (media['title']['english'] ?? media['title']['romaji'] ?? 'Untitled')
                                : (media['title'] ?? 'Untitled');
                            final coverUrl = media['coverImage'] is Map
                                ? (media['coverImage']['large'] ?? media['coverImage']['extraLarge'] ?? '')
                                : (media['coverImage'] ?? '');
                            final format = media['format'] ?? '';
                            final episodes = item['episodes'] as List<int>;
                            final timeAgo = _formatTimeAgo(item['timestamp']);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12.0),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F0F11),
                                borderRadius: BorderRadius.circular(10.0),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: InkWell(
                                onTap: () {
                                  final isAnime = item['isAnime'] ?? true;
                                  if (isAnime) {
                                    final idInt = int.tryParse(item['id'].toString());
                                    if (idInt != null) {
                                      widget.navigationState.selectAnime(idInt);
                                    }
                                  } else {
                                    widget.navigationState.selectMovie(item['id'].toString());
                                  }
                                },
                                borderRadius: BorderRadius.circular(10.0),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    children: [
                                      // Cover Art
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6.0),
                                        child: SizedBox(
                                          width: 48.0,
                                          height: 68.0,
                                          child: coverUrl.isNotEmpty
                                              ? Image.network(
                                                  coverUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) =>
                                                      Container(color: Colors.grey[950]),
                                                )
                                              : Container(color: Colors.grey[950]),
                                        ),
                                      ),
                                      const SizedBox(width: 16.0),
                                      
                                      // Details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14.0,
                                                fontFamily: 'Outfit',
                                              ),
                                            ),
                                            const SizedBox(height: 6.0),
                                            Text(
                                              'Watched Episodes: ${_formatEpisodeRanges(episodes)}',
                                              style: const TextStyle(
                                                color: Color(0xFF3A86FF),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12.0,
                                                fontFamily: 'Outfit',
                                              ),
                                            ),
                                            if (format.isNotEmpty || timeAgo.isNotEmpty) ...[
                                              const SizedBox(height: 6.0),
                                              Row(
                                                children: [
                                                  if (format.isNotEmpty) ...[
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white.withValues(alpha: 0.05),
                                                        borderRadius: BorderRadius.circular(3.0),
                                                      ),
                                                      child: Text(
                                                        format,
                                                        style: const TextStyle(
                                                          color: Colors.white54,
                                                          fontSize: 9.0,
                                                          fontWeight: FontWeight.bold,
                                                          fontFamily: 'Outfit',
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10.0),
                                                  ],
                                                  if (timeAgo.isNotEmpty)
                                                    Text(
                                                      timeAgo,
                                                      style: const TextStyle(
                                                        color: Colors.white38,
                                                        fontSize: 11.0,
                                                        fontFamily: 'Outfit',
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      
                                      const Icon(
                                        Icons.chevron_right,
                                        color: Colors.white30,
                                        size: 20.0,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
