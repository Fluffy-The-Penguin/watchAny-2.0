import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/anilist_service.dart';
import 'navigation_state.dart';

class LibraryItem {
  final int id;
  final String mode; // 'anime', 'manga', 'movies'
  final String format; // 'MOVIE', 'TV', etc.
  final DateTime addedAt;
  final String libraryStatus; // 'watching', 'planning', 'completed', 'paused_dropped'
  final double rating; // 0.0 (no rating) to 10.0
  final int watchedEpisodes;
  final int? totalEpisodes;

  LibraryItem({
    required this.id,
    required this.mode,
    required this.format,
    required this.addedAt,
    required this.libraryStatus,
    required this.rating,
    required this.watchedEpisodes,
    this.totalEpisodes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'mode': mode,
    'format': format,
    'addedAt': addedAt.toIso8601String(),
    'libraryStatus': libraryStatus,
    'rating': rating,
    'watchedEpisodes': watchedEpisodes,
    'totalEpisodes': totalEpisodes,
  };

  factory LibraryItem.fromJson(Map<String, dynamic> json) {
    return LibraryItem(
      id: json['id'],
      mode: json['mode'],
      format: json['format'] ?? '',
      addedAt: DateTime.parse(json['addedAt'] ?? DateTime.now().toIso8601String()),
      libraryStatus: json['libraryStatus'] ?? 'planning',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      watchedEpisodes: json['watchedEpisodes'] ?? 0,
      totalEpisodes: json['totalEpisodes'],
    );
  }
}

class LibraryState extends ChangeNotifier {
  static final LibraryState _instance = LibraryState._internal();
  factory LibraryState() => _instance;
  LibraryState._internal();

  List<LibraryItem> _items = [];
  int _animeNotificationCount = 0;
  int _mangaNotificationCount = 0;
  int _moviesNotificationCount = 0;

  bool _animeBadgeCleared = false;
  bool _mangaBadgeCleared = false;
  bool _moviesBadgeCleared = false;

  List<LibraryItem> get items => _items;

  int getNotificationCount(AppMode mode) {
    if (mode == AppMode.anime) return _animeBadgeCleared ? 0 : _animeNotificationCount;
    if (mode == AppMode.manga) return _mangaBadgeCleared ? 0 : _mangaNotificationCount;
    if (mode == AppMode.movies) return _moviesBadgeCleared ? 0 : _moviesNotificationCount;
    return 0;
  }

  void clearNotificationBadge(AppMode mode) {
    if (mode == AppMode.anime && !_animeBadgeCleared) {
      _animeBadgeCleared = true;
      notifyListeners();
    } else if (mode == AppMode.manga && !_mangaBadgeCleared) {
      _mangaBadgeCleared = true;
      notifyListeners();
    } else if (mode == AppMode.movies && !_moviesBadgeCleared) {
      _moviesBadgeCleared = true;
      notifyListeners();
    }
    acknowledgeNotifications(mode);
  }

  Future<void> acknowledgeNotifications(AppMode mode) async {
    final String localModeStr = mode == AppMode.manga
        ? 'manga'
        : (mode == AppMode.movies ? 'movies' : 'anime');
    final String anilistTypeStr = mode == AppMode.manga ? 'MANGA' : 'ANIME';
    
    final libraryItems = _items.where((item) => item.mode == localModeStr).toList();
    if (libraryItems.isEmpty) return;
    
    final ids = libraryItems.map((item) => item.id).toList();
    try {
      final details = await AnilistService().fetchLibraryDetails(ids, type: anilistTypeStr);
      final prefs = await SharedPreferences.getInstance();
      
      for (var media in details) {
        final id = media['id'];
        final localItem = libraryItems.firstWhere((item) => item.id == id);
        
        final int? nextEpisode = media['nextAiringEpisode']?['episode'];
        final int totalEpisodes = media['episodes'] ?? 0;
        final int totalChapters = media['chapters'] ?? 0;
        
        final int latestReleased = mode == AppMode.manga
            ? totalChapters
            : (nextEpisode != null ? (nextEpisode - 1) : totalEpisodes);
            
        if (latestReleased > localItem.watchedEpisodes) {
          await prefs.setInt('notif_acknowledged_${localModeStr}_$id', latestReleased);
        }
      }
      await updateNotificationCount();
    } catch (_) {}
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString('library_items');
    if (jsonString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        _items = decoded.map((item) => LibraryItem.fromJson(item)).toList();
      } catch (e) {
        debugPrint('Failed to load library items: $e');
      }
    }
    notifyListeners();
    updateNotificationCount();
  }

  bool isSaved(int id, String mode) {
    return _items.any((item) => item.id == id && item.mode == mode);
  }

  LibraryItem? getItem(int id, String mode) {
    try {
      return _items.firstWhere((item) => item.id == id && item.mode == mode);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveItem({
    required int id,
    required String mode,
    required String format,
    required String libraryStatus,
    required double rating,
    required int watchedEpisodes,
    int? totalEpisodes,
  }) async {
    _items.removeWhere((item) => item.id == id && item.mode == mode);
    
    _items.add(LibraryItem(
      id: id,
      mode: mode,
      format: format,
      addedAt: DateTime.now(),
      libraryStatus: libraryStatus,
      rating: rating,
      watchedEpisodes: watchedEpisodes,
      totalEpisodes: totalEpisodes,
    ));
    
    notifyListeners();
    await _persist();
    updateNotificationCount();
  }

  Future<void> removeItem(int id, String mode) async {
    _items.removeWhere((item) => item.id == id && item.mode == mode);
    notifyListeners();
    await _persist();
    updateNotificationCount();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(_items.map((item) => item.toJson()).toList());
    await prefs.setString('library_items', jsonString);
  }

  Future<void> updateNotificationCount() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. ANIME
    final animeItems = _items.where((item) => item.mode == 'anime').toList();
    int animeCount = 0;
    if (animeItems.isNotEmpty) {
      final ids = animeItems.map((item) => item.id).toList();
      try {
        final details = await AnilistService().fetchLibraryDetails(ids, type: 'ANIME');
        for (var media in details) {
          final id = media['id'];
          final localItem = animeItems.firstWhere((item) => item.id == id);
          final int? nextEpisode = media['nextAiringEpisode']?['episode'];
          final int totalEpisodes = media['episodes'] ?? 0;
          final int latestReleased = nextEpisode != null ? (nextEpisode - 1) : totalEpisodes;
          
          int ackEp = prefs.getInt('notif_acknowledged_anime_$id') ?? localItem.watchedEpisodes;
          if (ackEp < localItem.watchedEpisodes) {
            ackEp = localItem.watchedEpisodes;
          }
          if (latestReleased > ackEp) {
            animeCount++;
          }
        }
      } catch (_) {}
    }

    // 2. MANGA
    final mangaItems = _items.where((item) => item.mode == 'manga').toList();
    int mangaCount = 0;
    if (mangaItems.isNotEmpty) {
      final ids = mangaItems.map((item) => item.id).toList();
      try {
        final details = await AnilistService().fetchLibraryDetails(ids, type: 'MANGA');
        for (var media in details) {
          final id = media['id'];
          final localItem = mangaItems.firstWhere((item) => item.id == id);
          final int totalChapters = media['chapters'] ?? 0;
          
          int ackEp = prefs.getInt('notif_acknowledged_manga_$id') ?? localItem.watchedEpisodes;
          if (ackEp < localItem.watchedEpisodes) {
            ackEp = localItem.watchedEpisodes;
          }
          if (totalChapters > ackEp) {
            mangaCount++;
          }
        }
      } catch (_) {}
    }

    // 3. MOVIES
    final movieItems = _items.where((item) => item.mode == 'movies').toList();
    int movieCount = 0;
    if (movieItems.isNotEmpty) {
      final ids = movieItems.map((item) => item.id).toList();
      try {
        final details = await AnilistService().fetchLibraryDetails(ids, type: 'ANIME');
        for (var media in details) {
          final id = media['id'];
          final localItem = movieItems.firstWhere((item) => item.id == id);
          final int? nextEpisode = media['nextAiringEpisode']?['episode'];
          final int totalEpisodes = media['episodes'] ?? 0;
          final int latestReleased = nextEpisode != null ? (nextEpisode - 1) : totalEpisodes;
          
          int ackEp = prefs.getInt('notif_acknowledged_movies_$id') ?? localItem.watchedEpisodes;
          if (ackEp < localItem.watchedEpisodes) {
            ackEp = localItem.watchedEpisodes;
          }
          if (latestReleased > ackEp) {
            movieCount++;
          }
        }
      } catch (_) {}
    }

    bool changed = false;
    if (_animeNotificationCount != animeCount) {
      _animeNotificationCount = animeCount;
      _animeBadgeCleared = false;
      changed = true;
    }
    if (_mangaNotificationCount != mangaCount) {
      _mangaNotificationCount = mangaCount;
      _mangaBadgeCleared = false;
      changed = true;
    }
    if (_moviesNotificationCount != movieCount) {
      _moviesNotificationCount = movieCount;
      _moviesBadgeCleared = false;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }
}
