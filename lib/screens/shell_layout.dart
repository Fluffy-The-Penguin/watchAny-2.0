import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../state/navigation_state.dart';
import '../state/player_state.dart';
import '../state/library_state.dart';
import '../services/update_service.dart';
import '../services/anilist_service.dart';
import '../state/app_settings.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/update_circular_progress_badge.dart';
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
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/library_providers.dart';
import 'movies_details_page.dart';
import 'profile_page.dart';
import '../state/anilist_auth_state.dart';
import 'manga_details_page.dart';

class ShellLayout extends StatelessWidget {
  final NavigationState navigationState;

  const ShellLayout({
    super.key,
    required this.navigationState,
  });



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
      case TabPage.profile:
        return 'Profile';
      case TabPage.settings:
        return 'Settings';
    }
  }


  List<BottomNavigationBarItem> _buildBottomTabs(AppMode mode) {
    if (mode == AppMode.anime) {
      return const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
        BottomNavigationBarItem(icon: Icon(Icons.video_library), label: 'Library'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Schedule'),
        BottomNavigationBarItem(icon: Icon(Icons.download_for_offline), label: 'Downloads'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
      ];
    } else if (mode == AppMode.manga) {
      return const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
        BottomNavigationBarItem(icon: Icon(Icons.video_library), label: 'Library'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
      ];
    } else {
      return const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
        BottomNavigationBarItem(icon: Icon(Icons.video_library), label: 'Library'),
        BottomNavigationBarItem(icon: Icon(Icons.download_for_offline), label: 'Downloads'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
      ];
    }
  }

  int _getTabIndexMobile(TabPage page, AppMode mode) {
    if (mode == AppMode.anime) {
      switch (page) {
        case TabPage.home: return 0;
        case TabPage.search: return 1;
        case TabPage.library: return 2;
        case TabPage.schedule: return 3;
        case TabPage.downloads: return 4;
        case TabPage.settings: return 5;
        default: return 0;
      }
    } else if (mode == AppMode.manga) {
      switch (page) {
        case TabPage.home: return 0;
        case TabPage.search: return 1;
        case TabPage.library: return 2;
        case TabPage.settings: return 3;
        default: return 0;
      }
    } else {
      switch (page) {
        case TabPage.home: return 0;
        case TabPage.search: return 1;
        case TabPage.library: return 2;
        case TabPage.downloads: return 3;
        case TabPage.settings: return 4;
        default: return 0;
      }
    }
  }

  TabPage _getTabPageFromIndex(int index, AppMode mode) {
    if (mode == AppMode.anime) {
      switch (index) {
        case 0: return TabPage.home;
        case 1: return TabPage.search;
        case 2: return TabPage.library;
        case 3: return TabPage.schedule;
        case 4: return TabPage.downloads;
        case 5: return TabPage.settings;
        default: return TabPage.home;
      }
    } else if (mode == AppMode.manga) {
      switch (index) {
        case 0: return TabPage.home;
        case 1: return TabPage.search;
        case 2: return TabPage.library;
        case 3: return TabPage.settings;
        default: return TabPage.home;
      }
    } else {
      switch (index) {
        case 0: return TabPage.home;
        case 1: return TabPage.search;
        case 2: return TabPage.library;
        case 3: return TabPage.downloads;
        case 4: return TabPage.settings;
        default: return TabPage.home;
      }
    }
  }

  void _showMobileModeSelector(BuildContext context) {
    final enabledModes = AppSettings().enabledModesList;
    IconData _modeIcon(AppMode mode) {
      switch (mode) {
        case AppMode.anime: return Icons.movie_creation_outlined;
        case AppMode.manga: return Icons.menu_book_outlined;
        case AppMode.movies: return Icons.tv_outlined;
      }
    }
    String _modeLabel(AppMode mode) {
      switch (mode) {
        case AppMode.anime: return 'Anime';
        case AppMode.manga: return 'Manga';
        case AppMode.movies: return 'Movies & Webseries';
      }
    }
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
              ...enabledModes.map((mode) => ListTile(
                leading: Icon(_modeIcon(mode), color: Colors.white70),
                title: Text(_modeLabel(mode), style: const TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                onTap: () {
                  navigationState.setMode(mode);
                  Navigator.pop(context);
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StartupUpdateChecker(
      child: ListenableBuilder(
        listenable: Listenable.merge([navigationState, PlayerState(), AppSettings()]),
        builder: (context, _) {
        final currentMode = navigationState.currentMode;
        final currentPage = navigationState.currentPage;
        final selectedAnimeId = navigationState.selectedAnimeId;

        final double screenWidth = MediaQuery.of(context).size.width;
        final double screenHeight = MediaQuery.of(context).size.height;
        final bool isMobile = screenWidth < 650;

        final playerState = PlayerState();
        final showFullPlayer = playerState.isActive && !playerState.isMinimized;
        final showMiniPlayer = playerState.isActive && playerState.isMinimized;

        final bool isDetailsOpen = selectedAnimeId != null ||
            navigationState.selectedMovieId != null ||
            navigationState.selectedMangaId != null;

        final bool isBottomNavVisible = isMobile && !isDetailsOpen && !showFullPlayer;

        final double statusBarHeight = MediaQuery.of(context).padding.top;
        final double bottomSafeArea = MediaQuery.of(context).padding.bottom;
        final double appBarHeight = (isMobile && !showFullPlayer && !isDetailsOpen) ? 56.0 : 0.0;
        final double bottomNavBarHeight = isBottomNavVisible ? (56.0 + bottomSafeArea) : 0.0;
        final double miniPlayerBottomOffset = 12.0 + bottomNavBarHeight + (isBottomNavVisible ? 0.0 : bottomSafeArea);
        final double layoutTopOffset = statusBarHeight + appBarHeight;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: isMobile && !showFullPlayer && !isDetailsOpen
              ? AppBar(
                  backgroundColor: Colors.black,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  title: Text(
                    '${navigationState.modeLabel} - ${_getPageTitle(currentPage)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Outfit',
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  leading: null,
                  actions: [
                    if (!isDetailsOpen) ...[
                      ListenableBuilder(
                        listenable: AnilistAuthState(),
                        builder: (context, child) {
                          final authState = AnilistAuthState();
                          return Tooltip(
                            message: 'User Profile',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                navigationState.setPage(TabPage.profile);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                                child: CircleAvatar(
                                  radius: 12.0,
                                  backgroundImage: authState.isLoggedIn && authState.avatarUrl != null
                                      ? NetworkImage(authState.avatarUrl!)
                                      : null,
                                  backgroundColor: Colors.white10,
                                  child: !authState.isLoggedIn || authState.avatarUrl == null
                                      ? const Icon(Icons.account_circle, color: Colors.white70, size: 16.0)
                                      : null,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
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
                      Consumer(
                        builder: (context, ref, child) {
                          final int count;
                          if (navigationState.currentMode == AppMode.anime) {
                            count = ref.watch(animeNotificationCountProvider);
                          } else if (navigationState.currentMode == AppMode.manga) {
                            count = ref.watch(mangaNotificationCountProvider);
                          } else {
                            count = ref.watch(moviesNotificationCountProvider);
                          }

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
                      if (AppSettings().enabledModesList.length > 1)
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
                  currentIndex: _getTabIndexMobile(currentPage, currentMode),
                  type: BottomNavigationBarType.fixed,
                  selectedLabelStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 11),
                  unselectedLabelStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 11),
                  items: _buildBottomTabs(currentMode),
                  onTap: (index) {
                    navigationState.setPage(_getTabPageFromIndex(index, currentMode));
                  },
                )
              : null,
          body: PopScope(
            canPop: !(showFullPlayer ||
                navigationState.activeChapterId != null ||
                isDetailsOpen ||
                currentPage != TabPage.home),
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              if (showFullPlayer) {
                playerState.minimize();
              } else if (navigationState.activeChapterId != null) {
                navigationState.stopReading();
              } else if (navigationState.selectedAnimeId != null) {
                navigationState.selectAnime(null);
              } else if (navigationState.selectedMovieId != null) {
                navigationState.selectMovie(null);
              } else if (navigationState.selectedMangaId != null) {
                navigationState.selectManga(null);
              } else if (currentPage != TabPage.home) {
                navigationState.setPage(TabPage.home);
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
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: _buildDoubleNestedIndexedStack(currentMode, currentPage),
                                  ),
                                  Positioned.fill(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      child: _buildDetailsOverlayWidget(currentMode, selectedAnimeId),
                                    ),
                                  ),
                                ],
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
                          if (AppSettings().offlineMode)
                            Positioned(
                              top: (!isMobile && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ? 32.0 : 0.0,
                              left: 0,
                              right: 0,
                              child: Material(
                                color: const Color(0xFFFF9F1C).withOpacity(0.95),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.wifi_off, color: Colors.black, size: 14.0),
                                      SizedBox(width: 8.0),
                                      Text(
                                        'Offline Mode Active (Showing local library downloads)',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (isMobile)
                            const Positioned(
                              top: 8.0,
                              right: 12.0,
                              child: UpdateCircularProgressBadge(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                // Player Overlay (Full Screen & Mini Player)
                if (playerState.isActive)
                  AnimatedPositioned(
                    key: const ValueKey('player_animated_container'),
                    duration: playerState.isDraggingMiniPlayer 
                        ? Duration.zero 
                        : const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    left: playerState.isMinimized 
                        ? (screenWidth - 280.0 - 12.0 + playerState.miniPlayerOffset.dx) 
                        : 0.0,
                    top: playerState.isMinimized 
                        ? (screenHeight - 158.0 - miniPlayerBottomOffset - layoutTopOffset + playerState.miniPlayerOffset.dy) 
                        : 0.0,
                    width: playerState.isMinimized ? 280.0 : screenWidth,
                    height: playerState.isMinimized ? 158.0 : screenHeight,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: playerState.isMinimized ? const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 15.0,
                              spreadRadius: 2.0,
                              offset: Offset(0, 4),
                            ),
                          ] : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(playerState.isMinimized ? 12.0 : 0.0),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: playerState.isMinimized
                                ? GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onPanStart: (_) {
                                      playerState.setDraggingMiniPlayer(true);
                                    },
                                    onPanUpdate: (details) {
                                      final defaultLeft = screenWidth - 280.0 - 12.0;
                                      final defaultTop = screenHeight - 158.0 - miniPlayerBottomOffset - layoutTopOffset;

                                      final proposedLeft = defaultLeft + playerState.miniPlayerOffset.dx + details.delta.dx;
                                      final proposedTop = defaultTop + playerState.miniPlayerOffset.dy + details.delta.dy;

                                      final clampedLeft = proposedLeft.clamp(12.0, screenWidth - 280.0 - 12.0);
                                      final clampedTop = proposedTop.clamp(12.0, screenHeight - 158.0 - 12.0);

                                      final dx = clampedLeft - defaultLeft;
                                      final dy = clampedTop - defaultTop;

                                      playerState.setMiniPlayerOffset(Offset(dx, dy));
                                    },
                                    onPanEnd: (_) {
                                      playerState.setDraggingMiniPlayer(false);
                                    },
                                    child: const MiniPlayer(key: ValueKey('mini')),
                                  )
                                : PlayerScreen(
                                    key: const ValueKey('full'),
                                    streamUrl: playerState.streamUrl!,
                                    title: playerState.title!,
                                    anilistId: playerState.anilistId,
                                    titles: playerState.titles,
                                    episodeCount: playerState.episodeCount,
                                    episodeNumber: playerState.episodeNumber,
                                    isMovie: playerState.isMovie,
                                    media: playerState.media,
                                    episodes: playerState.episodes,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),


              ],
            ),
          ),
        );
      },
    ),
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

  Widget? _buildDetailsOverlayWidget(AppMode currentMode, int? selectedAnimeId) {
    if (currentMode == AppMode.anime && selectedAnimeId != null) {
      return AnimeDetailsPage(
        key: ValueKey('details_$selectedAnimeId'),
        animeId: selectedAnimeId,
        navigationState: navigationState,
      );
    }
    if (currentMode == AppMode.movies && navigationState.selectedMovieId != null) {
      return MovieDetailsPage(
        key: ValueKey('details_movie_${navigationState.selectedMovieId}'),
        movieId: navigationState.selectedMovieId!,
        navigationState: navigationState,
      );
    }
    if (currentMode == AppMode.manga && navigationState.selectedMangaId != null) {
      return MangaDetailsPage(
        key: ValueKey('details_manga_${navigationState.selectedMangaId}'),
        mangaId: navigationState.selectedMangaId!,
        navigationState: navigationState,
      );
    }
    return null;
  }

  Widget _buildDoubleNestedIndexedStack(AppMode currentMode, TabPage currentPage) {
    return _LazyPageStack(
      key: const ValueKey('lazy_page_stack'),
      currentMode: currentMode,
      currentPage: currentPage,
      navigationState: navigationState,
    );
  }
}

/// A StatefulWidget that lazily builds pages only when they are first navigated to.
/// Previously, all 25 pages were built simultaneously via nested IndexedStack widgets.
/// Now only the active page is built on first render; others are built on-demand and cached.
class _LazyPageStack extends StatefulWidget {
  final AppMode currentMode;
  final TabPage currentPage;
  final NavigationState navigationState;

  const _LazyPageStack({
    super.key,
    required this.currentMode,
    required this.currentPage,
    required this.navigationState,
  });

  @override
  State<_LazyPageStack> createState() => _LazyPageStackState();
}

class _LazyPageStackState extends State<_LazyPageStack> {
  // Track which (mode, pageIndex) combinations have been visited
  final Set<String> _builtKeys = {};

  // Page definitions per mode
  static const List<TabPage> _animePages = [
    TabPage.home, TabPage.search, TabPage.library, TabPage.schedule,
    TabPage.downloads, TabPage.settings, TabPage.history,
    TabPage.notifications, TabPage.profile,
  ];
  static const List<TabPage> _mangaPages = [
    TabPage.home, TabPage.search, TabPage.library,
    TabPage.settings, TabPage.history,
    TabPage.notifications, TabPage.profile,
  ];
  static const List<TabPage> _otherPages = [
    TabPage.home, TabPage.search, TabPage.library,
    TabPage.downloads, TabPage.settings, TabPage.history,
    TabPage.notifications, TabPage.profile,
  ];

  List<TabPage> _pagesForMode(AppMode mode) {
    if (mode == AppMode.anime) return _animePages;
    if (mode == AppMode.manga) return _mangaPages;
    return _otherPages;
  }

  int _pageIndex(TabPage page, AppMode mode) {
    final pages = _pagesForMode(mode);
    final idx = pages.indexOf(page);
    return idx >= 0 ? idx : 0;
  }

  String _key(AppMode mode, int pageIdx) => '${mode.name}_$pageIdx';

  Widget _buildPage(AppMode mode, TabPage page) {
    final nav = widget.navigationState;
    switch (page) {
      case TabPage.home:
        return HomePage(key: ValueKey('home_${mode.name}'), mode: mode, navigationState: nav);
      case TabPage.search:
        return SearchPage(key: ValueKey('search_${mode.name}'), mode: mode, navigationState: nav);
      case TabPage.library:
        return LibraryPage(key: ValueKey('library_${mode.name}'), mode: mode, navigationState: nav);
      case TabPage.schedule:
        return SchedulePage(key: ValueKey('schedule_${mode.name}'), navigationState: nav);
      case TabPage.downloads:
        return DownloadsPage(key: ValueKey('downloads_${mode.name}'), mode: mode);
      case TabPage.settings:
        return SettingsPage(key: ValueKey('settings_${mode.name}'), mode: mode);
      case TabPage.history:
        return HistoryPage(key: ValueKey('history_${mode.name}'), mode: mode, navigationState: nav);
      case TabPage.notifications:
        return NotificationsPage(key: ValueKey('notifications_${mode.name}'), mode: mode, navigationState: nav);
      case TabPage.profile:
        return ProfilePage(key: ValueKey('profile_${mode.name}'), navigationState: nav);
    }
  }

  // Track last active page index for each mode
  final Map<AppMode, int> _lastPageIndex = {};

  @override
  Widget build(BuildContext context) {
    final currentMode = widget.currentMode;
    final currentPage = widget.currentPage;
    final enabledModes = AppSettings().enabledModesList;
    final modeIndex = enabledModes.indexOf(currentMode).clamp(0, enabledModes.length - 1);
    final pageIndex = _pageIndex(currentPage, currentMode);

    // Save active page index for current mode
    _lastPageIndex[currentMode] = pageIndex;

    // Mark the current (mode, page) as visited so it gets built
    _builtKeys.add(_key(currentMode, pageIndex));

    return IndexedStack(
      key: const ValueKey('outer_indexed_stack'),
      index: modeIndex,
      children: enabledModes.map((mode) {
        return _buildModeStack(mode);
      }).toList(),
    );
  }

  Widget _buildModeStack(AppMode mode) {
    final pages = _pagesForMode(mode);
    final displayIndex = (_lastPageIndex[mode] ?? 0).clamp(0, pages.length - 1);

    return IndexedStack(
      key: ValueKey('${mode.name}_pages_stack'),
      index: displayIndex,
      children: List.generate(pages.length, (i) {
        final key = _key(mode, i);
        if (_builtKeys.contains(key)) {
          return _buildPage(mode, pages[i]);
        }
        // Placeholder for pages not yet visited — zero cost
        return const SizedBox.shrink();
      }),
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
    try {
      final items = await PlayerState.getHistoryList();
      
      // Filter history items by active mode partition
      final filtered = items.where((item) {
        final isAnime = item['isAnime'] ?? true;
        final isManga = item['isManga'] ?? false;
        if (widget.mode == AppMode.manga) {
          return isManga;
        } else if (widget.mode == AppMode.movies) {
          return !isAnime && !isManga;
        } else if (widget.mode == AppMode.anime) {
          return isAnime && !isManga;
        } else {
          return false;
        }
      }).toList();

      if (mounted) {
        setState(() {
          _items = filtered.take(4).toList();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _items = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
        final isManga = item['isManga'] ?? false;
        final eps = item['episodes'] as List<int>;

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: SizedBox(
              width: 32.0,
              height: 46.0,
              child: cover.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      memCacheWidth: 80,
                      placeholder: (c, u) => Container(color: Colors.grey[950]),
                      errorWidget: (c, u, e) => Container(color: Colors.grey[950]),
                    )
                  : Container(color: Colors.grey[950]),
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.0),
          ),
          subtitle: Text(
            '${isManga ? 'Chapters' : 'Episodes'}: ${_formatEpisodeRanges(eps)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF3A86FF), fontSize: 10.5),
          ),
          onTap: () {
            Navigator.pop(context);
            if (isManga) {
              widget.navigationState.selectManga(item['id'].toString());
            } else if (item['isAnime'] ?? true) {
              final idInt = int.tryParse(item['id'].toString());
              if (idInt != null) {
                widget.navigationState.selectAnime(idInt);
              }
            } else {
              widget.navigationState.selectMovie(item['id'].toString());
            }
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
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _items = [];
  int _visibleCount = 4;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 20) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (_items.length < _allItems.length) {
      setState(() {
        _visibleCount += 4;
        _items = _allItems.take(_visibleCount).toList();
      });
    }
  }

  Future<void> _load() async {
    final String localModeStr = widget.mode == AppMode.manga
        ? 'manga'
        : (widget.mode == AppMode.movies ? 'movies' : 'anime');

    final libraryItems = LibraryState().items.where((item) => item.mode == localModeStr).toList();
    if (libraryItems.isEmpty) {
      if (mounted) setState(() { _items = []; _isLoading = false; });
      return;
    }

    final startMap = await LibraryState().getNotificationStartMap();
    final ackMap = await LibraryState().getNotificationAckMap();
    final List<Map<String, dynamic>> generated = [];

    try {
      if (widget.mode == AppMode.anime) {
        final ids = libraryItems.map((item) => item.id).toList();
        final List<dynamic> details = await AnilistService().fetchLibraryDetails(ids, type: 'ANIME');
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

          final int startBaseline = ackMap['anime_$id'] ?? startMap['anime_$id'] ?? latestReleased;
          final int startNew = max(localItem.watchedEpisodes, startBaseline) + 1;

          if (latestReleased >= startNew) {
            final int endNew = latestReleased;
            final String message = startNew == endNew
                ? 'Episode $startNew is out!'
                : 'Episodes $startNew-$endNew are out!';

            generated.add({
              'id': id,
              'title': media['title']?['english'] ?? media['title']?['romaji'] ?? 'Untitled',
              'cover': media['coverImage']?['large'] ?? '',
              'message': message,
              'releaseTime': releaseTime,
            });
          }
        }
      } else if (widget.mode == AppMode.manga) {
        final cache = LibraryState().mangaCache;
        for (var item in libraryItems) {
          final int totalChapters = item.totalEpisodes ?? 0;
          final int startBaseline = ackMap['manga_${item.id}'] ?? startMap['manga_${item.id}'] ?? totalChapters;
          final int startNew = max(item.watchedEpisodes, startBaseline) + 1;
          if (totalChapters >= startNew) {
            final cached = cache[item.id];
            final int endNew = totalChapters;
            final String message = startNew == endNew
                ? 'Chapter $startNew is out!'
                : 'Chapters $startNew-$endNew are out!';

            generated.add({
              'id': item.id,
              'title': cached?['title'] ?? 'Manga #${item.id}',
              'cover': cached?['thumbnailUrl'] ?? '',
              'message': message,
              'releaseTime': item.addedAt.millisecondsSinceEpoch ~/ 1000,
            });
          }
        }
      } else if (widget.mode == AppMode.movies) {
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
                
                final int startBaseline = ackMap['movies_${localItem.id}'] ?? startMap['movies_${localItem.id}'] ?? latestReleased;
                final int startNew = max(localItem.watchedEpisodes, startBaseline) + 1;

                if (latestReleased >= startNew) {
                  final int endNew = latestReleased;
                  final String message = startNew == endNew
                      ? 'Episode $startNew is out!'
                      : 'Episodes $startNew-$endNew are out!';
                      
                  generated.add({
                    'id': localItem.id,
                    'title': meta['name'] ?? 'Untitled',
                    'cover': meta['poster'] ?? '',
                    'message': message,
                    'releaseTime': DateTime.tryParse(meta['released']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0,
                  });
                }
              }
            }
          } catch (_) {}
        });
        await Future.wait(futures);
      }

      // Sort notifications by releaseTime descending (most recent first)
      generated.sort((a, b) => (b['releaseTime'] as int).compareTo(a['releaseTime'] as int));

      if (mounted) {
        setState(() {
          _allItems = generated;
          _items = _allItems.take(_visibleCount).toList();
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
      controller: _scrollController,
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
              child: cover.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      memCacheWidth: 80,
                      placeholder: (c, u) => Container(color: Colors.grey[950]),
                      errorWidget: (c, u, e) => Container(color: Colors.grey[950]),
                    )
                  : Container(color: Colors.grey[950]),
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

class StartupUpdateChecker extends StatefulWidget {
  final Widget child;
  const StartupUpdateChecker({super.key, required this.child});

  @override
  State<StartupUpdateChecker> createState() => _StartupUpdateCheckerState();
}

class _StartupUpdateCheckerState extends State<StartupUpdateChecker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdatesOnStartup();
    });
  }

  void _checkUpdatesOnStartup() async {
    final updateService = UpdateService();
    await updateService.loadCachedUpdateInfo();
    final hasUpdate = await updateService.checkForUpdates();

    if (!mounted) return;

    if (updateService.isUpdateReady) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF16161A),
            title: Text(
              'Update Ready to Install (${updateService.downloadedVersion})',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Outfit',
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const Text(
              'The update has been downloaded and verified on your device. Would you like to install it now?',
              style: TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontSize: 13.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Install Later', style: TextStyle(color: Colors.white38, fontFamily: 'Outfit')),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2EC4B6),
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  updateService.launchInstaller();
                },
                child: const Text('Install Now', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
      return;
    }

    if (!hasUpdate || updateService.latestUpdate == null) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          title: Text(
            'Update Available (${updateService.latestUpdate!.version})',
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Outfit',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Container(
            width: MediaQuery.of(context).size.width.clamp(0.0, 480.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A new version of watchAny is available! What\'s new:',
                    style: TextStyle(color: Colors.white70, fontFamily: 'Outfit', fontSize: 13.5),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      updateService.latestUpdate!.changelog,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontFamily: 'Outfit',
                        fontSize: 12.0,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (updateService.latestUpdate != null) {
                  updateService.skipVersion(updateService.latestUpdate!.version);
                }
                Navigator.pop(context);
              },
              child: const Text('Skip Version', style: TextStyle(color: Colors.redAccent, fontFamily: 'Outfit')),
            ),
            TextButton(
              onPressed: () {
                if (updateService.latestUpdate != null) {
                  updateService.dismissUpdate(updateService.latestUpdate!.version);
                }
                Navigator.pop(context);
              },
              child: const Text('Remind Later', style: TextStyle(color: Colors.white38, fontFamily: 'Outfit')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9F1C),
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.pop(context);
                updateService.startUpdate();
              },
              child: const Text('Download Update', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
