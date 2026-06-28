import 'package:flutter/material.dart';
import 'app_settings.dart';

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

  NavigationState() {
    final savedMode = AppSettings().startupMode;
    final savedPage = AppSettings().startupPage;
    _currentMode = savedMode;
    if (savedPage == TabPage.schedule && savedMode != AppMode.anime) {
      _modePages[savedMode] = TabPage.home;
    } else {
      _modePages[savedMode] = savedPage;
    }
  }

  // Sidebar expanded/collapsed state (collapsed by default)
  bool _isSidebarExpanded = false;

  // Selected Anime ID for details screen navigation
  int? _selectedAnimeId;

  // Selected Movie ID for details screen navigation
  String? _selectedMovieId;

  // Selected Manga ID for details screen navigation
  String? _selectedMangaId;

  // Active reading chapter details (Manga reader fullscreen overlay)
  String? _activeChapterId;
  int? _activeChapterNumber;
  String? _activeMangaId;
  String? _activeMangaTitle;
  List<dynamic>? _activeMangaChapters;

  AppMode get currentMode => _currentMode;
  TabPage get currentPage => _modePages[_currentMode] ?? TabPage.home;
  bool get isSidebarExpanded => _isSidebarExpanded;
  int? get selectedAnimeId => _selectedAnimeId;
  String? get selectedMovieId => _selectedMovieId;
  String? get selectedMangaId => _selectedMangaId;

  String? get activeChapterId => _activeChapterId;
  int? get activeChapterNumber => _activeChapterNumber;
  String? get activeMangaId => _activeMangaId;
  String? get activeMangaTitle => _activeMangaTitle;
  List<dynamic>? get activeMangaChapters => _activeMangaChapters;

  void setMode(AppMode mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      _selectedAnimeId = null; // Clear details view when switching modes
      _selectedMovieId = null;
      _selectedMangaId = null;
      notifyListeners();
    }
  }

  void selectAnime(int? id) {
    if (_selectedAnimeId != id) {
      _selectedAnimeId = id;
      notifyListeners();
    }
  }

  void selectMovie(String? id) {
    if (_selectedMovieId != id) {
      _selectedMovieId = id;
      notifyListeners();
    }
  }

  void selectManga(String? id) {
    if (_selectedMangaId != id) {
      _selectedMangaId = id;
      notifyListeners();
    }
  }

  void startReading({
    required String chapterId,
    required int chapterNumber,
    required String mangaId,
    required String mangaTitle,
    required List<dynamic> chapters,
  }) {
    _activeChapterId = chapterId;
    _activeChapterNumber = chapterNumber;
    _activeMangaId = mangaId;
    _activeMangaTitle = mangaTitle;
    _activeMangaChapters = chapters;
    notifyListeners();
  }

  void stopReading() {
    _activeChapterId = null;
    _activeChapterNumber = null;
    _activeMangaId = null;
    _activeMangaTitle = null;
    _activeMangaChapters = null;
    notifyListeners();
  }

  void setPage(TabPage page) {
    if (page == TabPage.schedule && _currentMode != AppMode.anime) {
      return;
    }
    if (_selectedAnimeId != null) {
      _selectedAnimeId = null; // Exit details page when clicking a tab
    }
    if (_selectedMovieId != null) {
      _selectedMovieId = null; // Exit movie details page when clicking a tab
    }
    if (_selectedMangaId != null) {
      _selectedMangaId = null; // Exit manga details page when clicking a tab
    }
    stopReading(); // Exit reader when clicking a tab
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
