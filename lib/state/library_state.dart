import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/anilist_service.dart';
import '../services/suwayomi_service.dart';
import '../services/suwayomi_manager.dart';
import '../services/download_service.dart';
import '../services/image_cache_service.dart';
import 'navigation_state.dart';
import 'anilist_auth_state.dart';
import '../database/app_database.dart' as db;
import 'package:drift/drift.dart' as drift;
import 'library_providers.dart';
import '../services/sync_isolate_worker.dart';



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

  void _publishNotificationCounts() {
    final container = RiverpodContainerHolder.container;
    if (container != null) {
      container.read(animeNotificationCountProvider.notifier).state = 
          _animeBadgeCleared ? 0 : _animeNotificationCount;
      container.read(mangaNotificationCountProvider.notifier).state = 
          _mangaBadgeCleared ? 0 : _mangaNotificationCount;
      container.read(moviesNotificationCountProvider.notifier).state = 
          _moviesBadgeCleared ? 0 : _moviesNotificationCount;
    }
  }

  final db.AppDatabase _db = db.AppDatabase();
  db.AppDatabase get database => _db;

  List<LibraryItem> _items = [];
  List<LibraryCategory> _categories = [];
  final Map<int, Map<String, dynamic>> _mangaCache = LazyJsonMap();
  final Map<int, Map<String, dynamic>> _animeCache = LazyJsonMap();
  final Map<int, Map<String, dynamic>> _movieCache = LazyJsonMap();
  int _animeNotificationCount = 0;
  int _mangaNotificationCount = 0;
  int _moviesNotificationCount = 0;

  SharedPreferences? _prefs;

  bool _animeBadgeCleared = false;
  bool _mangaBadgeCleared = false;
  bool _moviesBadgeCleared = false;

  List<LibraryItem> get items => _items;
  List<LibraryCategory> get categories => _categories;
  Map<int, Map<String, dynamic>> get mangaCache => _mangaCache;
  Map<int, Map<String, dynamic>> get animeCache => _animeCache;
  Map<int, Map<String, dynamic>> get movieCache => _movieCache;

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
    _publishNotificationCounts();
    acknowledgeNotifications(mode); // fire-and-forget, never block UI
  }

  Future<Map<String, int>> getNotificationStartMap() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return _loadNotifMap(prefs, _notifStartKey);
  }

  Future<Map<String, int>> getNotificationAckMap() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return _loadNotifMap(prefs, _notifAckKey);
  }

  // --- Notification state helpers ---
  static const String _notifAckKey = 'notif_ack_all';    // Map<"mode_id", int>
  static const String _notifStartKey = 'notif_start_all'; // Map<"mode_id", int>

  Future<Map<String, int>> _loadNotifMap(SharedPreferences prefs, String key) async {
    final acks = await _db.select(_db.notificationAcks).get();
    if (key == _notifAckKey) {
      return {for (var ack in acks) ack.mediaKey: ack.ackValue};
    } else {
      return {for (var ack in acks) ack.mediaKey: ack.startValue};
    }
  }

  Future<void> _saveNotifMap(SharedPreferences prefs, String key, Map<String, int> map) async {
    await _db.transaction(() async {
      for (var entry in map.entries) {
        final mediaKey = entry.key;
        final val = entry.value;

        final existing = await (_db.select(_db.notificationAcks)..where((t) => t.mediaKey.equals(mediaKey))).getSingleOrNull();
        final int currentAck = key == _notifAckKey ? val : (existing?.ackValue ?? val);
        final int currentStart = key == _notifStartKey ? val : (existing?.startValue ?? val);

        await _db.into(_db.notificationAcks).insertOnConflictUpdate(
          db.NotificationAcksCompanion.insert(
            mediaKey: mediaKey,
            ackValue: currentAck,
            startValue: currentStart,
          ),
        );
      }
    });
  }
  // ---

  Future<void> acknowledgeNotifications(AppMode mode) async {
    final String localModeStr = mode == AppMode.manga
        ? 'manga'
        : (mode == AppMode.movies ? 'movies' : 'anime');

    final libraryItems = _items.where((item) => item.mode == localModeStr).toList();
    if (libraryItems.isEmpty) return;

    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final ackMap = await _loadNotifMap(prefs, _notifAckKey);

    if (mode == AppMode.manga) {
      // Bulk-set all manga acks in memory, then write once
      for (var item in libraryItems) {
        ackMap['manga_${item.id}'] = item.totalEpisodes ?? 0;
      }
      await _saveNotifMap(prefs, _notifAckKey, ackMap); // 1 write
      updateNotificationCount(force: true); // fire-and-forget
      return;
    }

    if (mode == AppMode.movies) {
      // Fetch latest episode counts concurrently, then write all acks at once
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
              ackMap['movies_${item.id}'] = latestReleased;
            }
          }
        } catch (_) {}
      });
      await Future.wait(futures);
      await _saveNotifMap(prefs, _notifAckKey, ackMap); // 1 write
      updateNotificationCount(force: true); // fire-and-forget
      return;
    }

    // Anime
    final ids = libraryItems.map((item) => item.id).toList();
    try {
      final details = await AnilistService().fetchLibraryDetails(ids, type: 'ANIME');
      for (var media in details) {
        final id = media['id'];
        final localItem = libraryItems.firstWhere((item) => item.id == id);
        final int? nextEpisode = media['nextAiringEpisode']?['episode'];
        final int totalEpisodes = media['episodes'] ?? 0;
        final int latestReleased = nextEpisode != null ? (nextEpisode - 1) : totalEpisodes;
        if (latestReleased > localItem.watchedEpisodes) {
          ackMap['anime_$id'] = latestReleased;
        }
      }
      await _saveNotifMap(prefs, _notifAckKey, ackMap); // 1 write
      updateNotificationCount(force: true); // fire-and-forget
    } catch (_) {}
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final prefs = _prefs!;
    
    // Load host and port for Suwayomi manga engine
    SuwayomiService.host = prefs.getString('manga_server_host') ?? '127.0.0.1';
    SuwayomiService.port = prefs.getInt('manga_server_port') ?? 4567;
    

    // Load everything synchronously from SQLite into memory for runtime backwards compatibility
    try {
      final allItems = await _db.select(_db.libraryItems).get();
      _items = allItems.map((item) {
        List<String> parsedCategories = [];
        try {
          final decoded = jsonDecode(item.categoryIds);
          if (decoded is List) {
            parsedCategories = decoded.map((c) => c.toString()).toList();
          }
        } catch (_) {
          if (item.categoryIds.isNotEmpty) {
            parsedCategories = item.categoryIds.split(',').where((c) => c.isNotEmpty).toList();
          }
        }

        return LibraryItem(
          id: item.id,
          mode: item.mode,
          format: item.format,
          addedAt: item.addedAt,
          libraryStatus: item.libraryStatus,
          rating: item.rating,
          watchedEpisodes: item.watchedEpisodes,
          totalEpisodes: item.totalEpisodes,
          categoryIds: parsedCategories,
        );
      }).toList();
    } catch (e) {
      debugPrint('Failed to load library items from SQLite: $e');
    }

    try {
      final allCategories = await _db.select(_db.libraryCategories).get();
      _categories = allCategories.map((cat) => LibraryCategory(
        id: cat.id,
        name: cat.name,
        mode: cat.mode,
      )).toList();
    } catch (e) {
      debugPrint('Failed to load categories from SQLite: $e');
    }

    try {
      final List<db.MediaCache> allCaches;
      final libraryIds = _items.map((item) => item.id).toList();
      if (libraryIds.isNotEmpty) {
        allCaches = await (_db.select(_db.mediaCaches)..where((t) => t.id.isIn(libraryIds))).get();
      } else {
        allCaches = [];
      }
      for (var cache in allCaches) {
        if (cache.mode == 'manga') {
          (_mangaCache as LazyJsonMap).setRaw(cache.id, cache.extraData);
        } else if (cache.mode == 'anime') {
          (_animeCache as LazyJsonMap).setRaw(cache.id, cache.extraData);
        } else {
          (_movieCache as LazyJsonMap).setRaw(cache.id, cache.extraData);
        }
      }
    } catch (e) {
      debugPrint('Failed to load media caches from SQLite: $e');
    }

    notifyListeners();
    _publishNotificationCounts();
    // Defer notification count update — runs well after app is interactive
    Future.delayed(const Duration(seconds: 30), () {
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
    
    final newItem = LibraryItem(
      id: id,
      mode: mode,
      format: format,
      addedAt: existing?.addedAt ?? DateTime.now(),
      libraryStatus: libraryStatus,
      rating: rating,
      watchedEpisodes: watchedEpisodes,
      totalEpisodes: totalEpisodes,
      categoryIds: finalCategories,
    );
    _items.add(newItem);

    // Save to SQLite
    try {
      await _db.into(_db.libraryItems).insertOnConflictUpdate(
        db.LibraryItemsCompanion.insert(
          id: id,
          mode: mode,
          format: format,
          libraryStatus: libraryStatus,
          rating: rating,
          watchedEpisodes: watchedEpisodes,
          totalEpisodes: drift.Value(totalEpisodes),
          addedAt: newItem.addedAt,
          categoryIds: jsonEncode(finalCategories),
        ),
      );
    } catch (e) {
      debugPrint('Failed to save library item to SQLite: $e');
    }
    
    notifyListeners();

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

    // Calculate unique statistics for AniList auth state during sync
    final Map<int, Map<String, int>> uniqueAnime = {};
    for (var entry in entries) {
      final media = entry['media'];
      if (media == null) continue;
      final int id = media['id'];
      final int progress = entry['progress'] ?? 0;
      final int duration = media['duration'] ?? 24;
      if (!uniqueAnime.containsKey(id)) {
        uniqueAnime[id] = {'progress': progress, 'duration': duration};
      } else {
        if (progress > uniqueAnime[id]!['progress']!) {
          uniqueAnime[id]!['progress'] = progress;
        }
      }
    }
    final calcAnimeCount = uniqueAnime.length;
    final calcEpisodesWatched = uniqueAnime.values.fold(0, (sum, val) => sum + val['progress']!);
    final calcMinutesWatched = uniqueAnime.values.fold(0, (sum, val) => sum + (val['progress']! * val['duration']!));

    await AnilistAuthState().updateStats(
      animeCount: calcAnimeCount,
      episodesWatched: calcEpisodesWatched,
      minutesWatched: calcMinutesWatched,
    );

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

    // Batch insert imported items and caches into SQLite
    try {
      await _db.transaction(() async {
        for (var item in _items) {
          await _db.into(_db.libraryItems).insertOnConflictUpdate(
            db.LibraryItemsCompanion.insert(
              id: item.id,
              mode: item.mode,
              format: item.format,
              libraryStatus: item.libraryStatus,
              rating: item.rating,
              watchedEpisodes: item.watchedEpisodes,
              totalEpisodes: drift.Value(item.totalEpisodes),
              addedAt: item.addedAt,
              categoryIds: jsonEncode(item.categoryIds),
            ),
          );
        }
        for (var entry in _mangaCache.entries) {
          await _db.into(_db.mediaCaches).insertOnConflictUpdate(
            db.MediaCachesCompanion.insert(
              id: entry.key,
              mode: 'manga',
              title: entry.value['title'] ?? 'Untitled',
              coverImage: entry.value['thumbnailUrl'] ?? '',
              extraData: drift.Value(jsonEncode(entry.value)),
            ),
          );
        }
        for (var entry in _animeCache.entries) {
          await _db.into(_db.mediaCaches).insertOnConflictUpdate(
            db.MediaCachesCompanion.insert(
              id: entry.key,
              mode: 'anime',
              title: entry.value['title']?['english'] ?? entry.value['title']?['romaji'] ?? 'Untitled',
              coverImage: entry.value['coverImage']?['large'] ?? '',
              extraData: drift.Value(jsonEncode(entry.value)),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint('Failed to batch save imported AniList items to SQLite: $e');
    }

    notifyListeners();
    return importedCount;
  }

  Future<void> importLibraryData({
    List<dynamic>? itemsJson,
    List<dynamic>? categoriesJson,
    Map<String, dynamic>? mangaCacheJson,
    Map<String, dynamic>? animeCacheJson,
    Map<String, dynamic>? movieCacheJson,
  }) async {
    try {
      if (categoriesJson != null) {
        for (var c in categoriesJson) {
          if (c is Map) {
            final cat = LibraryCategory.fromJson(Map<String, dynamic>.from(c));
            final idx = _categories.indexWhere((x) => x.id == cat.id);
            if (idx != -1) {
              _categories[idx] = cat;
            } else {
              _categories.add(cat);
            }
            await _db.into(_db.libraryCategories).insertOnConflictUpdate(
              db.LibraryCategoriesCompanion.insert(
                id: cat.id,
                name: cat.name,
                mode: cat.mode,
              ),
            );
          }
        }
      }

      if (itemsJson != null) {
        final List<LibraryItem> importedItems = [];
        for (var i in itemsJson) {
          if (i is Map) {
            importedItems.add(LibraryItem.fromJson(Map<String, dynamic>.from(i)));
          }
        }
        if (importedItems.isNotEmpty) {
          for (var item in importedItems) {
            final idx = _items.indexWhere((x) => x.id == item.id && x.mode == item.mode);
            if (idx != -1) {
              _items[idx] = item;
            } else {
              _items.add(item);
            }
            await _db.into(_db.libraryItems).insertOnConflictUpdate(
              db.LibraryItemsCompanion.insert(
                id: item.id,
                mode: item.mode,
                format: item.format,
                addedAt: item.addedAt,
                libraryStatus: item.libraryStatus,
                rating: item.rating,
                watchedEpisodes: item.watchedEpisodes,
                totalEpisodes: drift.Value(item.totalEpisodes),
                categoryIds: jsonEncode(item.categoryIds),
              ),
            );
          }
        }
      }

      if (mangaCacheJson != null) {
        for (var entry in mangaCacheJson.entries) {
          final intId = int.tryParse(entry.key.toString());
          if (intId != null && entry.value is Map) {
            final cache = Map<String, dynamic>.from(entry.value);
            _mangaCache[intId] = cache;
            await _db.into(_db.mediaCaches).insertOnConflictUpdate(
              db.MediaCachesCompanion.insert(
                id: intId,
                mode: 'manga',
                title: cache['title']?.toString() ?? 'Untitled',
                coverImage: cache['thumbnailUrl']?.toString() ?? cache['coverImage']?.toString() ?? '',
                extraData: drift.Value(jsonEncode(cache)),
              ),
            );
          }
        }
      }

      if (animeCacheJson != null) {
        for (var entry in animeCacheJson.entries) {
          final intId = int.tryParse(entry.key.toString());
          if (intId != null && entry.value is Map) {
            final cache = Map<String, dynamic>.from(entry.value);
            _animeCache[intId] = cache;
            await _db.into(_db.mediaCaches).insertOnConflictUpdate(
              db.MediaCachesCompanion.insert(
                id: intId,
                mode: 'anime',
                title: cache['title']?['userPreferred']?.toString() ?? cache['title']?.toString() ?? 'Untitled',
                coverImage: cache['coverImage']?['large']?.toString() ?? cache['thumbnailUrl']?.toString() ?? '',
                extraData: drift.Value(jsonEncode(cache)),
              ),
            );
          }
        }
      }

      if (movieCacheJson != null) {
        for (var entry in movieCacheJson.entries) {
          final intId = int.tryParse(entry.key.toString());
          if (intId != null && entry.value is Map) {
            final cache = Map<String, dynamic>.from(entry.value);
            _movieCache[intId] = cache;
            await _db.into(_db.mediaCaches).insertOnConflictUpdate(
              db.MediaCachesCompanion.insert(
                id: intId,
                mode: 'movies',
                title: cache['title']?.toString() ?? cache['name']?.toString() ?? 'Untitled',
                coverImage: cache['poster_path']?.toString() ?? cache['thumbnailUrl']?.toString() ?? '',
                extraData: drift.Value(jsonEncode(cache)),
              ),
            );
          }
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to import cloud library data: $e');
    }
  }

  Future<void> removeItem(int id, String mode) async {
    _items.removeWhere((item) => item.id == id && item.mode == mode);
    if (mode == 'manga') {
      _mangaCache.remove(id);
    } else if (mode == 'anime') {
      _animeCache.remove(id);
    } else {
      _movieCache.remove(id);
    }

    try {
      await (_db.delete(_db.libraryItems)..where((t) => t.id.equals(id) & t.mode.equals(mode))).go();
      await (_db.delete(_db.mediaCaches)..where((t) => t.id.equals(id) & t.mode.equals(mode))).go();
    } catch (e) {
      debugPrint('Failed to delete library item from SQLite: $e');
    }

    // Remove permanently cached images for this item
    unawaited(LibraryImageCache().deleteImages(id, mode));

    notifyListeners();
  }

  Future<void> updateAnimeCache(int id, Map<String, dynamic> data) async {
    _animeCache[id] = data;
    try {
      await _db.into(_db.mediaCaches).insertOnConflictUpdate(
        db.MediaCachesCompanion.insert(
          id: id,
          mode: 'anime',
          title: data['title']?['english'] ?? data['title']?['romaji'] ?? 'Untitled',
          coverImage: data['coverImage']?['large'] ?? '',
          extraData: drift.Value(jsonEncode(data)),
        ),
      );
    } catch (e) {
      debugPrint('Failed to save anime cache: $e');
    }
    notifyListeners();
  }

  Future<void> updateAnimeCacheBatch(Map<int, Map<String, dynamic>> batch) async {
    _animeCache.addAll(batch);
    try {
      await _db.transaction(() async {
        for (var entry in batch.entries) {
          final id = entry.key;
          final data = entry.value;
          await _db.into(_db.mediaCaches).insertOnConflictUpdate(
            db.MediaCachesCompanion.insert(
              id: id,
              mode: 'anime',
              title: data['title']?['english'] ?? data['title']?['romaji'] ?? 'Untitled',
              coverImage: data['coverImage']?['large'] ?? '',
              extraData: drift.Value(jsonEncode(data)),
            ),
          );
          // Persistently cache cover and banner images for offline use
          final coverUrl = (data['coverImage']?['large'] ?? '').toString();
          final bannerUrl = (data['bannerImage'] ?? '').toString();
          if (coverUrl.isNotEmpty) unawaited(LibraryImageCache().cacheImage(coverUrl, id, 'anime', 'cover'));
          if (bannerUrl.isNotEmpty) unawaited(LibraryImageCache().cacheImage(bannerUrl, id, 'anime', 'banner'));
        }
      });
    } catch (e) {
      debugPrint('Failed to save anime cache batch: $e');
    }
    notifyListeners();
  }

  String _resolveMovieTitle(Map<String, dynamic> data) {
    if (data['title'] is Map) {
      return (data['title']['english'] ?? data['title']['romaji'] ?? 'Untitled').toString();
    } else if (data['title'] is String) {
      return data['title'] as String;
    } else if (data['name'] is String) {
      return data['name'] as String;
    }
    return 'Untitled';
  }

  String _resolveMovieCover(Map<String, dynamic> data) {
    if (data['coverImage'] is Map) {
      return (data['coverImage']['large'] ?? '').toString();
    } else if (data['coverImage'] is String) {
      return data['coverImage'] as String;
    } else if (data['poster'] is String) {
      return data['poster'] as String;
    } else if (data['poster_path'] is String) {
      return 'https://image.tmdb.org/t/p/w300${data['poster_path']}';
    } else if (data['thumbnailUrl'] is String) {
      return data['thumbnailUrl'] as String;
    }
    return '';
  }

  Future<void> updateMovieCache(int id, Map<String, dynamic> data) async {
    _movieCache[id] = data;
    try {
      await _db.into(_db.mediaCaches).insertOnConflictUpdate(
        db.MediaCachesCompanion.insert(
          id: id,
          mode: 'movies',
          title: _resolveMovieTitle(data),
          coverImage: _resolveMovieCover(data),
          extraData: drift.Value(jsonEncode(data)),
        ),
      );
    } catch (e) {
      debugPrint('Failed to save movie cache: $e');
    }
    notifyListeners();
  }

  Future<void> updateMovieCacheBatch(Map<int, Map<String, dynamic>> batch) async {
    _movieCache.addAll(batch);
    try {
      await _db.transaction(() async {
        for (var entry in batch.entries) {
          final id = entry.key;
          final data = entry.value;
          await _db.into(_db.mediaCaches).insertOnConflictUpdate(
            db.MediaCachesCompanion.insert(
              id: id,
              mode: 'movies',
              title: _resolveMovieTitle(data),
              coverImage: _resolveMovieCover(data),
              extraData: drift.Value(jsonEncode(data)),
            ),
          );
          // Persistently cache poster and backdrop images for offline use
          final posterUrl = _resolveMovieCover(data);
          final backdropUrl = (data['backdrop_path'] is String)
              ? 'https://image.tmdb.org/t/p/w1280${data['backdrop_path']}'
              : (data['bannerImage'] ?? '').toString();
          if (posterUrl.isNotEmpty) unawaited(LibraryImageCache().cacheImage(posterUrl, id, 'movies', 'cover'));
          if (backdropUrl.isNotEmpty) unawaited(LibraryImageCache().cacheImage(backdropUrl, id, 'movies', 'banner'));
        }
      });
    } catch (e) {
      debugPrint('Failed to save movie cache batch: $e');
    }
    notifyListeners();
  }

  Future<void> updateItemEpisodesInMemory(int id, String mode, int totalEpisodes) async {
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].id == id && _items[i].mode == mode) {
        if (_items[i].totalEpisodes != totalEpisodes) {
          final item = LibraryItem(
            id: _items[i].id,
            mode: _items[i].mode,
            format: _items[i].format,
            addedAt: _items[i].addedAt,
            libraryStatus: _items[i].libraryStatus,
            rating: _items[i].rating,
            watchedEpisodes: _items[i].watchedEpisodes,
            totalEpisodes: totalEpisodes,
            categoryIds: _items[i].categoryIds,
          );
          _items[i] = item;

          try {
            await _db.into(_db.libraryItems).insertOnConflictUpdate(
              db.LibraryItemsCompanion.insert(
                id: item.id,
                mode: item.mode,
                format: item.format,
                libraryStatus: item.libraryStatus,
                rating: item.rating,
                watchedEpisodes: item.watchedEpisodes,
                totalEpisodes: drift.Value(totalEpisodes),
                addedAt: item.addedAt,
                categoryIds: jsonEncode(item.categoryIds),
              ),
            );
          } catch (e) {
            debugPrint('Failed to update episodes in SQLite: $e');
          }
        }
        break;
      }
    }
  }

  // --- Categories CRUD helper methods ---

  Future<void> createCategory(String name, String mode) async {
    final id = 'cat_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode.abs()}';
    _categories.add(LibraryCategory(id: id, name: name, mode: mode));

    try {
      await _db.into(_db.libraryCategories).insertOnConflictUpdate(
        db.LibraryCategoriesCompanion.insert(
          id: id,
          name: name,
          mode: mode,
        ),
      );
    } catch (e) {
      debugPrint('Failed to save category to SQLite: $e');
    }
    notifyListeners();
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

        try {
          await _db.into(_db.libraryItems).insertOnConflictUpdate(
            db.LibraryItemsCompanion.insert(
              id: item.id,
              mode: item.mode,
              format: item.format,
              libraryStatus: item.libraryStatus,
              rating: item.rating,
              watchedEpisodes: item.watchedEpisodes,
              totalEpisodes: drift.Value(item.totalEpisodes),
              addedAt: item.addedAt,
              categoryIds: jsonEncode(updatedCats),
            ),
          );
        } catch (e) {
          debugPrint('Failed to update item category removal in SQLite: $e');
        }
      }
    }
    
    try {
      await (_db.delete(_db.libraryCategories)..where((t) => t.id.equals(id))).go();
    } catch (e) {
      debugPrint('Failed to delete category from SQLite: $e');
    }
    notifyListeners();
  }

  Future<void> renameCategory(String id, String newName) async {
    final idx = _categories.indexWhere((cat) => cat.id == id);
    if (idx != -1) {
      final mode = _categories[idx].mode;
      _categories[idx] = LibraryCategory(id: id, name: newName, mode: mode);

      try {
        await _db.into(_db.libraryCategories).insertOnConflictUpdate(
          db.LibraryCategoriesCompanion.insert(
            id: id,
            name: newName,
            mode: mode,
          ),
        );
      } catch (e) {
        debugPrint('Failed to rename category in SQLite: $e');
      }
      notifyListeners();
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

      try {
        await _db.into(_db.libraryItems).insertOnConflictUpdate(
          db.LibraryItemsCompanion.insert(
            id: item.id,
            mode: item.mode,
            format: item.format,
            libraryStatus: item.libraryStatus,
            rating: item.rating,
            watchedEpisodes: item.watchedEpisodes,
            totalEpisodes: drift.Value(item.totalEpisodes),
            addedAt: item.addedAt,
            categoryIds: jsonEncode(updatedCats),
          ),
        );
      } catch (e) {
        debugPrint('Failed to toggle category in SQLite: $e');
      }
      notifyListeners();
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

      try {
        await _db.into(_db.libraryItems).insertOnConflictUpdate(
          db.LibraryItemsCompanion.insert(
            id: item.id,
            mode: item.mode,
            format: item.format,
            libraryStatus: item.libraryStatus,
            rating: item.rating,
            watchedEpisodes: item.watchedEpisodes,
            totalEpisodes: drift.Value(item.totalEpisodes),
            addedAt: item.addedAt,
            categoryIds: jsonEncode(categoryIds),
          ),
        );
      } catch (e) {
        debugPrint('Failed to update categories in SQLite: $e');
      }
      notifyListeners();
    }
  }

  Future<void> updateNotificationCount({bool force = false}) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();

    if (!force) {
      final int? lastSync = prefs.getInt('library_last_notif_sync');
      if (lastSync != null) {
        final age = DateTime.now().millisecondsSinceEpoch - lastSync;
        if (age < const Duration(minutes: 5).inMilliseconds) {
          return;
        }
      }
    }

    final ackMap = await _loadNotifMap(prefs, _notifAckKey);
    final startMap = await _loadNotifMap(prefs, _notifStartKey);
    bool startMapDirty = false;

    // Gather IDs for synchronization
    final animeIds = _items.where((item) => item.mode == 'anime').map((item) => item.id).toList();
    final mangaIds = _items.where((item) => item.mode == 'manga').map((item) => item.id).toList();
    final movieIds = _items.where((item) => item.mode == 'movies' && item.format == 'SERIES').map((item) => item.id).toList();

    final bool isSuwayomiRunning = await SuwayomiManager.isSuwayomiRunning(SuwayomiService.port);
    final suwayomiUrl = isSuwayomiRunning ? 'http://127.0.0.1:${SuwayomiService.port}' : '';

    SyncResponse response;
    try {
      response = await SyncIsolateWorker().performSync(
        SyncRequest(
          animeIds: animeIds,
          mangaIds: mangaIds,
          movieIds: movieIds,
          suwayomiBaseUrl: suwayomiUrl,
        ),
      );
    } catch (e) {
      debugPrint("Failed to perform background isolate sync: $e");
      return;
    }

    int animeCount = 0;
    int mangaCount = 0;
    int movieCount = 0;

    // 1. Process Anime Results
    for (var entry in response.animeLatestReleased.entries) {
      final id = entry.key;
      final latestReleased = entry.value;
      final localItems = _items.where((item) => item.id == id && item.mode == 'anime');
      if (localItems.isEmpty) continue;
      final localItem = localItems.first;

      final String startKey = 'anime_$id';
      if (!startMap.containsKey(startKey)) {
        startMap[startKey] = latestReleased;
        startMapDirty = true;
      }

      final localDownloads = DownloadService().tasks.where(
        (t) => t.anilistId == id && t.status == DownloadStatus.completed
      );
      final int maxDownloaded = localDownloads.isEmpty
          ? 0
          : localDownloads.map((t) => t.episodeNumber ?? 0).fold(0, max);

      int ackEp = ackMap['anime_$id'] ?? startMap[startKey]!;
      int watchedOrDownloaded = max(localItem.watchedEpisodes, maxDownloaded);
      if (ackEp < watchedOrDownloaded) ackEp = watchedOrDownloaded;
      if (latestReleased > ackEp) animeCount++;

      // Save fresh details to cache
      final freshDetails = response.freshAnimeDetails[id];
      if (freshDetails != null) {
        _animeCache[id] = freshDetails;
        await _db.into(_db.mediaCaches).insertOnConflictUpdate(
          db.MediaCachesCompanion.insert(
            id: id,
            mode: 'anime',
            title: freshDetails['title']?['english'] ?? freshDetails['title']?['romaji'] ?? 'Untitled',
            coverImage: freshDetails['coverImage']?['large'] ?? '',
            extraData: drift.Value(jsonEncode(freshDetails)),
          ),
        );
      }
    }

    // 2. Process Manga Results
    final List<LibraryItem> mangaItemsToReplace = [];
    for (var entry in response.mangaLatestReleased.entries) {
      final id = entry.key;
      final totalChapters = entry.value;
      final localItems = _items.where((item) => item.id == id && item.mode == 'manga');
      if (localItems.isEmpty) continue;
      final localItem = localItems.first;

      if (localItem.libraryStatus == 'completed') continue;

      if (localItem.totalEpisodes != totalChapters) {
        mangaItemsToReplace.add(LibraryItem(
          id: localItem.id, mode: localItem.mode, format: localItem.format,
          addedAt: localItem.addedAt, libraryStatus: localItem.libraryStatus,
          rating: localItem.rating, watchedEpisodes: localItem.watchedEpisodes,
          totalEpisodes: totalChapters, categoryIds: localItem.categoryIds,
        ));
      }

      final String startKey = 'manga_$id';
      if (!startMap.containsKey(startKey)) {
        startMap[startKey] = totalChapters;
        startMapDirty = true;
      }

      int ackEp = ackMap['manga_$id'] ?? startMap[startKey]!;
      if (ackEp < localItem.watchedEpisodes) ackEp = localItem.watchedEpisodes;
      if (totalChapters > ackEp) mangaCount++;
    }

    // Handle manga total episode updates
    if (mangaItemsToReplace.isNotEmpty) {
      for (final newItem in mangaItemsToReplace) {
        _items.removeWhere((x) => x.id == newItem.id && x.mode == 'manga');
        _items.add(newItem);

        try {
          await _db.into(_db.libraryItems).insertOnConflictUpdate(
            db.LibraryItemsCompanion.insert(
              id: newItem.id,
              mode: newItem.mode,
              format: newItem.format,
              libraryStatus: newItem.libraryStatus,
              rating: newItem.rating,
              watchedEpisodes: newItem.watchedEpisodes,
              totalEpisodes: drift.Value(newItem.totalEpisodes),
              addedAt: newItem.addedAt,
              categoryIds: jsonEncode(newItem.categoryIds),
            ),
          );
        } catch (_) {}
      }
    }

    // 3. Process Movie Results
    for (var entry in response.movieLatestReleased.entries) {
      final id = entry.key;
      final latestReleased = entry.value;
      final localItems = _items.where((item) => item.id == id && item.mode == 'movies');
      if (localItems.isEmpty) continue;
      final localItem = localItems.first;

      final String startKey = 'movies_$id';
      if (!startMap.containsKey(startKey)) {
        startMap[startKey] = latestReleased;
        startMapDirty = true;
      }

      final localDownloads = DownloadService().tasks.where(
        (t) => t.anilistId == id && t.status == DownloadStatus.completed
      );
      final int maxDownloaded = localDownloads.isEmpty
          ? 0
          : localDownloads.map((t) => t.episodeNumber ?? 0).fold(0, max);

      int ackEp = ackMap['movies_$id'] ?? startMap[startKey]!;
      int watchedOrDownloaded = max(localItem.watchedEpisodes, maxDownloaded);
      if (ackEp < watchedOrDownloaded) ackEp = watchedOrDownloaded;
      if (latestReleased > ackEp) movieCount++;
    }

    if (startMapDirty) await _saveNotifMap(prefs, _notifStartKey, startMap);
    await prefs.setInt('library_last_notif_sync', DateTime.now().millisecondsSinceEpoch);

    bool changed = false;
    if (_animeNotificationCount != animeCount) { _animeNotificationCount = animeCount; _animeBadgeCleared = false; changed = true; }
    if (_mangaNotificationCount != mangaCount) { _mangaNotificationCount = mangaCount; _mangaBadgeCleared = false; changed = true; }
    if (_moviesNotificationCount != movieCount) { _moviesNotificationCount = movieCount; _moviesBadgeCleared = false; changed = true; }

    if (changed) {
      notifyListeners();
    }
    _publishNotificationCounts();
  }

  void updateMangaCache(int id, Map<String, dynamic> data) {
    _mangaCache[id] = data;
    _db.into(_db.mediaCaches).insertOnConflictUpdate(
      db.MediaCachesCompanion.insert(
        id: id,
        mode: 'manga',
        title: data['title'] ?? 'Untitled',
        coverImage: data['thumbnailUrl'] ?? '',
        extraData: drift.Value(jsonEncode(data)),
      ),
    );
    notifyListeners();
  }

  void updateMangaCacheBatch(Map<int, Map<String, dynamic>> batch) {
    _mangaCache.addAll(batch);
    _db.transaction(() async {
      for (var entry in batch.entries) {
        final id = entry.key;
        final data = entry.value;
        await _db.into(_db.mediaCaches).insertOnConflictUpdate(
          db.MediaCachesCompanion.insert(
            id: id,
            mode: 'manga',
            title: data['title'] ?? 'Untitled',
            coverImage: data['thumbnailUrl'] ?? '',
            extraData: drift.Value(jsonEncode(data)),
          ),
        );
        // Persistently cache cover image for offline use
        final coverUrl = (data['thumbnailUrl'] ?? '').toString();
        if (coverUrl.isNotEmpty) unawaited(LibraryImageCache().cacheImage(coverUrl, id, 'manga', 'cover'));
      }
    });
    notifyListeners();
  }

  List<String> getReadChapterIds(int mangaId) {
    final cache = _mangaCache[mangaId];
    if (cache == null) return [];
    final list = cache['readChapterIds'] as List?;
    if (list == null) return [];
    return list.map((e) => e.toString()).toList();
  }

  // ── Manga Download Tracking ─────────────────────────────────────────────────

  /// Returns a map of chapterId -> local directory path for downloaded chapters.
  Map<String, String> _getDownloadedChaptersMap(int mangaId) {
    final cache = _mangaCache[mangaId];
    if (cache == null) return {};
    final raw = cache['downloadedChapters'];
    if (raw is Map) return Map<String, String>.from(raw.map((k, v) => MapEntry(k.toString(), v.toString())));
    return {};
  }

  /// Returns all downloaded chapter IDs for a manga.
  List<String> getDownloadedChapterIds(int mangaId) => _getDownloadedChaptersMap(mangaId).keys.toList();

  /// Returns the local directory path for a downloaded chapter, or null if not downloaded.
  String? getChapterLocalDir(int mangaId, String chapterId) => _getDownloadedChaptersMap(mangaId)[chapterId];

  /// Marks a chapter as downloaded and saves the local directory path.
  void markChapterDownloaded(int mangaId, int chapterId, String localDirPath) {
    final cache = _mangaCache[mangaId] ?? {};
    final map = _getDownloadedChaptersMap(mangaId);
    map[chapterId.toString()] = localDirPath;
    cache['downloadedChapters'] = map;
    _mangaCache[mangaId] = cache;
    _persistMangaCache(mangaId, cache);
    notifyListeners();
  }

  /// Removes a chapter's download record (called when user deletes a download).
  void markChapterNotDownloaded(int mangaId, int chapterId) {
    final cache = _mangaCache[mangaId];
    if (cache == null) return;
    final map = _getDownloadedChaptersMap(mangaId);
    map.remove(chapterId.toString());
    cache['downloadedChapters'] = map;
    _mangaCache[mangaId] = cache;
    _persistMangaCache(mangaId, cache);
    notifyListeners();
  }

  void _persistMangaCache(int mangaId, Map<String, dynamic> cache) {
    _db.into(_db.mediaCaches).insertOnConflictUpdate(
      db.MediaCachesCompanion.insert(
        id: mangaId,
        mode: 'manga',
        title: cache['title'] ?? 'Untitled',
        coverImage: cache['thumbnailUrl'] ?? '',
        extraData: drift.Value(jsonEncode(cache)),
      ),
    );
  }

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
    
    final item = getItem(mangaId, 'manga');
    if (item != null) {
      _items = _items.map((i) {
        if (i.id == mangaId && i.mode == 'manga') {
          final updatedItem = LibraryItem(
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

          _db.into(_db.libraryItems).insertOnConflictUpdate(
            db.LibraryItemsCompanion.insert(
              id: updatedItem.id,
              mode: updatedItem.mode,
              format: updatedItem.format,
              libraryStatus: updatedItem.libraryStatus,
              rating: updatedItem.rating,
              watchedEpisodes: updatedItem.watchedEpisodes,
              totalEpisodes: drift.Value(updatedItem.totalEpisodes),
              addedAt: updatedItem.addedAt,
              categoryIds: jsonEncode(updatedItem.categoryIds),
            ),
          );

          return updatedItem;
        }
        return i;
      }).toList();
    }

    _mangaCache[mangaId] = cache;
    
    await _db.into(_db.mediaCaches).insertOnConflictUpdate(
      db.MediaCachesCompanion.insert(
        id: mangaId,
        mode: 'manga',
        title: cache['title'] ?? 'Untitled',
        coverImage: cache['thumbnailUrl'] ?? '',
        extraData: drift.Value(jsonEncode(cache)),
      ),
    );

    notifyListeners();
  }

  Future<void> setBatchChapterReadStatus(int mangaId, List<String> chapterIds, bool read) async {
    if (chapterIds.isEmpty) return;
    final cache = _mangaCache[mangaId] ?? {};
    final list = Set<String>.from(cache['readChapterIds'] ?? []);
    if (read) {
      list.addAll(chapterIds);
    } else {
      list.removeAll(chapterIds);
    }
    final readList = list.toList();
    cache['readChapterIds'] = readList;

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
            watchedEpisodes: readList.length,
            totalEpisodes: i.totalEpisodes,
            categoryIds: i.categoryIds,
          );
        }
        return i;
      }).toList();

      final updatedItem = getItem(mangaId, 'manga');
      if (updatedItem != null) {
        await _db.into(_db.libraryItems).insertOnConflictUpdate(
          db.LibraryItemsCompanion.insert(
            id: updatedItem.id,
            mode: updatedItem.mode,
            format: updatedItem.format,
            libraryStatus: updatedItem.libraryStatus,
            rating: updatedItem.rating,
            watchedEpisodes: updatedItem.watchedEpisodes,
            totalEpisodes: drift.Value(updatedItem.totalEpisodes),
            addedAt: updatedItem.addedAt,
            categoryIds: jsonEncode(updatedItem.categoryIds),
          ),
        );
      }
    }

    _mangaCache[mangaId] = cache;

    await _db.into(_db.mediaCaches).insertOnConflictUpdate(
      db.MediaCachesCompanion.insert(
        id: mangaId,
        mode: 'manga',
        title: cache['title'] ?? 'Untitled',
        coverImage: cache['thumbnailUrl'] ?? '',
        extraData: drift.Value(jsonEncode(cache)),
      ),
    );

    notifyListeners();
  }
}

class LazyJsonMap extends MapBase<int, Map<String, dynamic>> {
  final Map<int, dynamic> _inner = {};

  void setRaw(int id, String? rawJson) {
    if (rawJson != null && rawJson.isNotEmpty) {
      _inner[id] = rawJson;
    }
  }

  @override
  Map<String, dynamic>? operator [](Object? key) {
    if (key is! int) return null;
    final val = _inner[key];
    if (val == null) return null;
    if (val is String) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(val));
        _inner[key] = decoded;
        return decoded;
      } catch (_) {
        return null;
      }
    }
    return val as Map<String, dynamic>;
  }

  @override
  void operator []=(int key, Map<String, dynamic> value) {
    _inner[key] = value;
  }

  @override
  void clear() => _inner.clear();

  @override
  Iterable<int> get keys => _inner.keys;

  @override
  Map<String, dynamic>? remove(Object? key) {
    final val = _inner.remove(key);
    if (val is String) {
      try {
        return Map<String, dynamic>.from(jsonDecode(val));
      } catch (_) {
        return null;
      }
    }
    return val as Map<String, dynamic>?;
  }

  @override
  int get length => _inner.length;

  @override
  bool containsKey(Object? key) => _inner.containsKey(key);
}

