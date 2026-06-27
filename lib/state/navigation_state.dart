import 'package:flutter/material.dart';

enum AppMode {
  anime,
  manga,
  movies,
}

enum TabPage {
  home,
  search,
  library,
  schedule,
  downloads,
  history,
  notifications,
  settings,
}

class NavigationState extends ChangeNotifier {
  // Current active mode
  AppMode _currentMode = AppMode.anime;
  
  // Independent active tab page for each mode
  final Map<AppMode, TabPage> _modePages = {
    AppMode.anime: TabPage.home,
    AppMode.manga: TabPage.home,
    AppMode.movies: TabPage.home,
  };

  // Sidebar expanded/collapsed state (collapsed by default)
  bool _isSidebarExpanded = false;

  // Selected Anime ID for details screen navigation
  int? _selectedAnimeId;

  AppMode get currentMode => _currentMode;
  TabPage get currentPage => _modePages[_currentMode] ?? TabPage.home;
  bool get isSidebarExpanded => _isSidebarExpanded;
  int? get selectedAnimeId => _selectedAnimeId;

  void setMode(AppMode mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      _selectedAnimeId = null; // Clear details view when switching modes
      notifyListeners();
    }
  }

  void selectAnime(int? id) {
    if (_selectedAnimeId != id) {
      _selectedAnimeId = id;
      notifyListeners();
    }
  }

  void setPage(TabPage page) {
    if (_selectedAnimeId != null) {
      _selectedAnimeId = null; // Exit details page when clicking a tab
    }
    if (_modePages[_currentMode] != page) {
      _modePages[_currentMode] = page;
      notifyListeners();
    }
  }

  void toggleSidebar() {
    _isSidebarExpanded = !_isSidebarExpanded;
    notifyListeners();
  }

  void setSidebarExpanded(bool expanded) {
    if (_isSidebarExpanded != expanded) {
      _isSidebarExpanded = expanded;
      notifyListeners();
    }
  }

  // Get human readable labels
  String get modeLabel {
    switch (_currentMode) {
      case AppMode.anime:
        return 'Anime';
      case AppMode.manga:
        return 'Manga';
      case AppMode.movies:
        return 'Movies & Webseries';
    }
  }
}
