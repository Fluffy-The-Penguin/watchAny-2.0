import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/anilist_service.dart';

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
  int _notificationCount = 0;
  bool _badgeCleared = false;

  List<LibraryItem> get items => _items;
  int get notificationCount => _badgeCleared ? 0 : _notificationCount;

  void clearNotificationBadge() {
    if (!_badgeCleared) {
      _badgeCleared = true;
      notifyListeners();
    }
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
    final libraryAnime = _items.where((item) => item.mode == 'anime').toList();
    if (libraryAnime.isEmpty) {
      if (_notificationCount != 0) {
        _notificationCount = 0;
        _badgeCleared = false;
        notifyListeners();
      }
      return;
    }
    
    final ids = libraryAnime.map((item) => item.id).toList();
    try {
      final List<dynamic> details = await AnilistService().fetchLibraryDetails(ids);
      int count = 0;
      for (var media in details) {
        final id = media['id'];
        final localItem = libraryAnime.firstWhere((item) => item.id == id);
        final int? nextEpisode = media['nextAiringEpisode']?['episode'];
        final int totalEpisodes = media['episodes'] ?? 0;
        final int latestReleased = nextEpisode != null ? (nextEpisode - 1) : totalEpisodes;
        if (latestReleased > localItem.watchedEpisodes) {
          count++;
        }
      }
      if (_notificationCount != count) {
        _notificationCount = count;
        _badgeCleared = false; // Reset cleared flag since count changed
        notifyListeners();
      }
    } catch (_) {
      // ignore network errors for background update
    }
  }
}
