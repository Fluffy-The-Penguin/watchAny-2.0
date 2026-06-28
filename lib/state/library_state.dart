import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/anilist_service.dart';
import '../services/suwayomi_service.dart';
import 'navigation_state.dart';

class LibraryCategory {
  final String id;
  final String name;
  final String mode; // 'anime', 'manga', 'movies'

  LibraryCategory({
    required this.id,
    required this.name,
    required this.mode,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mode': mode,
  };

  factory LibraryCategory.fromJson(Map<String, dynamic> json) {
    return LibraryCategory(
      id: json['id'],
      name: json['name'],
      mode: json['mode'] ?? 'anime',
    );
  }
}

class LibraryItem {
  final int id;
  final String mode; // 'anime', 'manga', 'movies'
  final String format; // 'MOVIE', 'TV', etc.
  final DateTime addedAt;
  final String libraryStatus; // 'watching', 'planning', 'completed', 'paused_dropped'
  final double rating; // 0.0 (no rating) to 10.0
  final int watchedEpisodes;
  final int? totalEpisodes;
  final List<String> categoryIds; // Custom category IDs

  LibraryItem({
    required this.id,
    required this.mode,
    required this.format,
    required this.addedAt,
    required this.libraryStatus,
    required this.rating,
    required this.watchedEpisodes,
    this.totalEpisodes,
    this.categoryIds = const <String>[],
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
    'categoryIds': categoryIds,
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
      categoryIds: (json['categoryIds'] as List?)?.map((c) => c.toString()).toList() ?? const <String>[],
    );
  }
}

class LibraryState extends ChangeNotifier {
  static final LibraryState _instance = LibraryState._internal();
  factory LibraryState() => _instance;
  LibraryState._internal();

  List<LibraryItem> _items = [];
  List<LibraryCategory> _categories = [];
  Map<int, Map<String, dynamic>> _mangaCache = {};
  int _animeNotificationCount = 0;
  int _mangaNotificationCount = 0;
  int _moviesNotificationCount = 0;

  bool _animeBadgeCleared = false;
  bool _mangaBadgeCleared = false;
  bool _moviesBadgeCleared = false;

  List<LibraryItem> get items => _items;
  List<LibraryCategory> get categories => _categories;
  Map<int, Map<String, dynamic>> get mangaCache => _mangaCache;

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
    
    final prefs = await SharedPreferences.getInstance();

    if (mode == AppMode.movies) {
      final futures = libraryItems.where((item) => item.format == 'SERIES').map((item) async {
        final imdbId = 'tt${item.id.toString().padLeft(7, '0')}';
        final url = 'https://v3-cinemeta.strem.io/meta/series/$imdbId.json';
        try {
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
          if (response.statusCode == 200) {
            final decoded = jsonDecode(response.body);
            final videos = decoded['meta']?['videos'] as List? ?? [];
            final int latestReleased = videos.length;
            if (latestReleased > item.watchedEpisodes) {
              await prefs.setInt('notif_acknowledged_movies_${item.id}', latestReleased);
            }
          }
        } catch (_) {}
      });
      await Future.wait(futures);
      await updateNotificationCount();
      return;
    }

    final ids = libraryItems.map((item) => item.id).toList();
    try {
      final details = await AnilistService().fetchLibraryDetails(ids, type: anilistTypeStr);
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
    
    // Load host and port for Suwayomi manga engine
    SuwayomiService.host = prefs.getString('manga_server_host') ?? '127.0.0.1';
    SuwayomiService.port = prefs.getInt('manga_server_port') ?? 4567;
    
    // Load library items
    final String? itemsJson = prefs.getString('library_items');
    if (itemsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(itemsJson);
        _items = decoded.map((item) => LibraryItem.fromJson(item)).toList();
      } catch (e) {
        debugPrint('Failed to load library items: $e');
      }
    }

    // Load categories
    final String? catsJson = prefs.getString('library_categories');
    if (catsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(catsJson);
        _categories = decoded.map((cat) => LibraryCategory.fromJson(cat)).toList();
      } catch (e) {
        debugPrint('Failed to load library categories: $e');
      }
    }

    // Load manga cache
    final String? cacheJson = prefs.getString('manga_library_cache');
    if (cacheJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(cacheJson);
        _mangaCache = decoded.map((key, value) => MapEntry(int.parse(key), Map<String, dynamic>.from(value)));
      } catch (e) {
        debugPrint('Failed to load manga cache: $e');
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
    List<String>? categoryIds,
  }) async {
    final existing = getItem(id, mode);
    final List<String> finalCategories = categoryIds ?? existing?.categoryIds ?? const <String>[];

    _items.removeWhere((item) => item.id == id && item.mode == mode);
    
    _items.add(LibraryItem(
      id: id,
      mode: mode,
      format: format,
      addedAt: existing?.addedAt ?? DateTime.now(),
      libraryStatus: libraryStatus,
      rating: rating,
      watchedEpisodes: watchedEpisodes,
      totalEpisodes: totalEpisodes,
      categoryIds: finalCategories,
    ));
    
    notifyListeners();
    await _persist();
    updateNotificationCount();
  }

  Future<void> removeItem(int id, String mode) async {
    _items.removeWhere((item) => item.id == id && item.mode == mode);
    if (mode == 'manga') {
      _mangaCache.remove(id);
    }
    notifyListeners();
    await _persist();
    updateNotificationCount();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(_items.map((item) => item.toJson()).toList());
    await prefs.setString('library_items', jsonString);
    
    final String catsJson = jsonEncode(_categories.map((cat) => cat.toJson()).toList());
    await prefs.setString('library_categories', catsJson);

    final String cacheJson = jsonEncode(_mangaCache.map((key, value) => MapEntry(key.toString(), value)));
    await prefs.setString('manga_library_cache', cacheJson);
  }

  // --- Categories CRUD helper methods ---

  Future<void> createCategory(String name, String mode) async {
    final id = 'cat_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode.abs()}';
    _categories.add(LibraryCategory(id: id, name: name, mode: mode));
    notifyListeners();
    await _persist();
  }

  Future<void> deleteCategory(String id) async {
    _categories.removeWhere((cat) => cat.id == id);
    
    // Also remove this category ID from all items in the library
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.categoryIds.contains(id)) {
        final List<String> updatedCats = List<String>.from(item.categoryIds)..remove(id);
        _items[i] = LibraryItem(
          id: item.id,
          mode: item.mode,
          format: item.format,
          addedAt: item.addedAt,
          libraryStatus: item.libraryStatus,
          rating: item.rating,
          watchedEpisodes: item.watchedEpisodes,
          totalEpisodes: item.totalEpisodes,
          categoryIds: updatedCats,
        );
      }
    }
    
    notifyListeners();
    await _persist();
  }

  Future<void> renameCategory(String id, String newName) async {
    final idx = _categories.indexWhere((cat) => cat.id == id);
    if (idx != -1) {
      final mode = _categories[idx].mode;
      _categories[idx] = LibraryCategory(id: id, name: newName, mode: mode);
      notifyListeners();
      await _persist();
    }
  }

  Future<void> toggleItemCategory(int itemId, String mode, String categoryId) async {
    final idx = _items.indexWhere((item) => item.id == itemId && item.mode == mode);
    if (idx != -1) {
      final item = _items[idx];
      final List<String> updatedCats = List<String>.from(item.categoryIds);
      if (updatedCats.contains(categoryId)) {
        updatedCats.remove(categoryId);
      } else {
        updatedCats.add(categoryId);
      }
      _items[idx] = LibraryItem(
        id: item.id,
        mode: item.mode,
        format: item.format,
        addedAt: item.addedAt,
        libraryStatus: item.libraryStatus,
        rating: item.rating,
        watchedEpisodes: item.watchedEpisodes,
        totalEpisodes: item.totalEpisodes,
        categoryIds: updatedCats,
      );
      notifyListeners();
      await _persist();
    }
  }

  Future<void> updateItemCategories(int itemId, String mode, List<String> categoryIds) async {
    final idx = _items.indexWhere((item) => item.id == itemId && item.mode == mode);
    if (idx != -1) {
      final item = _items[idx];
      _items[idx] = LibraryItem(
        id: item.id,
        mode: item.mode,
        format: item.format,
        addedAt: item.addedAt,
        libraryStatus: item.libraryStatus,
        rating: item.rating,
        watchedEpisodes: item.watchedEpisodes,
        totalEpisodes: item.totalEpisodes,
        categoryIds: categoryIds,
      );
      notifyListeners();
      await _persist();
    }
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

    // 3. MOVIES / TV Series notification updates using Cinemeta
    final movieItems = _items.where((item) => item.mode == 'movies' && item.format == 'SERIES').toList();
    int movieCount = 0;
    if (movieItems.isNotEmpty) {
      final futures = movieItems.map((item) async {
        final imdbId = 'tt${item.id.toString().padLeft(7, '0')}';
        final url = 'https://v3-cinemeta.strem.io/meta/series/$imdbId.json';
        try {
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
          if (response.statusCode == 200) {
            final decoded = jsonDecode(response.body);
            final videos = decoded['meta']?['videos'] as List? ?? [];
            final int latestReleased = videos.length;
            
            int ackEp = prefs.getInt('notif_acknowledged_movies_${item.id}') ?? item.watchedEpisodes;
            if (ackEp < item.watchedEpisodes) {
              ackEp = item.watchedEpisodes;
            }
            if (latestReleased > ackEp) {
              return 1;
            }
          }
        } catch (_) {}
        return 0;
      });
      final results = await Future.wait(futures);
      movieCount = results.fold(0, (sum, val) => sum + val);
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

  Future<void> updateMangaCache(int id, Map<String, dynamic> data) async {
    _mangaCache[id] = data;
    notifyListeners();
    await _persist();
  }
}
