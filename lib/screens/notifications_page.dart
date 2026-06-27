import 'package:flutter/material.dart';
import '../state/navigation_state.dart';
import '../state/library_state.dart';
import '../services/anilist_service.dart';

class NotificationsPage extends StatefulWidget {
  final AppMode mode;
  final NavigationState navigationState;

  const NotificationsPage({
    super.key,
    required this.mode,
    required this.navigationState,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final AnilistService _anilistService = AnilistService();
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    LibraryState().clearNotificationBadge(widget.mode);
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final String localModeStr = widget.mode == AppMode.manga
        ? 'manga'
        : (widget.mode == AppMode.movies ? 'movies' : 'anime');
        
    final String anilistTypeStr = widget.mode == AppMode.manga ? 'MANGA' : 'ANIME';

    final libraryItems = LibraryState().items.where((item) => item.mode == localModeStr).toList();
    if (libraryItems.isEmpty) {
      if (mounted) {
        setState(() {
          _notifications = [];
          _isLoading = false;
        });
      }
      return;
    }

    final ids = libraryItems.map((item) => item.id).toList();

    try {
      final List<dynamic> details = await _anilistService.fetchLibraryDetails(ids, type: anilistTypeStr);
      final List<Map<String, dynamic>> generated = [];

      for (var media in details) {
        final id = media['id'];
        final localItem = libraryItems.firstWhere((item) => item.id == id);

        // Determine latest released episode or chapter
        final int? nextEpisode = media['nextAiringEpisode']?['episode'];
        final int totalEpisodes = media['episodes'] ?? 0;
        final int totalChapters = media['chapters'] ?? 0;
        
        final int latestReleased = widget.mode == AppMode.manga
            ? totalChapters
            : (nextEpisode != null ? (nextEpisode - 1) : totalEpisodes);

        final nextAiring = media['nextAiringEpisode'];
        int releaseTime = 0;
        if (nextAiring != null) {
          releaseTime = (nextAiring['airingAt'] as int) - 604800;
        } else {
          releaseTime = media['updatedAt'] ?? 0;
        }

        if (latestReleased > localItem.watchedEpisodes) {
          final int startNew = localItem.watchedEpisodes + 1;
          final int endNew = latestReleased;

          String message = '';
          if (widget.mode == AppMode.manga) {
            if (startNew == endNew) {
              message = 'Chapter $startNew is now available!';
            } else {
              message = 'Chapters $startNew-$endNew are now available!';
            }
          } else {
            if (startNew == endNew) {
              message = 'Episode $startNew is now available!';
            } else {
              message = 'Episodes $startNew-$endNew are now available!';
            }
          }

          generated.add({
            'id': id,
            'media': media,
            'title': media['title']?['english'] ?? media['title']?['romaji'] ?? 'Untitled',
            'coverImage': media['coverImage']?['large'] ?? '',
            'message': message,
            'latestReleased': latestReleased,
            'watchedCount': localItem.watchedEpisodes,
            'status': media['status'] ?? '',
            'releaseTime': releaseTime,
          });
        }
      }

      // Sort notifications by releaseTime descending (most recent first)
      generated.sort((a, b) => (b['releaseTime'] as int).compareTo(a['releaseTime'] as int));

      if (mounted) {
        setState(() {
          _notifications = generated;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
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
            // Top spacing on desktop
            SizedBox(height: isMobile ? 8.0 : 58.0),

            // Page Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notifications',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                      SizedBox(height: 4.0),
                      Text(
                        'Updates about new episode releases for shows in your library.',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13.0,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    onPressed: _fetchNotifications,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12.0),

            // Notifications List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.0,
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.redAccent, size: 40.0),
                                const SizedBox(height: 12.0),
                                Text(
                                  'Error loading updates:\n$_errorMessage',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70, fontSize: 14.0, fontFamily: 'Outfit'),
                                ),
                                const SizedBox(height: 16.0),
                                ElevatedButton(
                                  onPressed: _fetchNotifications,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                                  ),
                                  child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _notifications.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.notifications_none, color: Colors.white24, size: 48.0),
                                  const SizedBox(height: 16.0),
                                  const Text(
                                    'All caught up! No new episodes released.',
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
                              itemCount: _notifications.length,
                              itemBuilder: (context, index) {
                                final notif = _notifications[index];
                                final title = notif['title'];
                                final coverUrl = notif['coverImage'];
                                final message = notif['message'];
                                final status = notif['status'];

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12.0),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F0F11),
                                    borderRadius: BorderRadius.circular(10.0),
                                    border: Border.all(
                                      color: const Color(0xFF2EC4B6).withValues(alpha: 0.15),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: () {
                                      widget.navigationState.selectAnime(notif['id']);
                                    },
                                    borderRadius: BorderRadius.circular(10.0),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Row(
                                        children: [
                                          // Accent circle indicator
                                          Container(
                                            width: 8.0,
                                            height: 8.0,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF2EC4B6),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 12.0),

                                          // Cover Art
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(6.0),
                                            child: SizedBox(
                                              width: 44.0,
                                              height: 60.0,
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

                                          // Text details
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
                                                const SizedBox(height: 4.0),
                                                Text(
                                                  message,
                                                  style: const TextStyle(
                                                    color: Color(0xFF2EC4B6),
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12.5,
                                                    fontFamily: 'Outfit',
                                                  ),
                                                ),
                                                if (status.isNotEmpty) ...[
                                                  const SizedBox(height: 4.0),
                                                  Text(
                                                    'Status: ${status.replaceAll('_', ' ')}',
                                                    style: const TextStyle(
                                                      color: Colors.white38,
                                                      fontSize: 10.5,
                                                      fontFamily: 'Outfit',
                                                    ),
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
