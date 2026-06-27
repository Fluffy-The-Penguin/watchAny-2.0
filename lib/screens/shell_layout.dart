import 'dart:io';
import 'package:flutter/material.dart';
import '../state/navigation_state.dart';
import '../state/player_state.dart';
import '../state/library_state.dart';
import '../services/anilist_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/sidebar.dart';
import '../widgets/mini_player.dart';
import 'home_page.dart';
import 'search_page.dart';
import 'library_page.dart';
import 'anime_details_page.dart';
import 'settings_page.dart';
import 'downloads_page.dart';
import 'player_screen.dart';
import 'schedule_page.dart';
import 'history_page.dart';
import 'notifications_page.dart';

class ShellLayout extends StatelessWidget {
  final NavigationState navigationState;

  const ShellLayout({
    super.key,
    required this.navigationState,
  });

  Widget _buildContent(AppMode mode, TabPage page) {
    switch (page) {
      case TabPage.home:
        return HomePage(key: ValueKey('home_$mode'), mode: mode, navigationState: navigationState);
      case TabPage.search:
        return SearchPage(key: ValueKey('search_$mode'), mode: mode, navigationState: navigationState);
      case TabPage.library:
        return LibraryPage(key: ValueKey('library_$mode'), mode: mode, navigationState: navigationState);
      case TabPage.downloads:
        return DownloadsPage(key: ValueKey('downloads_$mode'), mode: mode);
      case TabPage.settings:
        return SettingsPage(key: ValueKey('settings_$mode'));
      case TabPage.schedule:
        return SchedulePage(
          key: ValueKey('schedule_$mode'),
          navigationState: navigationState,
        );
      case TabPage.history:
        return HistoryPage(key: ValueKey('history_$mode'), mode: mode, navigationState: navigationState);
      case TabPage.notifications:
        return NotificationsPage(key: ValueKey('notifications_$mode'), mode: mode, navigationState: navigationState);
    }
  }

  String _getPageTitle(TabPage page) {
    switch (page) {
      case TabPage.home:
        return 'Home';
      case TabPage.search:
        return 'Search';
      case TabPage.library:
        return 'Library';
      case TabPage.schedule:
        return 'Schedule';
      case TabPage.downloads:
        return 'Downloads';
      case TabPage.history:
        return 'Watch History';
      case TabPage.notifications:
        return 'Notifications';
      case TabPage.settings:
        return 'Settings';
    }
  }


  int _getTabIndexMobile(TabPage page) {
    switch (page) {
      case TabPage.home: return 0;
      case TabPage.search: return 1;
      case TabPage.library: return 2;
      case TabPage.schedule: return 3;
      case TabPage.downloads: return 4;
      case TabPage.settings: return 5;
      default: return 0;
    }
  }

  TabPage _getTabPageFromIndex(int index) {
    switch (index) {
      case 0:
        return TabPage.home;
      case 1:
        return TabPage.search;
      case 2:
        return TabPage.library;
      case 3:
        return TabPage.schedule;
      case 4:
        return TabPage.downloads;
      case 5:
        return TabPage.history;
      case 6:
        return TabPage.notifications;
      case 7:
        return TabPage.settings;
      default:
        return TabPage.home;
    }
  }

  void _showMobileModeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F11),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  'Select Mode',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Outfit',
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.movie_creation_outlined, color: Colors.white70),
                title: const Text('Anime', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                onTap: () {
                  navigationState.setMode(AppMode.anime);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined, color: Colors.white70),
                title: const Text('Manga', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                onTap: () {
                  navigationState.setMode(AppMode.manga);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.tv_outlined, color: Colors.white70),
                title: const Text('Movies & Webseries', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                onTap: () {
                  navigationState.setMode(AppMode.movies);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([navigationState, PlayerState()]),
      builder: (context, _) {
        final currentMode = navigationState.currentMode;
        final currentPage = navigationState.currentPage;
        final selectedAnimeId = navigationState.selectedAnimeId;

        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isMobile = screenWidth < 650;

        final playerState = PlayerState();
        final showFullPlayer = playerState.isActive && !playerState.isMinimized;
        final showMiniPlayer = playerState.isActive && playerState.isMinimized;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: isMobile && !showFullPlayer
              ? AppBar(
                  backgroundColor: Colors.black,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  title: Text(
                    selectedAnimeId != null 
                        ? 'Details' 
                        : '${navigationState.modeLabel} - ${_getPageTitle(currentPage)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Outfit',
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  leading: selectedAnimeId != null
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => navigationState.selectAnime(null),
                        )
                      : null,
                  actions: [
                    if (selectedAnimeId == null) ...[
                      IconButton(
                        icon: const Icon(Icons.history, color: Colors.white70),
                        tooltip: 'History',
                        onPressed: () => _showSidebarPopup(
                          context: context,
                          title: 'History',
                          content: _HistoryPopupContent(mode: navigationState.currentMode, navigationState: navigationState),
                          onViewAll: () => navigationState.setPage(TabPage.history),
                        ),
                      ),
                      ListenableBuilder(
                        listenable: LibraryState(),
                        builder: (context, child) {
                          final count = LibraryState().getNotificationCount(navigationState.currentMode);
                          return IconButton(
                            icon: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(Icons.notifications, color: Colors.white70),
                                if (count > 0)
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2EC4B6),
                                        borderRadius: BorderRadius.circular(10.0),
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 12.0,
                                        minHeight: 12.0,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '$count',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 7.5,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Outfit',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            onPressed: () {
                              LibraryState().clearNotificationBadge(navigationState.currentMode);
                              _showSidebarPopup(
                                context: context,
                                title: 'Notifications',
                                content: _NotificationsPopupContent(mode: navigationState.currentMode, navigationState: navigationState),
                                onViewAll: () => navigationState.setPage(TabPage.notifications),
                              );
                            },
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.swap_horiz, color: Colors.white70),
                        tooltip: 'Switch Mode',
                        onPressed: () => _showMobileModeSelector(context),
                      ),
                    ],
                  ],
                )
              : null,
          bottomNavigationBar: isMobile && selectedAnimeId == null && !showFullPlayer
              ? BottomNavigationBar(
                  backgroundColor: const Color(0xFF0F0F11),
                  selectedItemColor: Colors.white,
                  unselectedItemColor: Colors.white30,
                  currentIndex: _getTabIndexMobile(currentPage),
                  type: BottomNavigationBarType.fixed,
                  selectedLabelStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 11),
                  unselectedLabelStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 11),
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
                    BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
                    BottomNavigationBarItem(icon: Icon(Icons.video_library), label: 'Library'),
                    BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Schedule'),
                    BottomNavigationBarItem(icon: Icon(Icons.download_for_offline), label: 'Downloads'),
                    BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
                  ],
                  onTap: (index) {
                    navigationState.setPage(_getTabPageFromIndex(index == 5 ? 7 : index));
                  },
                )
              : null,
          body: PopScope(
            canPop: !showFullPlayer,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              if (showFullPlayer) {
                playerState.minimize();
              }
            },
            child: Stack(
              children: [
                // Main layout: Sidebar + Content Window
                Row(
                  children: [
                    // Left Sidebar (Desktop only)
                    if (!isMobile)
                      Sidebar(
                        state: navigationState,
                        onHistoryTap: () => _showSidebarPopup(
                          context: context,
                          title: 'History',
                          content: _HistoryPopupContent(mode: navigationState.currentMode, navigationState: navigationState),
                          onViewAll: () => navigationState.setPage(TabPage.history),
                        ),
                        onNotificationsTap: () {
                          LibraryState().clearNotificationBadge(navigationState.currentMode);
                          _showSidebarPopup(
                            context: context,
                            title: 'Notifications',
                            content: _NotificationsPopupContent(mode: navigationState.currentMode, navigationState: navigationState),
                            onViewAll: () => navigationState.setPage(TabPage.notifications),
                          );
                        },
                      ),
                    
                    // Right Content Window (Stack containing full content and floating controls)
                    Expanded(
                      child: Stack(
                        children: [
                          // Main Content Window - takes full area
                          Positioned.fill(
                            child: Container(
                              color: Colors.black,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: selectedAnimeId != null
                                    ? AnimeDetailsPage(
                                        key: ValueKey('details_$selectedAnimeId'),
                                        animeId: selectedAnimeId,
                                        navigationState: navigationState,
                                      )
                                    : _buildContent(currentMode, currentPage),
                              ),
                            ),
                          ),
                          
                          // Floating Custom Title Bar (Desktop only)
                          if (!isMobile && (Platform.isWindows || Platform.isMacOS || Platform.isLinux))
                            const Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: CustomTitleBar(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                // Full Screen Player Overlay
                if (showFullPlayer)
                  Positioned.fill(
                    child: PlayerScreen(
                      streamUrl: playerState.streamUrl!,
                      title: playerState.title!,
                      anilistId: playerState.anilistId,
                      titles: playerState.titles,
                      episodeCount: playerState.episodeCount,
                      episodeNumber: playerState.episodeNumber,
                      isMovie: playerState.isMovie,
                      media: playerState.media,
                      episodes: playerState.episodes,
                      tmdbEpisodesMap: playerState.tmdbEpisodesMap,
                    ),
                  ),
                
                // Floating MiniPlayer Overlay
                if (showMiniPlayer)
                  Positioned(
                    right: 16.0,
                    bottom: 16.0,
                    child: const SafeArea(
                      child: MiniPlayer(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSidebarPopup({
    required BuildContext context,
    required String title,
    required Widget content,
    required VoidCallback onViewAll,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Container();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isMobile = screenWidth < 650;
        
        final slideTween = isMobile
            ? Tween<Offset>(begin: const Offset(0.0, 0.15), end: Offset.zero)
            : Tween<Offset>(begin: const Offset(-0.15, 0.0), end: Offset.zero);
            
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return FadeTransition(
          opacity: curvedAnimation,
          child: SlideTransition(
            position: slideTween.animate(curvedAnimation),
            child: Stack(
              children: [
                Positioned(
                  left: isMobile ? 16.0 : 68.0,
                  right: isMobile ? 16.0 : null,
                  top: isMobile ? null : 180.0,
                  bottom: isMobile ? 80.0 : null,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: isMobile ? screenWidth - 32.0 : 320.0,
                      height: 340.0,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F11),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.85),
                            blurRadius: 16.0,
                            spreadRadius: 4.0,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white54, size: 16.0),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          ),
                          Container(height: 1.0, color: Colors.white.withValues(alpha: 0.05)),
                          Expanded(child: content),
                          Container(height: 1.0, color: Colors.white.withValues(alpha: 0.05)),
                          InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              onViewAll();
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              alignment: Alignment.center,
                              child: Text(
                                title == 'History' ? 'View Full History' : 'See All Notifications',
                                style: const TextStyle(
                                  color: Color(0xFF3A86FF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.0,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryPopupContent extends StatefulWidget {
  final AppMode mode;
  final NavigationState navigationState;
  const _HistoryPopupContent({required this.mode, required this.navigationState});

  @override
  State<_HistoryPopupContent> createState() => _HistoryPopupContentState();
}

class _HistoryPopupContentState extends State<_HistoryPopupContent> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await PlayerState.getHistoryList();
    
    // Filter history items by active mode
    final filtered = items.where((item) {
      final media = item['media'] ?? {};
      final itemMode = media['mode'];
      final itemFormat = media['format'];
      
      if (widget.mode == AppMode.movies) {
        return itemMode == 'movies' || itemFormat == 'MOVIE';
      } else if (widget.mode == AppMode.anime) {
        return itemMode == 'anime' || (itemMode == null && itemFormat != 'MOVIE');
      } else {
        return false;
      }
    }).toList();

    if (mounted) {
      setState(() {
        _items = filtered.take(4).toList();
        _isLoading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0));
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No watch history found', style: TextStyle(color: Colors.white38, fontSize: 12.0)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final media = item['media'] ?? {};
        final title = media['title'] is Map
            ? (media['title']['english'] ?? media['title']['romaji'] ?? 'Untitled')
            : (media['title'] ?? 'Untitled');
        final cover = media['coverImage'] is Map
            ? (media['coverImage']['large'] ?? media['coverImage']['extraLarge'] ?? '')
            : (media['coverImage'] ?? '');
        final eps = item['episodes'] as List<int>;

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: SizedBox(
              width: 32.0,
              height: 46.0,
              child: cover.isNotEmpty ? Image.network(cover, fit: BoxFit.cover) : Container(color: Colors.grey[950]),
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.0),
          ),
          subtitle: Text(
            'Episodes: ${_formatEpisodeRanges(eps)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF3A86FF), fontSize: 10.5),
          ),
          onTap: () {
            Navigator.pop(context);
            widget.navigationState.selectAnime(item['id']);
          },
        );
      },
    );
  }
}

class _NotificationsPopupContent extends StatefulWidget {
  final AppMode mode;
  final NavigationState navigationState;
  const _NotificationsPopupContent({required this.mode, required this.navigationState});

  @override
  State<_NotificationsPopupContent> createState() => _NotificationsPopupContentState();
}

class _NotificationsPopupContentState extends State<_NotificationsPopupContent> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String localModeStr = widget.mode == AppMode.manga
        ? 'manga'
        : (widget.mode == AppMode.movies ? 'movies' : 'anime');
        
    final String anilistTypeStr = widget.mode == AppMode.manga ? 'MANGA' : 'ANIME';

    final libraryItems = LibraryState().items.where((item) => item.mode == localModeStr).toList();
    if (libraryItems.isEmpty) {
      if (mounted) setState(() { _items = []; _isLoading = false; });
      return;
    }

    final ids = libraryItems.map((item) => item.id).toList();
    try {
      final List<dynamic> details = await AnilistService().fetchLibraryDetails(ids, type: anilistTypeStr);
      final List<Map<String, dynamic>> generated = [];

      for (var media in details) {
        final id = media['id'];
        final localItem = libraryItems.firstWhere((item) => item.id == id);
        
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
            message = startNew == endNew
                ? 'Chapter $startNew is out!'
                : 'Chapters $startNew-$endNew are out!';
          } else {
            message = startNew == endNew
                ? 'Episode $startNew is out!'
                : 'Episodes $startNew-$endNew are out!';
          }

          generated.add({
            'id': id,
            'title': media['title']?['english'] ?? media['title']?['romaji'] ?? 'Untitled',
            'cover': media['coverImage']?['large'] ?? '',
            'message': message,
            'releaseTime': releaseTime,
          });
        }
      }

      // Sort notifications by releaseTime descending (most recent first)
      generated.sort((a, b) => (b['releaseTime'] as int).compareTo(a['releaseTime'] as int));

      if (mounted) {
        setState(() {
          _items = generated.take(4).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0));
    }
    if (_items.isEmpty) {
      return const Center(child: Text('All caught up!', style: TextStyle(color: Colors.white38, fontSize: 12.0)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final title = item['title'];
        final cover = item['cover'];
        final message = item['message'];

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: SizedBox(
              width: 32.0,
              height: 46.0,
              child: cover.isNotEmpty ? Image.network(cover, fit: BoxFit.cover) : Container(color: Colors.grey[950]),
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.0),
          ),
          subtitle: Text(
            message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF2EC4B6), fontSize: 10.5),
          ),
          onTap: () {
            Navigator.pop(context);
            widget.navigationState.selectAnime(item['id']);
          },
        );
      },
    );
  }
}
