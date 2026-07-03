import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../state/navigation_state.dart';
import '../state/library_state.dart';
import '../services/anilist_service.dart';
import '../services/download_service.dart';

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

    final libraryItems = LibraryState().items.where((item) => item.mode == localModeStr).toList();
    if (libraryItems.isEmpty) {
      if (mounted) {
        setState(() {
          _notifications = [];
          _isLoading = false;
        });
        LibraryState().clearNotificationBadge(widget.mode);
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    if (widget.mode == AppMode.movies) {
      final List<Map<String, dynamic>> generated = [];
      try {
        final futures = libraryItems.where((item) => item.format == 'SERIES').map((localItem) async {
          final imdbId = 'tt${localItem.id.toString().padLeft(7, '0')}';
          final url = 'https://v3-cinemeta.strem.io/meta/series/$imdbId.json';
          try {
            final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
            if (response.statusCode == 200) {
              final decoded = jsonDecode(response.body);
              final meta = decoded['meta'];
              if (meta != null) {
                final videos = meta['videos'] as List? ?? [];
                final int latestReleased = videos.length;
                final int startBaseline = prefs.getInt('notif_start_episode_movies_${localItem.id}') ?? latestReleased;
                final localDownloads = DownloadService().tasks.where(
                  (t) => t.anilistId == localItem.id && t.status == DownloadStatus.completed
                );
                final int maxDownloaded = localDownloads.isEmpty 
                    ? 0 
                    : localDownloads.map((t) => t.episodeNumber ?? 0).fold(0, max);
                final int startNew = max(max(localItem.watchedEpisodes, maxDownloaded), startBaseline) + 1;
                
                if (latestReleased >= startNew) {
                  final int endNew = latestReleased;
                  
                  final String message = startNew == endNew
                      ? 'Episode $startNew is now available!'
                      : 'Episodes $startNew-$endNew are now available!';
                      
                  generated.add({
                    'id': imdbId,
                    'media': meta,
                    'title': meta['name'] ?? 'Untitled',
                    'coverImage': meta['poster'] ?? '',
                    'message': message,
                    'latestReleased': latestReleased,
                    'watchedCount': localItem.watchedEpisodes,
                    'status': meta['status'] ?? '',
                    'releaseTime': DateTime.tryParse(meta['released']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0,
                  });
                }
              }
            }
          } catch (_) {}
        });
        await Future.wait(futures);

        // Sort notifications by releaseTime descending
        generated.sort((a, b) => (b['releaseTime'] as int).compareTo(a['releaseTime'] as int));

        if (mounted) {
          setState(() {
            _notifications = generated;
            _isLoading = false;
          });
          LibraryState().clearNotificationBadge(widget.mode);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
            _isLoading = false;
          });
          LibraryState().clearNotificationBadge(widget.mode);
        }
      }
      return;
    }

    try {
      final List<Map<String, dynamic>> generated = [];

      if (widget.mode == AppMode.anime) {
        final ids = libraryItems.map((item) => item.id).toList();
        final List<dynamic> details = await _anilistService.fetchLibraryDetails(ids, type: 'ANIME');
        for (var media in details) {
          final id = media['id'];
          final localItem = libraryItems.firstWhere((item) => item.id == id);

          final int? nextEpisode = media['nextAiringEpisode']?['episode'];
          final int totalEpisodes = media['episodes'] ?? 0;
          final int latestReleased = nextEpisode != null ? (nextEpisode - 1) : totalEpisodes;

          final nextAiring = media['nextAiringEpisode'];
          int releaseTime = 0;
          if (nextAiring != null) {
            releaseTime = (nextAiring['airingAt'] as int) - 604800;
          } else {
            releaseTime = media['updatedAt'] ?? 0;
          }

          final int startBaseline = prefs.getInt('notif_start_episode_anime_$id') ?? latestReleased;
          final localDownloads = DownloadService().tasks.where(
            (t) => t.anilistId == id && t.status == DownloadStatus.completed
          );
          final int maxDownloaded = localDownloads.isEmpty 
              ? 0 
              : localDownloads.map((t) => t.episodeNumber ?? 0).fold(0, max);
          final int startNew = max(max(localItem.watchedEpisodes, maxDownloaded), startBaseline) + 1;

          if (latestReleased >= startNew) {
            final int endNew = latestReleased;

            final String message = startNew == endNew
                ? 'Episode $startNew is now available!'
                : 'Episodes $startNew-$endNew are now available!';

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
      } else if (widget.mode == AppMode.manga) {
        final cache = LibraryState().mangaCache;
        for (var item in libraryItems) {
          final int totalChapters = item.totalEpisodes ?? 0;
          final int startBaseline = prefs.getInt('notif_start_chapter_manga_${item.id}') ?? totalChapters;
          final int startNew = max(item.watchedEpisodes, startBaseline) + 1;
          if (totalChapters >= startNew) {
            final cached = cache[item.id];
            final int endNew = totalChapters;
            final String message = startNew == endNew
                ? 'Chapter $startNew is now available!'
                : 'Chapters $startNew-$endNew are now available!';

            generated.add({
              'id': item.id,
              'media': cached ?? {},
              'title': cached?['title'] ?? 'Manga #${item.id}',
              'coverImage': cached?['thumbnailUrl'] ?? '',
              'message': message,
              'latestReleased': totalChapters,
              'watchedCount': item.watchedEpisodes,
              'status': cached?['status'] ?? '',
              'releaseTime': item.addedAt.millisecondsSinceEpoch,
            });
          }
        }
      }

      // Sort notifications by releaseTime descending (most recent first)
      generated.sort((a, b) => (b['releaseTime'] as int).compareTo(a['releaseTime'] as int));

      if (mounted) {
        setState(() {
          _notifications = generated;
          _isLoading = false;
        });
        LibraryState().clearNotificationBadge(widget.mode);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
        LibraryState().clearNotificationBadge(widget.mode);
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
                                      if (widget.mode == AppMode.anime || widget.mode == AppMode.manga) {
                                        widget.navigationState.selectAnime(notif['id']);
                                      } else {
                                        widget.navigationState.selectMovie('series:${notif['id']}');
                                      }
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
