import 'dart:io';
import 'package:flutter/material.dart';
import '../state/navigation_state.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/sidebar.dart';
import 'home_page.dart';
import 'search_page.dart';
import 'library_page.dart';
import 'anime_details_page.dart';
import 'settings_page.dart';

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
        return LibraryPage(key: ValueKey('library_$mode'), mode: mode);
      case TabPage.settings:
        return SettingsPage(key: ValueKey('settings_$mode'));
      case TabPage.schedule:
        return Center(
          key: ValueKey('schedule_$mode'),
          child: const Text(
            'Schedule Screen (Coming Soon)',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 16.0,
              fontFamily: 'Outfit',
            ),
          ),
        );
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
      case TabPage.settings:
        return 'Settings';
    }
  }

  int _getTabIndex(TabPage page) {
    switch (page) {
      case TabPage.home:
        return 0;
      case TabPage.search:
        return 1;
      case TabPage.library:
        return 2;
      case TabPage.schedule:
        return 3;
      case TabPage.settings:
        return 4;
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
      listenable: navigationState,
      builder: (context, _) {
        final currentMode = navigationState.currentMode;
        final currentPage = navigationState.currentPage;
        final selectedAnimeId = navigationState.selectedAnimeId;

        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isMobile = screenWidth < 650;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: isMobile
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
                    // Mode Selector Button for Mobile
                    if (selectedAnimeId == null)
                      IconButton(
                        icon: const Icon(Icons.swap_horiz, color: Colors.white70),
                        tooltip: 'Switch Mode',
                        onPressed: () => _showMobileModeSelector(context),
                      ),
                  ],
                )
              : null,
          bottomNavigationBar: isMobile && selectedAnimeId == null
              ? BottomNavigationBar(
                  backgroundColor: const Color(0xFF0F0F11),
                  selectedItemColor: Colors.white,
                  unselectedItemColor: Colors.white30,
                  currentIndex: _getTabIndex(currentPage),
                  type: BottomNavigationBarType.fixed,
                  selectedLabelStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 11),
                  unselectedLabelStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 11),
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
                    BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
                    BottomNavigationBarItem(icon: Icon(Icons.video_library), label: 'Library'),
                    BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Schedule'),
                    BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
                  ],
                  onTap: (index) {
                    navigationState.setPage(_getTabPageFromIndex(index));
                  },
                )
              : null,
          body: Row(
            children: [
              // Left Sidebar (Desktop only)
              if (!isMobile) Sidebar(state: navigationState),
              
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
        );
      },
    );
  }
}
