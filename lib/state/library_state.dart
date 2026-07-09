import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/anilist_service.dart';
import '../services/suwayomi_service.dart';
import '../services/suwayomi_manager.dart';
import '../services/download_service.dart';
import 'navigation_state.dart';
import 'anilist_auth_state.dart';

// Top-level functions for compute() — must be top-level or static to run in isolates
List<LibraryItem> _parseLibraryItems(String json) {
  final List<dynamic> decoded = jsonDecode(json);
  return decoded.map((item) => LibraryItem.fromJson(item)).toList();
}

List<LibraryCategory> _parseCategories(String json) {
  final List<dynamic> decoded = jsonDecode(json);
  return decoded.map((cat) => LibraryCategory.fromJson(cat)).toList();
}

Map<int, Map<String, dynamic>> _parseCache(String json) {
  final Map<String, dynamic> decoded = jsonDecode(json);
  return decoded.map((key, value) => MapEntry(int.parse(key), Map<String, dynamic>.from(value)));
}

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
  Map<int, Map<String, dynamic>> _animeCache = {};
  int _animeNotificationCount = 0;
  int _mangaNotificationCount = 0;
  int _moviesNotificationCount = 0;

  bool _animeBadgeCleared = false;
  bool _mangaBadgeCleared = false;
  bool _moviesBadgeCleared = false;

  List<LibraryItem> get items => _items;
  List<LibraryCategory> get categories => _categories;
  Map<int, Map<String, dynamic>> get mangaCache => _mangaCache;
  Map<int, Map<String, dynamic>> get animeCache => _animeCache;

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

    if (mode == AppMode.manga) {
      for (var item in libraryItems) {
        final int totalChapters = item.totalEpisodes ?? 0;
        await prefs.setInt('notif_acknowledged_manga_${item.id}', totalChapters);
      }
      await updateNotificationCount(force: true);
      return;
    }

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
      await updateNotificationCount(force: true);
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
      await updateNotificationCount(force: true);
    } catch (_) {}
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load host and port for Suwayomi manga engine
    SuwayomiService.host = prefs.getString('manga_server_host') ?? '127.0.0.1';
    SuwayomiService.port = prefs.getInt('manga_server_port') ?? 4567;
    
    // Load library items, categories, and caches in parallel on background isolates
    final String? itemsJson = prefs.getString('library_items');
    final String? catsJson = prefs.getString('library_categories');
    final String? cacheJson = prefs.getString('manga_library_cache');
    final String? animeCacheJson = prefs.getString('anime_library_cache');

    final List<Future<void>> parseTasks = [];
    if (itemsJson != null) {
      parseTasks.add(compute(_parseLibraryItems, itemsJson).then((v) => _items = v).catchError((e) {
        debugPrint('Failed to load library items: $e');
      }));
    }
    if (catsJson != null) {
      parseTasks.add(compute(_parseCategories, catsJson).then((v) => _categories = v).catchError((e) {
        debugPrint('Failed to load library categories: $e');
      }));
    }
    if (cacheJson != null) {
      parseTasks.add(compute(_parseCache, cacheJson).then((v) => _mangaCache = v).catchError((e) {
        debugPrint('Failed to load manga cache: $e');
      }));
    }
    if (animeCacheJson != null) {
      parseTasks.add(compute(_parseCache, animeCacheJson).then((v) => _animeCache = v).catchError((e) {
        debugPrint('Failed to load anime cache: $e');
      }));
    }
    await Future.wait(parseTasks);

    notifyListeners();
    // Defer notification count update to run in the background after startup to avoid lag
    Future.delayed(const Duration(seconds: 3), () {
      updateNotificationCount();
    });
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
    bool bypassAnilistSync = false,
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
    updateNotificationCount(force: true);

    // Asynchronous background sync to AniList (only for anime)
    if (!bypassAnilistSync && mode == 'anime') {
      final authState = AnilistAuthState();
      if (authState.isLoggedIn && authState.isAutoSyncEnabled) {
        AnilistService().syncProgressToAnilist(
          mediaId: id,
          status: libraryStatus,
          progress: watchedEpisodes,
          score: rating,
          token: authState.accessToken!,
        );
      }
    }
  }

  Future<int> importFromAnilist(String type, String token) async {
    if (type == 'MANGA') return 0; // Disable AniList manga syncing entirely
    final String localModeStr = 'anime';
    final viewerId = AnilistAuthState().userId;
    if (viewerId == null) return 0;

    final List<dynamic> entries = await AnilistService().fetchUserLibrary(viewerId, type, token);
    if (entries.isEmpty) return 0;

    int importedCount = 0;
    final existingMap = {for (var item in _items) '${item.id}_${item.mode}': item};

    for (var entry in entries) {
      final media = entry['media'];
      if (media == null) continue;

      final int mediaId = media['id'];
      final String formatVal = media['format'] ?? '';
      final String aniStatus = entry['status'] ?? 'PLANNING';
      final double score = (entry['score'] as num?)?.toDouble() ?? 0.0;
      final int progress = entry['progress'] ?? 0;
      final int? total = type == 'MANGA' ? media['chapters'] : media['episodes'];

      String libraryStatus = 'planning';
      if (aniStatus == 'CURRENT' || aniStatus == 'REPEATING') {
        libraryStatus = 'watching';
      } else if (aniStatus == 'PLANNING') {
        libraryStatus = 'planning';
      } else if (aniStatus == 'COMPLETED') {
        libraryStatus = 'completed';
      } else if (aniStatus == 'DROPPED' || aniStatus == 'PAUSED') {
        libraryStatus = 'paused_dropped';
      }

      final key = '${mediaId}_$localModeStr';
      final existingItem = existingMap[key];

      bool shouldUpdate = false;
      List<String> finalCategories = const <String>[];

      if (existingItem != null) {
        finalCategories = existingItem.categoryIds;
        if (existingItem.libraryStatus != libraryStatus ||
            existingItem.watchedEpisodes != progress ||
            existingItem.rating != score) {
          shouldUpdate = true;
        }
      } else {
        shouldUpdate = true;
      }

      if (shouldUpdate) {
        _items.removeWhere((item) => item.id == mediaId && item.mode == localModeStr);
        _items.add(LibraryItem(
          id: mediaId,
          mode: localModeStr,
          format: formatVal,
          addedAt: existingItem?.addedAt ?? DateTime.now(),
          libraryStatus: libraryStatus,
          rating: score,
          watchedEpisodes: progress,
          totalEpisodes: total ?? existingItem?.totalEpisodes,
          categoryIds: finalCategories,
        ));
        importedCount++;
      }

      if (type == 'MANGA') {
        final titles = media['title'];
        final String displayName = titles?['english'] ?? titles?['romaji'] ?? 'Untitled';
        final String coverUrl = media['coverImage']?['large'] ?? '';
        
        _mangaCache[mediaId] = {
          'id': mediaId,
          'title': displayName,
          'thumbnailUrl': coverUrl,
          'status': '',
          'author': '',
          'genre': [],
        };
      } else {
        _animeCache[mediaId] = {
          'id': mediaId,
          'title': media['title'],
          'coverImage': media['coverImage'],
          'averageScore': media['averageScore'],
          'format': media['format'],
          'episodes': media['episodes'],
          'status': media['status'],
          'bannerImage': media['bannerImage'],
        };
      }
    }

    notifyListeners();
    await _persist();
    updateNotificationCount(force: true);
    return importedCount;
  }

  Future<void> removeItem(int id, String mode) async {
    _items.removeWhere((item) => item.id == id && item.mode == mode);
    if (mode == 'manga') {
      _mangaCache.remove(id);
    } else if (mode == 'anime') {
      _animeCache.remove(id);
    }
    notifyListeners();
    await _persist();
    updateNotificationCount(force: true);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(_items.map((item) => item.toJson()).toList());
    await prefs.setString('library_items', jsonString);
    
    final String catsJson = jsonEncode(_categories.map((cat) => cat.toJson()).toList());
    await prefs.setString('library_categories', catsJson);

    final String cacheJson = jsonEncode(_mangaCache.map((key, value) => MapEntry(key.toString(), value)));
    await prefs.setString('manga_library_cache', cacheJson);

    final String animeCacheJson = jsonEncode(_animeCache.map((key, value) => MapEntry(key.toString(), value)));
    await prefs.setString('anime_library_cache', animeCacheJson);
  }

  Future<void> updateAnimeCache(int id, Map<String, dynamic> data) async {
    _animeCache[id] = data;
    await _persist();
  }

  Future<void> updateAnimeCacheBatch(Map<int, Map<String, dynamic>> batch) async {
    _animeCache.addAll(batch);
    await _persist();
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

  Future<void> updateNotificationCount({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!force) {
      final int? lastSync = prefs.getInt('library_last_notif_sync');
      if (lastSync != null) {
        final age = DateTime.now().millisecondsSinceEpoch - lastSync;
        if (age < const Duration(minutes: 5).inMilliseconds) {
          return;
        }
      }
    }

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
          
          final String startEpKey = 'notif_start_episode_anime_$id';
          int? startEp = prefs.getInt(startEpKey);
          if (startEp == null) {
            startEp = latestReleased;
            await prefs.setInt(startEpKey, startEp);
          }

          final localDownloads = DownloadService().tasks.where(
            (t) => t.anilistId == id && t.status == DownloadStatus.completed
          );
          final int maxDownloaded = localDownloads.isEmpty 
              ? 0 
              : localDownloads.map((t) => t.episodeNumber ?? 0).fold(0, max);

          int ackEp = prefs.getInt('notif_acknowledged_anime_$id') ?? startEp;
          int watchedOrDownloaded = max(localItem.watchedEpisodes, maxDownloaded);
          if (ackEp < watchedOrDownloaded) {
            ackEp = watchedOrDownloaded;
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
    if (mangaItems.isNotEmpty && await SuwayomiManager.isSuwayomiRunning(SuwayomiService.port)) {
      bool needPersist = false;
      for (var item in mangaItems) {
        if (item.libraryStatus == 'completed') continue;
        try {
          final chaptersList = await SuwayomiService().getChapters(item.id);
          final int totalChapters = chaptersList.length;
          
          if (item.totalEpisodes != totalChapters) {
            _items.removeWhere((x) => x.id == item.id && x.mode == 'manga');
            _items.add(LibraryItem(
              id: item.id,
              mode: item.mode,
              format: item.format,
              addedAt: item.addedAt,
              libraryStatus: item.libraryStatus,
              rating: item.rating,
              watchedEpisodes: item.watchedEpisodes,
              totalEpisodes: totalChapters,
              categoryIds: item.categoryIds,
            ));
            needPersist = true;
          }

          final String startChapterKey = 'notif_start_chapter_manga_${item.id}';
          int? startChapter = prefs.getInt(startChapterKey);
          if (startChapter == null) {
            startChapter = totalChapters;
            await prefs.setInt(startChapterKey, startChapter);
          }

          int ackEp = prefs.getInt('notif_acknowledged_manga_${item.id}') ?? startChapter;
          if (ackEp < item.watchedEpisodes) {
            ackEp = item.watchedEpisodes;
          }
          if (totalChapters > ackEp) {
            mangaCount++;
          }
        } catch (_) {}
      }
      if (needPersist) {
        await _persist();
      }
    } else {
      for (var item in mangaItems) {
        final int totalChapters = item.totalEpisodes ?? 0;
        
        final String startChapterKey = 'notif_start_chapter_manga_${item.id}';
        int? startChapter = prefs.getInt(startChapterKey);
        if (startChapter == null) {
          startChapter = totalChapters;
          await prefs.setInt(startChapterKey, startChapter);
        }

        int ackEp = prefs.getInt('notif_acknowledged_manga_${item.id}') ?? startChapter;
        if (ackEp < item.watchedEpisodes) {
          ackEp = item.watchedEpisodes;
        }
        if (totalChapters > ackEp) {
          mangaCount++;
        }
      }
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
            
            final String startEpKey = 'notif_start_episode_movies_${item.id}';
            int? startEp = prefs.getInt(startEpKey);
            if (startEp == null) {
              startEp = latestReleased;
              await prefs.setInt(startEpKey, startEp);
            }

            final localDownloads = DownloadService().tasks.where(
              (t) => t.anilistId == item.id && t.status == DownloadStatus.completed
            );
            final int maxDownloaded = localDownloads.isEmpty 
                ? 0 
                : localDownloads.map((t) => t.episodeNumber ?? 0).fold(0, max);

            int ackEp = prefs.getInt('notif_acknowledged_movies_${item.id}') ?? startEp;
            int watchedOrDownloaded = max(item.watchedEpisodes, maxDownloaded);
            if (ackEp < watchedOrDownloaded) {
              ackEp = watchedOrDownloaded;
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

    await prefs.setInt('library_last_notif_sync', DateTime.now().millisecondsSinceEpoch);

    if (changed) {
      notifyListeners();
    }
  }

  Future<void> updateMangaCache(int id, Map<String, dynamic> data) async {
    _mangaCache[id] = data;
    notifyListeners();
    await _persist();
  }

  // Get the list of read chapter IDs for a manga
  List<String> getReadChapterIds(int mangaId) {
    final cache = _mangaCache[mangaId];
    if (cache == null) return [];
    final list = cache['readChapterIds'] as List?;
    if (list == null) return [];
    return list.map((e) => e.toString()).toList();
  }

  // Mark a chapter as read/unread for a manga
  Future<void> setChapterReadStatus(int mangaId, String chapterId, bool read) async {
    final cache = _mangaCache[mangaId] ?? {};
    final list = List<String>.from(cache['readChapterIds'] ?? []);
    if (read) {
      if (!list.contains(chapterId)) {
        list.add(chapterId);
      }
    } else {
      list.remove(chapterId);
    }
    cache['readChapterIds'] = list;
    
    // Also update watchedEpisodes in LibraryItem to count how many chapters are read
    final item = getItem(mangaId, 'manga');
    if (item != null) {
      _items = _items.map((i) {
        if (i.id == mangaId && i.mode == 'manga') {
          return LibraryItem(
            id: i.id,
            mode: i.mode,
            format: i.format,
            addedAt: i.addedAt,
            libraryStatus: i.libraryStatus,
            rating: i.rating,
            watchedEpisodes: list.length,
            totalEpisodes: i.totalEpisodes,
            categoryIds: i.categoryIds,
          );
        }
        return i;
      }).toList();
    }

    _mangaCache[mangaId] = cache;
    notifyListeners();
    await _persist();
  }
}
