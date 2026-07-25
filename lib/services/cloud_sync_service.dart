import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../state/app_settings.dart';
import '../state/library_state.dart';
import '../state/user_profile_state.dart';
import 'backup_service.dart';
import 'download_service.dart';
import 'extension_service.dart';

enum SyncStatus {
  idle,
  syncing,
  synced,
  error,
  offline,
}

class CloudSyncService extends ChangeNotifier {
  static final CloudSyncService _instance = CloudSyncService._internal();
  factory CloudSyncService() => _instance;
  CloudSyncService._internal();

  static const String defaultServerUrl = 'http://fi10.bot-hosting.net:21204';

  String _serverUrl = defaultServerUrl;
  String? _authToken;
  String? _userEmail;
  String? _username;
  int? _userId;
  DateTime? _lastSyncTime;
  SyncStatus _status = SyncStatus.idle;
  String? _lastErrorMessage;
  Timer? _debounceSyncTimer;
  bool _isInitialized = false;

  String get serverUrl => _serverUrl;
  String? get authToken => _authToken;
  String? get userEmail => _userEmail;
  String? get username => _username;
  int? get userId => _userId;
  DateTime? get lastSyncTime => _lastSyncTime;
  SyncStatus get status => _status;
  String? get lastErrorMessage => _lastErrorMessage;
  bool get isLoggedIn => _authToken != null && _authToken!.isNotEmpty;
  bool get isSyncing => _status == SyncStatus.syncing;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      _serverUrl = prefs.getString('cloud_sync_server_url') ?? defaultServerUrl;
      _authToken = prefs.getString('cloud_sync_auth_token');
      _userEmail = prefs.getString('cloud_sync_user_email');
      _username = prefs.getString('cloud_sync_username');
      _userId = prefs.getInt('cloud_sync_user_id');

      final lastTs = prefs.getInt('cloud_sync_last_time');
      if (lastTs != null && lastTs > 0) {
        _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(lastTs);
      }

      if (isLoggedIn) {
        // Schedule silent background pull sync 3s after app startup completes to avoid race conditions with LibraryState
        Future.delayed(const Duration(seconds: 3), () {
          syncNow(silent: true);
        });
      }
    } catch (e) {
      debugPrint('CloudSyncService init error: $e');
    }
  }

  void setServerUrl(String url) async {
    var cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    if (cleanUrl.isEmpty) {
      cleanUrl = defaultServerUrl;
    }
    _serverUrl = cleanUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud_sync_server_url', _serverUrl);
    notifyListeners();
  }

  // --- Auth Actions ---

  Future<bool> register({
    required String serverUrl,
    required String username,
    required String email,
    required String password,
  }) async {
    setServerUrl(serverUrl);
    _setStatus(SyncStatus.syncing);
    _lastErrorMessage = null;

    try {
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username.trim(),
              'email': email.trim().toLowerCase(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['token'] != null) {
        await _saveAuthCredentials(
          token: data['token'].toString(),
          email: data['user']['email'].toString(),
          username: data['user']['username'].toString(),
          userId: int.tryParse(data['user']['id'].toString()) ?? 0,
        );

        // Perform initial push sync to seed the cloud account
        await syncNow();
        return true;
      } else {
        _lastErrorMessage = data['error'] ?? 'Registration failed';
        _setStatus(SyncStatus.error);
        return false;
      }
    } catch (e) {
      _lastErrorMessage = _parseHttpError(e);
      _setStatus(SyncStatus.error);
      return false;
    }
  }

  Future<bool> login({
    required String serverUrl,
    required String emailOrUsername,
    required String password,
  }) async {
    setServerUrl(serverUrl);
    _setStatus(SyncStatus.syncing);
    _lastErrorMessage = null;

    try {
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'emailOrUsername': emailOrUsername.trim(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['token'] != null) {
        await _saveAuthCredentials(
          token: data['token'].toString(),
          email: data['user']['email'].toString(),
          username: data['user']['username'].toString(),
          userId: int.tryParse(data['user']['id'].toString()) ?? 0,
        );

        // Perform pull sync to retrieve cloud data onto new device
        await syncNow();
        return true;
      } else {
        _lastErrorMessage = data['error'] ?? 'Authentication failed';
        _setStatus(SyncStatus.error);
        return false;
      }
    } catch (e) {
      _lastErrorMessage = _parseHttpError(e);
      _setStatus(SyncStatus.error);
      return false;
    }
  }

  Future<void> logout() async {
    _authToken = null;
    _userEmail = null;
    _username = null;
    _userId = null;
    _lastSyncTime = null;
    _status = SyncStatus.idle;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cloud_sync_auth_token');
    await prefs.remove('cloud_sync_user_email');
    await prefs.remove('cloud_sync_username');
    await prefs.remove('cloud_sync_user_id');
    await prefs.remove('cloud_sync_last_time');

    notifyListeners();
  }

  static String _encodeSyncPayload(Map<String, dynamic> payload) {
    return jsonEncode({'syncPayload': payload});
  }

  // --- Two-Way Sync Engine ---

  Future<bool> syncNow({bool silent = false}) async {
    if (!isLoggedIn) return false;

    if (!silent) {
      _setStatus(SyncStatus.syncing);
    }
    _lastErrorMessage = null;

    try {
      // 1. Pull cloud state from server FIRST so fresh devices restore cloud backup before pushing
      final pullResponse = await http
          .get(
            Uri.parse('$_serverUrl/api/sync/pull'),
            headers: {
              'Authorization': 'Bearer $_authToken',
            },
          )
          .timeout(const Duration(seconds: 25));

      if (pullResponse.statusCode == 401 || pullResponse.statusCode == 403) {
        _lastErrorMessage = 'Session expired. Please log in again.';
        await logout();
        return false;
      }

      if (pullResponse.statusCode == 200) {
        final data = jsonDecode(pullResponse.body);
        if (data['exists'] == true && data['syncPayload'] != null) {
          await _applyCloudSyncPayload(data['syncPayload']);
        }
      }

      // 2. Build local state payload (including newly restored items)
      final localPayload = await _buildLocalSyncPayload();

      // 3. Offload JSON encoding to isolate thread to keep UI completely responsive
      final pushBody = await compute(_encodeSyncPayload, localPayload);

      // 4. Push merged state to cloud server
      await http
          .post(
            Uri.parse('$_serverUrl/api/sync/push'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_authToken',
            },
            body: pushBody,
          )
          .timeout(const Duration(seconds: 25));

      final now = DateTime.now();
      _lastSyncTime = now;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('cloud_sync_last_time', now.millisecondsSinceEpoch);

      _setStatus(SyncStatus.synced);
      return true;
    } catch (e) {
      debugPrint('Cloud sync failed: $e');
      _lastErrorMessage = _parseHttpError(e);
      _setStatus(SyncStatus.error);
      return false;
    }
  }

  void triggerDebouncedSync() {
    if (!isLoggedIn) return;
    _debounceSyncTimer?.cancel();
    _debounceSyncTimer = Timer(const Duration(seconds: 30), () {
      syncNow(silent: true);
    });
  }

  // --- Private Helpers ---

  Future<void> _saveAuthCredentials({
    required String token,
    required String email,
    required String username,
    required int userId,
  }) async {
    _authToken = token;
    _userEmail = email;
    _username = username;
    _userId = userId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud_sync_auth_token', token);
    await prefs.setString('cloud_sync_user_email', email);
    await prefs.setString('cloud_sync_username', username);
    await prefs.setInt('cloud_sync_user_id', userId);
    notifyListeners();
  }

  Map<String, dynamic> _cleanMapForJson(Map map) {
    final Map<String, dynamic> result = {};
    map.forEach((key, value) {
      final k = key.toString();
      if (value is Map) {
        result[k] = _cleanMapForJson(value);
      } else if (value is List) {
        result[k] = value.map((e) => e is Map ? _cleanMapForJson(e) : e).toList();
      } else if (value is num || value is bool || value is String || value == null) {
        result[k] = value;
      } else {
        result[k] = value.toString();
      }
    });
    return result;
  }

  Future<Map<String, dynamic>> _buildLocalSyncPayload() async {
    final prefs = await SharedPreferences.getInstance();

    final libraryState = LibraryState();
    final userProfile = UserProfileState();
    final extService = ExtensionService();

    // Collect settings keys (Exclude internal staging, setup, and cache keys)
    const excludeKeys = {
      'cloud_sync_auth_token',
      'cloud_sync_user_email',
      'cloud_sync_username',
      'cloud_sync_user_id',
      'cloud_sync_last_time',
      'cloud_sync_server_url',
      'setup_completed',
      'library_items',
      'library_categories',
      'manga_library_cache',
      'anime_library_cache',
      'movie_library_cache',
      'watch_history',
      'download_tasks',
    };

    final settingsMap = <String, dynamic>{};
    for (var key in prefs.getKeys()) {
      if (!excludeKeys.contains(key)) {
        settingsMap[key] = prefs.get(key);
      }
    }

    return {
      'version': '2.0',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'library_items': libraryState.items.map((e) => e.toJson()).toList(),
      'library_categories': libraryState.categories.map((e) => e.toJson()).toList(),
      'anime_cache': _cleanMapForJson(libraryState.animeCache),
      'manga_cache': _cleanMapForJson(libraryState.mangaCache),
      'movie_cache': _cleanMapForJson(libraryState.movieCache),
      'extension_repos': extService.repos.map((e) => e.toJson()).toList(),
      'installed_extensions': extService.extensions.map((e) => e.toJson()).toList(),
      'profile': {
        'displayName': userProfile.displayName,
        'userTitle': userProfile.userTitle,
        'bio': userProfile.bio,
        'favoriteQuote': userProfile.favoriteQuote,
        'avatarIndex': userProfile.avatarIndex,
        'bannerIndex': userProfile.bannerIndex,
        'customAvatarUrl': userProfile.customAvatarUrl,
        'customBannerUrl': userProfile.customBannerUrl,
        'favoriteItems': userProfile.favoriteItems,
      },
      'settings': settingsMap,
    };
  }

  Future<void> _applyCloudSyncPayload(dynamic payload) async {
    try {
      final Map<String, dynamic> data = payload is String ? jsonDecode(payload) : Map<String, dynamic>.from(payload);
      final prefs = await SharedPreferences.getInstance();

      // 1. Restore Profile Settings
      if (data['profile'] is Map) {
        final prof = Map<String, dynamic>.from(data['profile']);
        final userProfile = UserProfileState();
        await userProfile.saveProfile(
          name: prof['displayName']?.toString() ?? userProfile.displayName,
          userTitle: prof['userTitle']?.toString() ?? userProfile.userTitle,
          bio: prof['bio']?.toString() ?? userProfile.bio,
          quote: prof['favoriteQuote']?.toString() ?? userProfile.favoriteQuote,
          avatarIdx: (prof['avatarIndex'] as num?)?.toInt() ?? userProfile.avatarIndex,
          bannerIdx: (prof['bannerIndex'] as num?)?.toInt() ?? userProfile.bannerIndex,
          customAvatar: prof['customAvatarUrl']?.toString() ?? userProfile.customAvatarUrl,
          customBanner: prof['customBannerUrl']?.toString() ?? userProfile.customBannerUrl,
        );

        if (prof['favoriteItems'] is List) {
          final List favs = prof['favoriteItems'];
          for (int i = 0; i < favs.length; i++) {
            if (favs[i] is Map) {
              await userProfile.setFavoriteItem(i, Map<String, String>.from(favs[i]));
            }
          }
        }
      }

      // 2. Restore Extension Repositories & Extension Lists
      if (data['extension_repos'] is List || data['installed_extensions'] is List) {
        await ExtensionService().importCloudData(
          reposJson: data['extension_repos'] as List<dynamic>?,
          extensionsJson: data['installed_extensions'] as List<dynamic>?,
        );
      }

      // 3. Restore Extension Repositories & Extension Lists in SharedPreferences
      if (data['settings'] is Map) {
        final settings = Map<String, dynamic>.from(data['settings']);
        const skipKeys = {
          'cloud_sync_auth_token',
          'cloud_sync_user_email',
          'cloud_sync_username',
          'cloud_sync_user_id',
          'cloud_sync_last_time',
          'cloud_sync_server_url',
          'setup_completed',
          'library_items',
          'library_categories',
          'manga_library_cache',
          'anime_library_cache',
          'movie_library_cache',
          'watch_history',
        };

        for (var entry in settings.entries) {
          if (skipKeys.contains(entry.key)) continue;
          final currentVal = prefs.get(entry.key);
          if (currentVal == entry.value) continue; // Skip redundant writes!

          final val = entry.value;
          if (val is String) {
            await prefs.setString(entry.key, val);
          } else if (val is bool) {
            await prefs.setBool(entry.key, val);
          } else if (val is int) {
            await prefs.setInt(entry.key, val);
          } else if (val is double) {
            await prefs.setDouble(entry.key, val);
          } else if (val is List) {
            await prefs.setStringList(entry.key, val.map((e) => e.toString()).toList());
          }
        }
      }

      // 4. Restore Library Items, Categories, and Media Caches
      if (data['library_items'] is List || data['library_categories'] is List || data['anime_cache'] is Map || data['manga_cache'] is Map) {
        await LibraryState().importLibraryData(
          itemsJson: data['library_items'] as List<dynamic>?,
          categoriesJson: data['library_categories'] as List<dynamic>?,
          mangaCacheJson: data['manga_cache'] as Map<String, dynamic>?,
          animeCacheJson: data['anime_cache'] as Map<String, dynamic>?,
          movieCacheJson: data['movie_cache'] as Map<String, dynamic>?,
        );
      }
    } catch (e) {
      debugPrint('Failed to apply cloud sync payload: $e');
    }
  }

  void _setStatus(SyncStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  String _parseHttpError(dynamic err) {
    if (err is SocketException) {
      return 'Network error: Server unreachable at $_serverUrl';
    } else if (err is TimeoutException) {
      return 'Request timed out. Please check your internet connection.';
    }
    return err.toString().replaceAll('Exception: ', '');
  }
}
