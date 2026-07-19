import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/anilist_service.dart';

class AnilistAuthState extends ChangeNotifier {
  static final AnilistAuthState _instance = AnilistAuthState._internal();
  factory AnilistAuthState() => _instance;
  AnilistAuthState._internal();

  String? _accessToken;
  String? _username;
  String? _avatarUrl;
  String? _bannerUrl;
  int? _userId;
  bool _isAutoSyncEnabled = true;

  // Statistics
  int _animeCount = 0;
  int _episodesWatched = 0;
  int _minutesWatched = 0;
  int _mangaCount = 0;
  int _chaptersRead = 0;
  int _volumesRead = 0;

  bool get isLoggedIn => _accessToken != null;
  String? get accessToken => _accessToken;
  String? get username => _username;
  String? get avatarUrl => _avatarUrl;
  String? get bannerUrl => _bannerUrl;
  int? get userId => _userId;
  bool get isAutoSyncEnabled => _isAutoSyncEnabled;

  int get animeCount => _animeCount;
  int get episodesWatched => _episodesWatched;
  int get minutesWatched => _minutesWatched;
  int get mangaCount => _mangaCount;
  int get chaptersRead => _chaptersRead;
  int get volumesRead => _volumesRead;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('anilist_access_token');
    _username = prefs.getString('anilist_username');
    _avatarUrl = prefs.getString('anilist_avatar_url');
    _bannerUrl = prefs.getString('anilist_banner_url');
    _userId = prefs.getInt('anilist_user_id');
    _isAutoSyncEnabled = prefs.getBool('anilist_auto_sync') ?? true;

    _animeCount = prefs.getInt('anilist_anime_count') ?? 0;
    _episodesWatched = prefs.getInt('anilist_episodes_watched') ?? 0;
    _minutesWatched = prefs.getInt('anilist_minutes_watched') ?? 0;
    _mangaCount = prefs.getInt('anilist_manga_count') ?? 0;
    _chaptersRead = prefs.getInt('anilist_chapters_read') ?? 0;
    _volumesRead = prefs.getInt('anilist_volumes_read') ?? 0;

    notifyListeners();
  }

  Future<bool> login(String rawInput) async {
    try {
      // With Implicit Grant (response_type=token), AniList returns a JWT access
      // token directly in the redirect URL — no server-side code exchange needed.
      final String token = rawInput.trim();

      final viewer = await AnilistService().fetchViewerDetails(token);
      if (viewer != null) {
        _accessToken = token;
        _username = viewer['name'];
        _avatarUrl = viewer['avatar']?['large'];
        _bannerUrl = viewer['bannerImage'];
        _userId = viewer['id'];
        
        // Fetch library entries to get correct unique stats
        int count = 0;
        int episodes = 0;
        int minutes = 0;
        try {
          final entries = await AnilistService().fetchUserLibrary(_userId!, 'ANIME', token);
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
          count = uniqueAnime.length;
          episodes = uniqueAnime.values.fold(0, (sum, val) => sum + val['progress']!);
          minutes = uniqueAnime.values.fold(0, (sum, val) => sum + (val['progress']! * val['duration']!));
        } catch (_) {
          final stats = viewer['statistics'];
          count = stats?['anime']?['count'] ?? 0;
          episodes = stats?['anime']?['episodesWatched'] ?? 0;
          minutes = stats?['anime']?['minutesWatched'] ?? 0;
        }

        _animeCount = count;
        _episodesWatched = episodes;
        _minutesWatched = minutes;
        _mangaCount = 0;
        _chaptersRead = 0;
        _volumesRead = 0;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('anilist_access_token', token);
        await prefs.setString('anilist_username', _username!);
        
        if (_avatarUrl != null) {
          await prefs.setString('anilist_avatar_url', _avatarUrl!);
        } else {
          await prefs.remove('anilist_avatar_url');
        }
        
        if (_bannerUrl != null) {
          await prefs.setString('anilist_banner_url', _bannerUrl!);
        } else {
          await prefs.remove('anilist_banner_url');
        }
        
        if (_userId != null) {
          await prefs.setInt('anilist_user_id', _userId!);
        }

        await prefs.setInt('anilist_anime_count', _animeCount);
        await prefs.setInt('anilist_episodes_watched', _episodesWatched);
        await prefs.setInt('anilist_minutes_watched', _minutesWatched);
        await prefs.setInt('anilist_manga_count', _mangaCount);
        await prefs.setInt('anilist_chapters_read', _chaptersRead);
        await prefs.setInt('anilist_volumes_read', _volumesRead);

        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> updateStats({
    required int animeCount,
    required int episodesWatched,
    required int minutesWatched,
  }) async {
    _animeCount = animeCount;
    _episodesWatched = episodesWatched;
    _minutesWatched = minutesWatched;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('anilist_anime_count', _animeCount);
    await prefs.setInt('anilist_episodes_watched', _episodesWatched);
    await prefs.setInt('anilist_minutes_watched', _minutesWatched);

    notifyListeners();
  }

  Future<void> logout() async {
    _accessToken = null;
    _username = null;
    _avatarUrl = null;
    _bannerUrl = null;
    _userId = null;
    _animeCount = 0;
    _episodesWatched = 0;
    _minutesWatched = 0;
    _mangaCount = 0;
    _chaptersRead = 0;
    _volumesRead = 0;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('anilist_access_token');
    await prefs.remove('anilist_username');
    await prefs.remove('anilist_avatar_url');
    await prefs.remove('anilist_banner_url');
    await prefs.remove('anilist_user_id');

    await prefs.remove('anilist_anime_count');
    await prefs.remove('anilist_episodes_watched');
    await prefs.remove('anilist_minutes_watched');
    await prefs.remove('anilist_manga_count');
    await prefs.remove('anilist_chapters_read');
    await prefs.remove('anilist_volumes_read');

    notifyListeners();
  }

  Future<void> setAutoSync(bool enabled) async {
    _isAutoSyncEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('anilist_auto_sync', enabled);
    notifyListeners();
  }
}
