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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: navigationState,
      builder: (context, _) {
        final currentMode = navigationState.currentMode;
        final currentPage = navigationState.currentPage;
        final selectedAnimeId = navigationState.selectedAnimeId;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Row(
            children: [
              // Left Sidebar
              Sidebar(state: navigationState),
              
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
                    
                    // Floating Custom Title Bar
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
