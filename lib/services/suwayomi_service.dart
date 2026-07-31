import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'suwayomi_manager.dart';

class SuwayomiService {
  static final SuwayomiService _instance = SuwayomiService._internal();
  factory SuwayomiService() => _instance;
  SuwayomiService._internal();

  Future<void> seedExternalRepositories() async {
    try {
      await fetchExtensionsIndex();
    } catch (_) {}
  }

  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  static String host = '127.0.0.1';
  static int port = 4567;

  String get _baseUrl => 'http://$host:$port';
  String get _gqlUrl => '$_baseUrl/api/graphql';

  final http.Client _client = http.Client();

  int _generateHash(String input) {
    return input.hashCode.abs();
  }

  static dynamic _parseJsonIsolate(String text) {
    return jsonDecode(text);
  }

  Future<dynamic> _fastJsonDecode(String text) async {
    if (text.length < 2000) {
      return jsonDecode(text);
    }
    return compute(_parseJsonIsolate, text);
  }

  Future<dynamic> _postGraphQL(String query, [Map<String, dynamic>? variables]) async {
    final response = await _client.post(
      Uri.parse(_gqlUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'query': query,
        if (variables != null) 'variables': variables,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final decoded = await _fastJsonDecode(response.body);
      if (decoded['errors'] != null) {
        developer.log('GraphQL errors: ${decoded['errors']}', name: 'SuwayomiService');
      }
      return decoded['data'];
    }
    throw Exception('GraphQL HTTP error: ${response.statusCode}');
  }

  SharedPreferences? _prefs;
  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> registerMangaPath(int hash, String sourceId, String url, {String? extName}) async {
    final prefs = await _getPrefs();
    prefs.setString('manga_path_$hash', '$sourceId:$url');
    if (extName != null && extName.isNotEmpty) {
      prefs.setString('manga_extension_$hash', extName);
    }
  }

  Future<String?> getMangaExtensionName(int hash) async {
    final prefs = await _getPrefs();
    return prefs.getString('manga_extension_$hash');
  }

  Future<Map<String, String>?> getMangaPath(int hash) async {
    final prefs = await _getPrefs();
    final val = prefs.getString('manga_path_$hash');
    if (val == null) return null;
    final parts = val.split(':');
    if (parts.length < 2) return null;
    final sourceId = parts[0];
    final url = parts.sublist(1).join(':');
    return {'sourceId': sourceId, 'url': url};
  }

  Future<void> registerChapterPath(int hash, String sourceId, String url) async {
    final prefs = await _getPrefs();
    prefs.setString('chapter_path_$hash', '$sourceId:$url');
  }

  Future<Map<String, String>?> getChapterPath(int hash) async {
    final prefs = await _getPrefs();
    final val = prefs.getString('chapter_path_$hash');
    if (val == null) return null;
    final parts = val.split(':');
    if (parts.length < 2) return null;
    final sourceId = parts[0];
    final url = parts.sublist(1).join(':');
    return {'sourceId': sourceId, 'url': url};
  }


  static List<Map<String, dynamic>> _userRepoExtensionsCache = [];
  // Prevents infinite retry loop if the repo JSON parse fails and cache stays empty.
  static bool _cacheLoadAttempted = false;

  // Android: tracks which extension packages we have installed locally.
  // Persisted to SharedPreferences so it survives app restarts.
  static Set<String> _androidInstalledPkgs = {};
  static bool _androidInstalledPkgsLoaded = false;

  Future<void> _loadAndroidInstalledPkgs() async {
    if (_androidInstalledPkgsLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('android_installed_ext_pkgs') ?? [];
      _androidInstalledPkgs = list.toSet();
      _androidInstalledPkgsLoaded = true;
    } catch (_) {}
  }

  Future<void> _markExtensionInstalled(String pkgName) async {
    _androidInstalledPkgs.add(pkgName);
    _androidInstalledPkgsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('android_installed_ext_pkgs', _androidInstalledPkgs.toList());
    } catch (_) {}
  }

  Future<void> _markExtensionUninstalled(String pkgName) async {
    _androidInstalledPkgs.remove(pkgName);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('android_installed_ext_pkgs', _androidInstalledPkgs.toList());
    } catch (_) {}
  }

  // Prevents concurrent install calls for the same package (was causing loop).
  static final Set<String> _pendingInstalls = {};

  Future<List<String>> getUserRepos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('user_extension_repos') ?? [];
      return list
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && (s.startsWith('http://') || s.startsWith('https://')))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removeRepoUrl(String url) async {
    final cleanUrl = url.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList('user_extension_repos') ?? [];
      currentList.removeWhere((item) => item.trim() == cleanUrl);
      await prefs.setStringList('user_extension_repos', currentList);
    } catch (_) {}
    _userRepoExtensionsCache.clear();
    _cacheLoadAttempted = false;
    changeNotifier.value++;
  }

  // Fetch all extensions (installed AND available in user-added stores)
  Future<List<dynamic>> getExtensions() async {
    try {
      final List<String> userRepos = await getUserRepos();
      final bool hasUserRepos = userRepos.isNotEmpty;

      if (!hasUserRepos) {
        _userRepoExtensionsCache.clear();
      }

      // Collect installed extensions from Suwayomi (GraphQL & REST)
      // On Android, Suwayomi server is not running locally — skip server calls entirely
      // to avoid 35s+ timeouts. Installed state on Android is tracked by the APK manager.
      final Map<String, Map<String, dynamic>> installedMap = {};
      final Map<String, Map<String, dynamic>> gqlAvailableMap = {};

      final bool isAndroid = !kIsWeb && Platform.isAndroid;

      if (isAndroid) {
        // ── Android path ──────────────────────────────────────────────────────
        // Load installed packages from SharedPreferences (instant, in-memory after first load)
        await _loadAndroidInstalledPkgs();

        // Try lightweight /api/installed from the local Tachiyomi server (3s timeout).
        // Skip GraphQL entirely on Android — mutations reach the local server and
        // trigger unintended extension operations.
        try {
          final localResp = await http
              .get(Uri.parse('$_baseUrl/api/installed'))
              .timeout(const Duration(seconds: 3));
          if (localResp.statusCode == 200) {
            final installedData = await _fastJsonDecode(localResp.body);
            final installedList = installedData['data'] as List? ?? [];
            for (var ext in installedList) {
              final String pkg = ext['pkg']?.toString() ?? '';
              if (pkg.isEmpty) continue;
              _androidInstalledPkgs.add(pkg);
              final String iconName = ext['icon']?.toString() ?? 'icon/$pkg.png';
              final String iconCdn =
                  'https://raw.githubusercontent.com/keiyoushi/extensions/repo/$iconName';
              installedMap[pkg] = {
                'id': pkg,
                'name': ext['name'] ?? '',
                'pkgName': pkg,
                'versionName': ext['version'] ?? '',
                'isInstalled': true,
                'hasUpdate': ext['hasUpdate'] == true || ext['hasUpdate'] == 1,
                'lang': ext['lang'] ?? 'en',
                'nsfw': (ext['nsfw'] ?? 0) == 1,
                'iconUrl': ext['iconUrl']?.toString() ?? iconCdn,
                'sources': ext['sources'] ?? [],
              };
            }
          }
        } catch (_) {}

        // Also mark packages we know are installed from SharedPreferences
        // (covers case where server isn't ready yet or was freshly installed)
        for (final pkg in _androidInstalledPkgs) {
          if (!installedMap.containsKey(pkg)) {
            installedMap[pkg] = {
              'id': pkg,
              'pkgName': pkg,
              'name': pkg,
              'versionName': '',
              'isInstalled': true,
              'hasUpdate': false,
              'lang': 'en',
              'nsfw': false,
              'iconUrl': 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/icon/$pkg.png',
              'sources': <dynamic>[],
            };
          }
        }
      } else {
        // ── Desktop path ──────────────────────────────────────────────────────
        // 1. GraphQL extensions query (desktop/Suwayomi-Server only)
        try {
          const gqlQuery = '''
            query {
              extensions {
                nodes {
                  pkgName
                  name
                  versionName
                  isInstalled
                  hasUpdate
                  lang
                  isNsfw
                  iconUrl
                }
              }
            }
          ''';
          final data = await _postGraphQL(gqlQuery);
          if (data != null && data['extensions']?['nodes'] != null) {
            final List nodes = data['extensions']['nodes'] as List;
            for (final ext in nodes) {
              final pkg = ext['pkgName']?.toString() ?? '';
              if (pkg.isEmpty) continue;
              final bool isInst = ext['isInstalled'] == true;
              final item = <String, dynamic>{
                'id': pkg,
                'name': ext['name'] ?? '',
                'pkgName': pkg,
                'versionName': ext['versionName'] ?? ext['version'] ?? '',
                'isInstalled': isInst,
                'hasUpdate': ext['hasUpdate'] == true || ext['hasUpdate'] == 1,
                'lang': ext['lang'] ?? 'en',
                'nsfw': ext['isNsfw'] == true || ext['nsfw'] == true,
                'iconUrl': ext['iconUrl']?.toString() ?? '',
              };
              if (isInst) {
                installedMap[pkg] = item;
              } else {
                gqlAvailableMap[pkg] = item;
              }
            }
          }
        } catch (e) {
          developer.log('GraphQL installed query error: $e', name: 'SuwayomiService');
        }

        // 2. REST API v1 installed fallback (desktop only)
        try {
          final v1Resp = await http.get(Uri.parse('$_baseUrl/api/v1/extension/list')).timeout(const Duration(seconds: 5));
          if (v1Resp.statusCode == 200) {
            final List v1List = (await _fastJsonDecode(v1Resp.body)) as List;
            for (final ext in v1List) {
              final pkg = ext['pkgName']?.toString() ?? ext['pkg']?.toString() ?? '';
              final bool isInst = ext['installed'] == true || ext['isInstalled'] == true;
              if (pkg.isNotEmpty && isInst) {
                installedMap[pkg] = <String, dynamic>{
                  'id': ext['id']?.toString() ?? pkg,
                  'name': ext['name'] ?? '',
                  'pkgName': pkg,
                  'versionName': ext['versionName'] ?? ext['version'] ?? '',
                  'isInstalled': true,
                  'hasUpdate': ext['hasUpdate'] == true || ext['hasUpdate'] == 1,
                  'lang': ext['lang'] ?? 'en',
                  'nsfw': ext['nsfw'] == true || ext['isNsfw'] == true,
                  'iconUrl': ext['iconUrl']?.toString() ?? '',
                };
              }
            }
          }
        } catch (_) {}

        // 3. Local Native Engine installed fallback (/api/installed) — desktop fallback
        try {
          final localResp = await http.get(Uri.parse('$_baseUrl/api/installed')).timeout(const Duration(seconds: 5));
          if (localResp.statusCode == 200) {
            final installedData = await _fastJsonDecode(localResp.body);
            final installedList = installedData['data'] as List? ?? [];
            for (var ext in installedList) {
              final String pkg = ext['pkg']?.toString() ?? '';
              if (pkg.isEmpty) continue;
              final String iconName = ext['icon']?.toString() ?? 'icon/$pkg.png';
              final String iconCdn = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/$iconName';
              installedMap[pkg] = {
                'id': pkg,
                'name': ext['name'] ?? '',
                'pkgName': pkg,
                'versionName': ext['version'] ?? '',
                'isInstalled': true,
                'hasUpdate': ext['hasUpdate'] == true || ext['hasUpdate'] == 1,
                'lang': ext['lang'] ?? 'en',
                'nsfw': (ext['nsfw'] ?? 0) == 1,
                'iconUrl': ext['iconUrl']?.toString() ?? iconCdn,
                'sources': ext['sources'] ?? [],
              };
            }
          }
        } catch (_) {}
      }

      // IF USER HAS ADDED NO REPOS: RETURN ONLY INSTALLED EXTENSIONS (ZERO AVAILABLE UNINSTALLED EXTENSIONS)
      if (!hasUserRepos) {
        _userRepoExtensionsCache.clear();
        return installedMap.values.toList();
      }

      // Load user repository extensions if cache is empty.
      // Guard with _cacheLoadAttempted: if the JSON parse previously failed and
      // left the cache empty, we must NOT retry on every call — that creates an
      // infinite loop. The sentinel is reset when the user adds/removes a repo.
      if (_userRepoExtensionsCache.isEmpty && userRepos.isNotEmpty && !_cacheLoadAttempted) {
        _cacheLoadAttempted = true;
        await refreshUserRepoExtensionsCache(userRepos);
      }

      // Combine installed map with available user repo extensions
      final Map<String, Map<String, dynamic>> combined = {};

      // 1. Add all installed extensions
      for (final entry in installedMap.entries) {
        combined[entry.key] = Map<String, dynamic>.from(entry.value);
      }

      // 2. Merge available extensions strictly from user-added repositories (contains rich iconUrl & apkUrl)
      for (final ext in _userRepoExtensionsCache) {
        final pkg = ext['pkgName']?.toString() ?? '';
        if (pkg.isEmpty) continue;
        if (combined.containsKey(pkg)) {
          final instVer = combined[pkg]!['versionName']?.toString() ?? '';
          final availVer = ext['versionName']?.toString() ?? '';
          if (availVer.isNotEmpty && instVer.isNotEmpty && availVer != instVer) {
            combined[pkg]!['hasUpdate'] = true;
            combined[pkg]!['availableVersion'] = availVer;
          }
          if (ext['apkUrl'] != null && ext['apkUrl'].toString().isNotEmpty) {
            combined[pkg]!['apkUrl'] = ext['apkUrl'];
          }
          if (ext['iconUrl'] != null && ext['iconUrl'].toString().isNotEmpty) {
            combined[pkg]!['iconUrl'] = ext['iconUrl'];
          }
        } else {
          combined[pkg] = Map<String, dynamic>.from(ext);
          combined[pkg]!['isInstalled'] = false;
        }
      }

      // 3. Add any remaining GraphQL available extensions from Suwayomi Server
      for (final entry in gqlAvailableMap.entries) {
        final pkg = entry.key;
        if (!combined.containsKey(pkg)) {
          combined[pkg] = Map<String, dynamic>.from(entry.value);
        }
      }

      // 4. Normalize iconUrl for all items
      for (final item in combined.values) {
        final pkg = item['pkgName']?.toString() ?? '';
        var icon = item['iconUrl']?.toString() ?? '';
        if (icon.isEmpty) {
          icon = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/icon/$pkg.png';
        } else if (icon.startsWith('/')) {
          icon = '$_baseUrl$icon';
        }
        item['iconUrl'] = icon;
      }

      return combined.values.toList();
    } catch (e, stack) {
      developer.log('getExtensions Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return [];
    }
  }

  Future<void> refreshUserRepoExtensionsCache(List<String> userRepos) async {
    final List<Map<String, dynamic>> repoExts = [];
    for (final repoUrl in userRepos) {
      try {
        var fetchUrl = repoUrl.trim();
        fetchUrl = fetchUrl.replaceAll('https://github.com/', 'https://raw.githubusercontent.com/');
        fetchUrl = fetchUrl.replaceAll('/raw/repo/', '/repo/');
        if (fetchUrl.endsWith('.pb')) {
          fetchUrl = '${fetchUrl.substring(0, fetchUrl.length - 3)}.json';
        }
        final repoResp = await http.get(Uri.parse(fetchUrl)).timeout(const Duration(seconds: 15));
        if (repoResp.statusCode == 200) {
          final dynamic decoded = await _fastJsonDecode(repoResp.body);
          List repoList = [];
          if (decoded is Map) {
            final dynamic extListField = decoded['extensionList'];
            if (extListField is List) {
              // Old format: "extensionList": [...]
              repoList = extListField;
            } else if (extListField is Map && extListField['extensions'] is List) {
              // New Keiyoushi format: "extensionList": { "extensions": [...] }
              repoList = extListField['extensions'] as List;
            } else if (decoded['extensions'] is List) {
              // Fallback: root-level "extensions" key
              repoList = decoded['extensions'] as List;
            }
          } else if (decoded is List) {
            // Plain array format
            repoList = decoded;
          }
          for (final ext in repoList) {
            final String pkg = ext['packageName']?.toString() ?? ext['pkg']?.toString() ?? '';
            if (pkg.isEmpty) continue;
            final Map res = ext['resources'] as Map? ?? {};
            final String apkUrl = res['apkUrl']?.toString() ?? ext['apkUrl']?.toString() ?? 'https://cdn.jsdelivr.net/gh/keiyoushi/extensions@repo/apk/$pkg.apk';
            final String iconUrl = res['iconUrl']?.toString() ?? ext['iconUrl']?.toString() ?? '';
            final List sources = ext['sources'] as List? ?? [];
            final String lang = sources.isNotEmpty ? (sources.first['language']?.toString() ?? 'en') : (ext['lang']?.toString() ?? 'en');
            final String warning = ext['contentWarning']?.toString() ?? '';
            final bool isNsfw = warning.contains('NSFW') || (ext['nsfw'] ?? 0) == 1;
            repoExts.add({
              'id': pkg,
              'name': ext['name'] ?? '',
              'pkgName': pkg,
              'versionName': ext['versionName'] ?? ext['version'] ?? '',
              'isInstalled': false,
              'hasUpdate': false,
              'lang': lang,
              'nsfw': isNsfw,
              'apkUrl': apkUrl,
              'iconUrl': iconUrl,
              'sources': sources,
            });
          }
        }
      } catch (_) {}
    }
    _userRepoExtensionsCache = repoExts;
    // If we successfully loaded extensions, allow future calls to re-fetch
    // (e.g., after app resumes or a new repo is added).
    if (repoExts.isNotEmpty) {
      _cacheLoadAttempted = false;
    }
  }

  Future<bool> updateExtension(String pkgName, {String? extId}) async {
    final bool isAndroid = !kIsWeb && Platform.isAndroid;

    if (!isAndroid) {
      // Desktop only: try GraphQL update first
      try {
        const gqlQuery = '''
          mutation UpdateExt(\$id: String!) {
            updateExtension(input: { id: \$id, patch: {} }) {
              extension {
                pkgName
                isInstalled
                hasUpdate
                versionName
              }
            }
          }
        ''';
        final data = await _postGraphQL(gqlQuery, {'id': extId ?? pkgName});
        if (data != null && data['updateExtension'] != null) {
          clearSourcesCache();
          unawaited(fetchExtensionsIndex());
          return true;
        }
      } catch (e) {
        developer.log('GraphQL updateExtension failed, falling back to install: $e', name: 'SuwayomiService');
      }
    }

    // Android + desktop fallback: re-install (uses the Android fast path on Android)
    final result = await installExtension(pkgName, extId: extId);
    if (result && !isAndroid) {
      clearSourcesCache();
      unawaited(fetchExtensionsIndex());
    }
    return result;
  }

  // Add an extension repository URL (Works on both Android local engine and Desktop Suwayomi-Server instantly without restart)
  Future<void> addRepoUrl(String url, {String? name}) async {
    var cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    if (cleanUrl.endsWith('/')) {
      cleanUrl = '${cleanUrl}index.pb';
    }

    // 1. Save locally to SharedPreferences user repo list
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList('user_extension_repos') ?? [];
      if (!currentList.contains(cleanUrl)) {
        currentList.add(cleanUrl);
        await prefs.setStringList('user_extension_repos', currentList);
      }
    } catch (_) {}

    // 2. Refresh cache immediately in Dart for zero-restart availability
    final userRepos = await getUserRepos();
    await refreshUserRepoExtensionsCache(userRepos);

    // 3. Notify UI immediately — don't wait for slow server calls below
    changeNotifier.value++;

    // 4. Server-side registrations (best-effort, all failures silently ignored)
    // Run these unawaited so UI is never blocked by them on Android
    unawaited(() async {
      // Android / Local Engine API (/api/repos/add)
      try {
        final queryName = name != null && name.trim().isNotEmpty ? '&name=${Uri.encodeComponent(name.trim())}' : '';
        final addUrl = Uri.parse('$_baseUrl/api/repos/add?url=${Uri.encodeComponent(cleanUrl)}$queryName');
        await http.get(addUrl).timeout(const Duration(seconds: 5));
      } catch (_) {}

      // Desktop / Suwayomi-Server GraphQL (addExtensionStore)
      try {
        const addStoreGql = '''
          mutation AddStore(\$url: String!) {
            addExtensionStore(input: { indexUrl: \$url }) {
              extensionStore {
                indexUrl
                name
              }
            }
          }
        ''';
        await _postGraphQL(addStoreGql, {'url': cleanUrl});
      } catch (e) {
        developer.log('GraphQL addExtensionStore error: $e', name: 'SuwayomiService');
      }

      // Suwayomi-Server REST v1 /api/v1/extension/store/add
      try {
        await http.post(
          Uri.parse('$_baseUrl/api/v1/extension/store/add'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'url': cleanUrl, 'indexUrl': cleanUrl}),
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }());

    // 5. Trigger background fetch/refresh on Suwayomi-Server (desktop only —
    //    on Android the local cache was already refreshed above and server calls
    //    are skipped inside fetchExtensionsIndex anyway).
    final bool isAndroidDevice = !kIsWeb && Platform.isAndroid;
    if (!isAndroidDevice) {
      unawaited(fetchExtensionsIndex());
    }
  }

  Future<void> fetchExtensionsIndex() async {
    final userRepos = await getUserRepos();
    if (userRepos.isNotEmpty) {
      await refreshUserRepoExtensionsCache(userRepos);
    }

    // Server-side refresh calls — skip entirely on Android.
    // On Android there is no local Suwayomi server; hitting these endpoints
    // could trigger unintended auto-installs or loop the refresh cycle.
    final bool isAndroid = !kIsWeb && Platform.isAndroid;
    if (isAndroid) return;

    try {
      await http.get(Uri.parse('$_baseUrl/api/repos/refresh-all')).timeout(const Duration(seconds: 5)).catchError((_) => http.Response('', 500));
    } catch (_) {}

    try {
      const gqlQuery = '''
        mutation {
          fetchExtensions(input: {}) {
            clientMutationId
          }
        }
      ''';
      await _postGraphQL(gqlQuery);
    } catch (e) {
      developer.log('fetchExtensionsIndex error: $e', name: 'SuwayomiService');
    }
  }

  Future<bool> installExtension(String pkgName, {String? extId, String? apkUrl}) async {
    // Guard: one install at a time per package. Prevents the loop where a
    // changeNotifier fire or duplicate UI tap causes a second install flow to
    // start while the first is still running.
    if (_pendingInstalls.contains(pkgName)) {
      developer.log('installExtension: $pkgName already in progress, ignoring', name: 'SuwayomiService');
      return false;
    }
    _pendingInstalls.add(pkgName);
    try {
      final id = extId ?? pkgName;
      final bool isAndroid = !kIsWeb && Platform.isAndroid;

      // ── ANDROID FAST PATH ─────────────────────────────────────────────────
      if (isAndroid) {
        // Resolve APK URL from cache
        String targetApkUrl = apkUrl ?? '';
        if (targetApkUrl.isEmpty) {
          for (final item in _userRepoExtensionsCache) {
            final p = item['pkgName']?.toString() ?? '';
            if (p == pkgName || p == id) {
              final u = item['apkUrl']?.toString() ?? '';
              if (u.startsWith('http')) { targetApkUrl = u; break; }
            }
          }
        }
        if (targetApkUrl.isEmpty) {
          targetApkUrl =
              'https://raw.githubusercontent.com/keiyoushi/extensions/repo/apk/$pkgName.apk';
        }

        // 1. Local Tachiyomi server — try multiple URL formats
        // Only block the MethodChannel fallback on TimeoutException (server is
        // actively installing). For any other outcome (bad response, non-success
        // body) fall through sequentially — the pending-install guard makes this safe.
        bool serverTimedOut = false;
        for (final installUrl in [
          // Pass APK URL explicitly (most compatible format)
          '$_baseUrl/api/install?url=${Uri.encodeComponent(targetApkUrl)}&pkg=$pkgName',
          // Package-name-only fallback
          '$_baseUrl/api/install?pkg=$pkgName',
        ]) {
          bool triedThisUrl = false;
          try {
            final response = await http
                .get(Uri.parse(installUrl))
                .timeout(const Duration(seconds: 90));
            triedThisUrl = true;
            if (response.statusCode == 200) {
              final decoded = jsonDecode(response.body);
              final bool ok = decoded['ok'] == true ||
                  decoded['success'] == true ||
                  decoded['installed'] == true ||
                  decoded['result'] == 'success' ||
                  decoded['status'] == 'ok';
              if (ok) {
                await _markExtensionInstalled(pkgName);
                clearSourcesCache();
                changeNotifier.value++;
                return true;
              }
            }
          } on TimeoutException {
            // Server is actively installing (>90s) — do NOT fire MethodChannel
            // concurrently; that's what caused the loop. Mark optimistically.
            serverTimedOut = true;
            developer.log('Android /api/install timed out — server still installing', name: 'SuwayomiService');
            await _markExtensionInstalled(pkgName);
            clearSourcesCache();
            changeNotifier.value++;
            return true;
          } catch (e) {
            if (!triedThisUrl) {
              // Connection refused / unreachable on first URL — skip second URL too
              developer.log('Android /api/install unreachable: $e', name: 'SuwayomiService');
              break;
            }
            developer.log('Android /api/install error ($installUrl): $e', name: 'SuwayomiService');
          }
          if (serverTimedOut) break;
        }

        // 2. Sequential MethodChannel fallback — safe because:
        //    a) _pendingInstalls guard blocks any concurrent second call
        //    b) We only reach here if the server returned a non-success response
        //       (or was unreachable) — NOT if it timed out (handled above).
        try {
          final tempDir = await getTemporaryDirectory();
          final targetFile = File('${tempDir.path}/$pkgName.apk');
          final resp = await http
              .get(Uri.parse(targetApkUrl))
              .timeout(const Duration(seconds: 60));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            await targetFile.writeAsBytes(resp.bodyBytes);
            const channel = MethodChannel('com.example.watch_any/native_path');
            await channel.invokeMethod('installApk', {'filePath': targetFile.path});
            await _markExtensionInstalled(pkgName);
            clearSourcesCache();
            changeNotifier.value++;
            return true;
          }
        } catch (e) {
          developer.log('Android APK download/install error: $e', name: 'SuwayomiService');
        }

        return false;
      }

      // ── DESKTOP PATH ──────────────────────────────────────────────────────
      // 1. Local Engine API (desktop fallback)
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/install?pkg=$pkgName'),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded['ok'] == true) {
            clearSourcesCache();
            changeNotifier.value++;
            return true;
          }
        }
      } catch (e) {
        developer.log('Engine API install error: $e', name: 'SuwayomiService');
      }

      // 1. Primary Suwayomi Server GraphQL updateExtension (patch: { install: true })
      for (final targetId in [id, pkgName]) {
        try {
          const gqlQuery = '''
            mutation InstallExt(\$id: String!) {
              updateExtension(input: { id: \$id, patch: { install: true } }) {
                extension {
                  pkgName
                  isInstalled
                }
              }
            }
          ''';
          final data = await _postGraphQL(gqlQuery, {'id': targetId});
          if (data != null && data['updateExtension']?['extension']?['isInstalled'] == true) {
            clearSourcesCache();
            changeNotifier.value++;
            return true;
          }
        } catch (e) {
          developer.log('GraphQL updateExtension install ($targetId) error: $e', name: 'SuwayomiService');
        }
      }

      // 3. REST API v1 POST pkgName / id
      for (final endpoint in [
        '/api/v1/extension/install/$pkgName',
        '/api/v1/extension/store/install/$pkgName',
        '/api/v1/extension/install/$id',
      ]) {
        try {
          final v1Resp = await http.post(Uri.parse('$_baseUrl$endpoint')).timeout(const Duration(seconds: 15));
          if (v1Resp.statusCode >= 200 && v1Resp.statusCode < 300) {
            clearSourcesCache();
            changeNotifier.value++;
            return true;
          }
        } catch (_) {}
      }

      // 4. Desktop APK Download & Multipart Upload to Suwayomi-Server
      String targetApkUrl = apkUrl ?? '';
      if (targetApkUrl.isEmpty || !targetApkUrl.startsWith('http') || targetApkUrl.endsWith('$pkgName.apk')) {
        for (final item in _userRepoExtensionsCache) {
          final p = item['pkgName']?.toString() ?? '';
          if (p == pkgName || p == id) {
            if (item['apkUrl'] != null && item['apkUrl'].toString().startsWith('http')) {
              targetApkUrl = item['apkUrl'].toString();
              break;
            }
          }
        }
      }

      if (targetApkUrl.isEmpty || !targetApkUrl.startsWith('http')) {
        try {
          final indexResp = await http.get(Uri.parse('https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json')).timeout(const Duration(seconds: 15));
          if (indexResp.statusCode == 200) {
            final decoded = await _fastJsonDecode(indexResp.body);
            List extList = [];
            if (decoded is Map && decoded['extensionList'] is List) {
              extList = decoded['extensionList'] as List;
            } else if (decoded is List) {
              extList = decoded;
            }
            final match = extList.firstWhere(
              (e) {
                final p = e['packageName']?.toString() ?? e['pkg']?.toString() ?? '';
                return p == pkgName || p == id || (p.isNotEmpty && (p.endsWith(pkgName) || pkgName.endsWith(p)));
              },
              orElse: () => null,
            );
            if (match != null && match['resources'] is Map) {
              final res = match['resources'] as Map;
              if (res['apkUrl'] != null && res['apkUrl'].toString().isNotEmpty) {
                targetApkUrl = res['apkUrl'].toString();
              }
            }
          }
        } catch (e) {
          developer.log('Error resolving Keiyoushi APK URL: $e', name: 'SuwayomiService');
        }
      }

      if (targetApkUrl.isEmpty || !targetApkUrl.startsWith('http')) {
        targetApkUrl = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/apk/$pkgName.apk';
      }

      try {
        final apkResponse = await http.get(Uri.parse(targetApkUrl)).timeout(const Duration(seconds: 45));
        if (apkResponse.statusCode == 200 && apkResponse.bodyBytes.isNotEmpty) {
          // A. GraphQL Multipart Upload (installExternalExtension)
          try {
            final gqlReq = http.MultipartRequest('POST', Uri.parse(_gqlUrl));
            gqlReq.fields['operations'] = jsonEncode({
              'query': 'mutation (\$file: Upload!) { installExternalExtension(input: { extensionFile: \$file }) { extension { pkgName isInstalled } } }',
              'variables': {'file': null},
            });
            gqlReq.fields['map'] = jsonEncode({
              '0': ['variables.file'],
            });
            gqlReq.files.add(http.MultipartFile.fromBytes('0', apkResponse.bodyBytes, filename: '$pkgName.apk'));
            final streamedResp = await gqlReq.send().timeout(const Duration(seconds: 30));
            final respStr = await streamedResp.stream.bytesToString();
            if (streamedResp.statusCode == 200 && respStr.contains('installExternalExtension')) {
              clearSourcesCache();
              unawaited(fetchExtensionsIndex());
              changeNotifier.value++;
              return true;
            }
          } catch (e) {
            developer.log('GraphQL installExternalExtension upload error: $e', name: 'SuwayomiService');
          }

          // B. REST Multipart fallback
          for (final uploadPath in ['/api/v1/extension/install', '/api/v1/extension/install/file', '/api/v1/extension/upload']) {
            for (final fieldName in ['file', 'apk', 'extension']) {
              try {
                final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$uploadPath'));
                request.files.add(http.MultipartFile.fromBytes(fieldName, apkResponse.bodyBytes, filename: '$pkgName.apk'));
                final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
                if (streamedResponse.statusCode >= 200 && streamedResponse.statusCode < 300) {
                  clearSourcesCache();
                  unawaited(fetchExtensionsIndex());
                  changeNotifier.value++;
                  return true;
                }
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        developer.log('Desktop APK download & multipart install error: $e', name: 'SuwayomiService');
      }

      // 4. REST API v1 POST pkgName
      try {
        final v1Resp = await http.post(Uri.parse('$_baseUrl/api/v1/extension/install/$pkgName')).timeout(const Duration(seconds: 15));
        if (v1Resp.statusCode == 200) {
          clearSourcesCache();
          changeNotifier.value++;
          return true;
        }
      } catch (_) {}

      // 5. Android System PackageInstaller Intent Fallback
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final tempDir = await getTemporaryDirectory();
          final targetFile = File('${tempDir.path}/$pkgName.apk');
          final resp = await http.get(Uri.parse(targetApkUrl)).timeout(const Duration(seconds: 60));
          if (resp.statusCode == 200) {
            await targetFile.writeAsBytes(resp.bodyBytes);
            const channel = MethodChannel('com.example.watch_any/native_path');
            await channel.invokeMethod('installApk', {'filePath': targetFile.path});
            clearSourcesCache();
            changeNotifier.value++;
            return true;
          }
        } catch (e) {
          developer.log('Android native APK installer error: $e', name: 'SuwayomiService');
        }
      }

      return false;
    } catch (e, stack) {
      developer.log('installExtension Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return false;
    } finally {
      _pendingInstalls.remove(pkgName);
    }
  }



  Future<bool> uninstallExtension(String pkgName, {String? extId}) async {
    try {
      final bool isAndroid = !kIsWeb && Platform.isAndroid;

      // ── ANDROID FAST PATH ─────────────────────────────────────────────────
      // Skip GraphQL/REST mutations — use native channel + system dialog.
      if (isAndroid) {
        // 1. Native MethodChannel uninstall (triggers Android system uninstall dialog)
        try {
          const channel = MethodChannel('com.example.watch_any/native_path');
          await channel.invokeMethod('uninstallApk', {'pkgName': pkgName});
          await _markExtensionUninstalled(pkgName);
          clearSourcesCache();
          changeNotifier.value++;
          return true;
        } catch (e) {
          developer.log('Android uninstallApk channel error: $e', name: 'SuwayomiService');
        }

        // 2. Fallback: open system App Details page
        try {
          final Uri uri = Uri.parse('package:$pkgName');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
            await _markExtensionUninstalled(pkgName);
            clearSourcesCache();
            changeNotifier.value++;
            return true;
          }
        } catch (e) {
          developer.log('Android package details launch error: $e', name: 'SuwayomiService');
        }

        return false;
      }

      // ── DESKTOP PATH ──────────────────────────────────────────────────────
      final id = extId ?? pkgName;

      // 1. Primary Suwayomi Server GraphQL updateExtension (patch: { uninstall: true })
      for (final targetId in [id, pkgName]) {
        try {
          const gqlQuery = '''
            mutation UninstallExt(\$id: String!) {
              updateExtension(input: { id: \$id, patch: { uninstall: true } }) {
                extension {
                  pkgName
                  isInstalled
                }
              }
            }
          ''';
          final data = await _postGraphQL(gqlQuery, {'id': targetId});
          if (data != null && data['updateExtension'] != null) {
            clearSourcesCache();
            changeNotifier.value++;
            return true;
          }
        } catch (e) {
          developer.log('GraphQL updateExtension uninstall ($targetId) error: $e', name: 'SuwayomiService');
        }
      }

      // 2. Try REST HTTP DELETE
      try {
        final delResp = await http.delete(Uri.parse('$_baseUrl/api/v1/extension/pkg/$pkgName')).timeout(const Duration(seconds: 15));
        if (delResp.statusCode == 200) { changeNotifier.value++; return true; }
      } catch (_) {}

      // 3. Try REST HTTP POST uninstall
      try {
        final postResp = await http.post(Uri.parse('$_baseUrl/api/v1/extension/uninstall/$pkgName')).timeout(const Duration(seconds: 15));
        if (postResp.statusCode == 200) { changeNotifier.value++; return true; }
      } catch (_) {}

      // 4. Legacy REST API fallback
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/uninstall?pkg=$pkgName'),
        ).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded['ok'] == true || decoded['removed'] == true) {
            changeNotifier.value++;
            return true;
          }
        }
      } catch (_) {}

      return false;
    } catch (e, stack) {
      developer.log('uninstallExtension Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return false;
    }
  }


  List<dynamic>? _cachedSources;

  void clearSourcesCache() {
    _cachedSources = null;
  }

  // Fetch active manga sources
  Future<List<dynamic>> getSources({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSources != null && _cachedSources!.isNotEmpty) {
      return _cachedSources!;
    }
    try {
      // 1. Try GraphQL sources query (Primary - returns real 64-bit LongString IDs for all installed extensions)
      try {
        const gqlQuery = '''
          query {
            sources {
              nodes {
                id
                name
                lang
                supportsLatest
                isNsfw
              }
            }
          }
        ''';
        final data = await _postGraphQL(gqlQuery);
        if (data != null && data['sources']?['nodes'] != null) {
          final List list = data['sources']['nodes'] as List;
          final mapped = list.map((source) => {
            'id': source['id']?.toString() ?? '',
            'name': source['name'] ?? '',
            'lang': source['lang'] ?? 'en',
            'isNsfw': source['isNsfw'] == true,
            'supportsLatest': source['supportsLatest'] ?? true,
          }).where((s) => (s['id'] as String).isNotEmpty).toList();
          if (mapped.isNotEmpty) {
            _cachedSources = mapped;
            return mapped;
          }
        }
      } catch (e) {
        developer.log('GraphQL sources query failed: $e', name: 'SuwayomiService');
      }

      // 2. Try local server GET /api/sources fallback
      try {
        final response = await http.get(Uri.parse('$_baseUrl/api/sources')).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded['ok'] == true && decoded['data'] is List) {
            final list = decoded['data'] as List;
            if (list.isNotEmpty) {
              final mapped = list.map((source) => {
                'id': source['id']?.toString() ?? '',
                'name': source['name'] ?? '',
                'lang': source['lang'] ?? 'en',
                'isNsfw': false,
                'supportsLatest': source['supportsLatest'] ?? true,
              }).where((s) => (s['id'] as String).isNotEmpty).toList();
              _cachedSources = mapped;
              return mapped;
            }
          }
        }
      } catch (e) {
        developer.log('GET /api/sources failed: $e', name: 'SuwayomiService');
      }

      // 3. Extract sources from installed extensions fallback (only if real 64-bit ID is present)
      try {
        final extensions = await getExtensions();
        final installedSources = <Map<String, dynamic>>[];
        for (var ext in extensions) {
          if (ext['isInstalled'] != true) continue;
          final sources = ext['sources'] as List? ?? [];
          for (var src in sources) {
            final String id = src['id']?.toString() ?? '';
            if (id.isEmpty || !RegExp(r'^\d+$').hasMatch(id)) continue; // Must be a valid numeric 64-bit ID
            installedSources.add({
              'id': id,
              'name': src['name'] ?? ext['name'] ?? '',
              'lang': src['lang'] ?? ext['lang'] ?? 'en',
              'isNsfw': ext['nsfw'] == true,
              'supportsLatest': src['supportsLatest'] ?? true,
              'pkg': ext['pkgName'] ?? ext['id'] ?? '',
            });
          }
        }

        if (installedSources.isNotEmpty) {
          _cachedSources = installedSources;
          return installedSources;
        }
      } catch (e) {
        developer.log('Extract sources from installed extensions failed: $e', name: 'SuwayomiService');
      }

      // 4. REST API v1 fallback
      try {
        final v1Resp = await http.get(Uri.parse('$_baseUrl/api/v1/source/list')).timeout(const Duration(seconds: 10));
        if (v1Resp.statusCode == 200) {
          final List v1List = jsonDecode(v1Resp.body) as List;
          final mapped = v1List.map((source) => {
            'id': source['id']?.toString() ?? '',
            'name': source['name'] ?? '',
            'lang': source['lang'] ?? 'en',
            'isNsfw': source['isNsfw'] == true,
            'supportsLatest': source['supportsLatest'] ?? true,
          }).toList();
          if (mapped.isNotEmpty) {
            _cachedSources = mapped;
            return mapped;
          }
        }
      } catch (_) {}

      return [];
    } catch (e, stack) {
      developer.log('getSources Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // Search or browse catalog from a source
  Future<List<dynamic>> fetchSourceManga({
    required String sourceId,
    required int page,
    String query = "",
    bool latest = false,
  }) async {
    try {
      // 1. GraphQL fetchSourceManga (Primary for POPULAR, LATEST, and SEARCH)
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final String fetchType = query.isNotEmpty ? 'SEARCH' : (latest ? 'LATEST' : 'POPULAR');
          final vars = <String, dynamic>{
            'source': sourceId,
            'type': fetchType,
            'page': page,
            if (query.isNotEmpty) 'query': query,
          };
          const gqlQuery = r'''
            mutation FetchSource($source: LongString!, $type: FetchSourceMangaType!, $page: Int!, $query: String) {
              fetchSourceManga(input: { source: $source, type: $type, page: $page, query: $query }) {
                mangas { id title thumbnailUrl url }
              }
            }
          ''';
          final data = await _postGraphQL(gqlQuery, vars);
          if (data != null && data['fetchSourceManga']?['mangas'] != null) {
            final List mangas = data['fetchSourceManga']['mangas'] as List;
            if (mangas.isNotEmpty || page > 1) {
              return _mapGqlMangas(mangas, sourceId);
            }
          }
        } catch (e) {
          developer.log('GraphQL fetchSourceManga attempt $attempt failed: $e', name: 'SuwayomiService');
        }

        // On first failure for page 1, try auto-installing the extension matching this sourceId!
        if (attempt == 0 && page == 1) {
          try {
            String? pkgToInstall;
            for (var item in _userRepoExtensionsCache) {
              final List sources = item['sources'] is List ? item['sources'] as List : [];
              for (var src in sources) {
                if (src['id']?.toString() == sourceId || _generateHash('${src['name']}:${src['lang']}') == sourceId) {
                  pkgToInstall = item['pkgName']?.toString() ?? item['pkg']?.toString();
                  break;
                }
              }
              if (pkgToInstall != null) break;
            }

            if (pkgToInstall != null && pkgToInstall.isNotEmpty) {
              developer.log('Auto-installing extension $pkgToInstall for source $sourceId...', name: 'SuwayomiService');
              await installExtension(pkgToInstall, extId: pkgToInstall);
              await Future.delayed(const Duration(seconds: 2));
            }
          } catch (autoErr) {
            developer.log('Auto-install attempt error: $autoErr', name: 'SuwayomiService');
          }
        }
      }
      String? lastError;
      // 2. Try v1 REST API — GET popular/latest, POST search
      try {
        if (query.isNotEmpty) {
          final postUrl = '$_baseUrl/api/v1/source/$sourceId/search/$page';
          final postResp = await http.post(
            Uri.parse(postUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': query, 'filters': []}),
          ).timeout(const Duration(seconds: 20));
          if (postResp.statusCode == 200 && !postResp.body.trimLeft().startsWith('<')) {
            final v1Data = await _fastJsonDecode(postResp.body);
            if (v1Data is Map && v1Data['ok'] == false && v1Data['error'] != null) {
              lastError = v1Data['error'].toString();
            } else {
              return _mapV1Mangas(v1Data, sourceId);
            }
          } else {
            lastError = 'HTTP ${postResp.statusCode}: ${postResp.body}';
          }
        } else {
          final v1UrlStr = latest
              ? '$_baseUrl/api/v1/source/$sourceId/latest/$page'
              : '$_baseUrl/api/v1/source/$sourceId/popular/$page';
          final v1Resp = await http.get(Uri.parse(v1UrlStr)).timeout(const Duration(seconds: 20));
          if (v1Resp.statusCode == 200 && !v1Resp.body.trimLeft().startsWith('<')) {
            final v1Data = await _fastJsonDecode(v1Resp.body);
            if (v1Data is Map && v1Data['ok'] == false && v1Data['error'] != null) {
              lastError = v1Data['error'].toString();
            } else {
              return _mapV1Mangas(v1Data, sourceId);
            }
          } else {
            lastError = 'HTTP ${v1Resp.statusCode}: ${v1Resp.body}';
          }
        }
      } catch (e) {
        lastError = e.toString();
      }

      // 3. Legacy API fallback — guard against HTML responses
      try {
        final urlStr = query.isNotEmpty
            ? '$_baseUrl/api/search?sourceId=$sourceId&page=$page&q=${Uri.encodeComponent(query)}'
            : latest
                ? '$_baseUrl/api/latest?sourceId=$sourceId&page=$page'
                : '$_baseUrl/api/popular?sourceId=$sourceId&page=$page';

        final response = await http.get(Uri.parse(urlStr)).timeout(const Duration(seconds: 20));
        final bodyStr = response.body.trimLeft();
        if (bodyStr.startsWith('{')) {
          final decoded = jsonDecode(bodyStr);
          if (decoded['ok'] == false && decoded['error'] != null) {
            throw Exception(decoded['error'].toString());
          }
          if (decoded['ok'] == true && decoded['data']?['mangas'] != null) {
            final list = decoded['data']['mangas'] as List;
            final mapped = <dynamic>[];
            for (var manga in list) {
              final String url = manga['url'] ?? '';
              if (url.isEmpty) continue;
              final int mangaId = manga['id'] ?? _generateHash('$sourceId:$url');
              await registerMangaPath(mangaId, sourceId, url);
              final rawTitle = manga['title']?.toString() ?? '';
              final String title = _sanitizeTitle(rawTitle, url);
              final coverUrl = manga['thumbnailUrl']?.toString() ?? '';
              final proxiedCover = coverUrl.isNotEmpty
                  ? '$_baseUrl/api/image?url=${Uri.encodeComponent(coverUrl)}'
                  : '';
              mapped.add({
                'id': mangaId,
                'title': title,
                'thumbnailUrl': proxiedCover,
                'url': url,
              });
            }
            return mapped;
          }
        }
      } catch (e) {
        lastError = e.toString();
      }

      if (lastError != null && lastError.isNotEmpty) {
        if (lastError.contains('404')) {
          throw Exception('Source unavailable or extension not installed on server');
        }
        throw Exception(lastError);
      }
      return [];
    } catch (e, stack) {
      developer.log('fetchSourceManga Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  List<dynamic> _mapGqlMangas(List mangas, String sourceId) {
    final mapped = <dynamic>[];
    for (var manga in mangas) {
      final String url = manga['url']?.toString() ?? '';
      final int mangaId = manga['id'] is int
          ? manga['id'] as int
          : int.tryParse(manga['id']?.toString() ?? '') ?? _generateHash('$sourceId:$url');
      if (url.isNotEmpty) registerMangaPath(mangaId, sourceId, url);
      final rawTitle = manga['title']?.toString() ?? '';
      final String title = _sanitizeTitle(rawTitle, url);
      final coverUrl = manga['thumbnailUrl']?.toString() ?? '';
      final proxiedCover = coverUrl.isNotEmpty
          ? (coverUrl.startsWith('/')
              ? '$_baseUrl$coverUrl'
              : '$_baseUrl/api/v1/source/$sourceId/cover?url=${Uri.encodeComponent(coverUrl)}')
          : '';
      mapped.add({
        'id': mangaId,
        'title': title,
        'thumbnailUrl': proxiedCover,
        'url': url,
      });
    }
    return mapped;
  }

  List<dynamic> _mapV1Mangas(dynamic v1Data, String sourceId) {
    if (v1Data == null) return [];
    dynamic container = v1Data;
    if (container is Map && container.containsKey('data') && container['data'] != null) {
      container = container['data'];
    }
    final List list = (container is Map ? (container['mangaList'] ?? container['mangas']) : (container is List ? container : [])) as List? ?? [];
    final mapped = <dynamic>[];
    for (var manga in list) {
      final String url = manga['url'] ?? '';
      if (url.isEmpty) continue;
      final int mangaId = manga['id'] ?? _generateHash('$sourceId:$url');
      registerMangaPath(mangaId, sourceId, url);
      final rawTitle = manga['title']?.toString() ?? '';
      final String title = _sanitizeTitle(rawTitle, url);
      final coverUrl = manga['thumbnailUrl']?.toString() ?? '';
      final proxiedCover = coverUrl.isNotEmpty
          ? (coverUrl.startsWith('/')
              ? '$_baseUrl$coverUrl'
              : '$_baseUrl/api/image?url=${Uri.encodeComponent(coverUrl)}')
          : '';
      mapped.add({'id': mangaId, 'title': title, 'thumbnailUrl': proxiedCover, 'url': url});
    }
    return mapped;
  }





  String _sanitizeTitle(String title, String url) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return _titleFromUrl(url);
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return _titleFromUrl(url);
    return trimmed;
  }

  String _titleFromUrl(String url) {
    final segments = url.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return 'Unknown Manga';
    final last = segments.last;
    if (RegExp(r'^\d+$').hasMatch(last) && segments.length >= 2) {
      final prefix = segments[segments.length - 2].replaceAll('-', ' ').replaceAll('_', ' ');
      final capitalized = prefix.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
      return '$capitalized $last';
    }
    return last.replaceAll('-', ' ').replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  // Fetch manga details
  Future<Map<String, dynamic>?> getMangaDetails(int id) async {
    try {
      // 1. Try v1 API directly by ID: GET /api/v1/manga/$id
      try {
        final v1IdResp = await http.get(Uri.parse('$_baseUrl/api/v1/manga/$id')).timeout(const Duration(seconds: 15));
        if (v1IdResp.statusCode == 200) {
          final data = Map<String, dynamic>.from(jsonDecode(v1IdResp.body));
          data['id'] = id;
          data['genre'] = data['genre'] ?? data['genres'] ?? [];
          final coverUrl = data['thumbnailUrl']?.toString() ?? '';
          if (coverUrl.isNotEmpty) {
            data['thumbnailUrl'] = coverUrl.startsWith('http')
                ? '$_baseUrl/api/v1/source/${data['sourceId']}/cover?url=${Uri.encodeComponent(coverUrl)}'
                : '$_baseUrl$coverUrl';
          }
          return data;
        }
      } catch (_) {}

      final pathInfo = await getMangaPath(id);
      if (pathInfo == null) return null;

      var sourceId = pathInfo['sourceId'] ?? '';
      final mangaUrl = pathInfo['url'] ?? '';

      if (sourceId.isEmpty) {
        final savedExt = await getMangaExtensionName(id);
        final sources = await getSources();
        if (savedExt != null && savedExt.isNotEmpty) {
          final match = sources.firstWhere(
            (s) => (s['name']?.toString().toLowerCase() ?? '').contains(savedExt.toLowerCase()),
            orElse: () => null,
          );
          if (match != null) sourceId = match['id']?.toString() ?? '';
        }
        if (sourceId.isEmpty && sources.isNotEmpty) {
          sourceId = sources.first['id']?.toString() ?? '';
        }
      }
      if (sourceId.isEmpty || mangaUrl.isEmpty) return null;

      // 2. Try v1 URL query API
      try {
        final v1Resp = await http.get(
          Uri.parse('$_baseUrl/api/v1/manga?sourceId=$sourceId&url=${Uri.encodeComponent(mangaUrl)}'),
        ).timeout(const Duration(seconds: 15));
        if (v1Resp.statusCode == 200) {
          final data = Map<String, dynamic>.from(jsonDecode(v1Resp.body));
          data['id'] = id;
          data['genre'] = data['genres'] ?? data['genre'] ?? [];
          final coverUrl = data['thumbnailUrl']?.toString() ?? '';
          if (coverUrl.isNotEmpty) {
            data['thumbnailUrl'] = coverUrl.startsWith('http')
                ? '$_baseUrl/api/v1/source/$sourceId/cover?url=${Uri.encodeComponent(coverUrl)}'
                : '$_baseUrl$coverUrl';
          }
          return data;
        }
      } catch (_) {}

      // 3. Legacy fallback
      final response = await http.get(
        Uri.parse('$_baseUrl/api/details?sourceId=$sourceId&url=${Uri.encodeComponent(mangaUrl)}'),
      ).timeout(const Duration(seconds: 15));

      _checkResponse(response);
      final decoded = jsonDecode(response.body);
      if (decoded['ok'] == true && decoded['data'] != null) {
        final data = Map<String, dynamic>.from(decoded['data']);
        data['id'] = id;
        data['genre'] = data['genres'] ?? [];
        final coverUrl = data['thumbnailUrl']?.toString() ?? '';
        if (coverUrl.isNotEmpty) {
          data['thumbnailUrl'] = '$_baseUrl/api/image?url=${Uri.encodeComponent(coverUrl)}';
        }
        return data;
      }
      return null;
    } catch (e, stack) {
      developer.log('getMangaDetails Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return null;
    }
  }

  // Fetch chapters list
  Future<List<dynamic>> getChapters(int mangaId) async {
    try {
      // 1. Try v1 API directly by ID with onlineFetch=true: GET /api/v1/manga/$mangaId/chapters?onlineFetch=true
      try {
        final v1IdResp = await http.get(Uri.parse('$_baseUrl/api/v1/manga/$mangaId/chapters?onlineFetch=true')).timeout(const Duration(seconds: 25));
        if (v1IdResp.statusCode == 200) {
          final list = (await _fastJsonDecode(v1IdResp.body)) as List;
          final mapped = <dynamic>[];
          for (var chapter in list) {
            final String url = chapter['url'] ?? '';
            final int chapterId = chapter['id'] ?? _generateHash('${chapter['mangaId']}:$url');
            await registerChapterPath(chapterId, chapter['sourceId']?.toString() ?? '', url);
            mapped.add({
              'id': chapterId,
              'mangaId': mangaId,
              'name': chapter['name'] ?? 'Chapter',
              'chapterNumber': chapter['chapterNumber'] ?? 1.0,
              'uploadDate': chapter['uploadDate'] ?? chapter['dateUpload'] ?? 0,
              'scanlator': chapter['scanlator'] ?? chapter['scanlatorName'] ?? '',
              'read': chapter['read'] == true,
            });
          }
          return mapped;
        }
      } catch (_) {}

      final pathInfo = await getMangaPath(mangaId);
      if (pathInfo == null) return [];

      final sourceId = pathInfo['sourceId']!;
      final mangaUrl = pathInfo['url']!;

      // 2. Try v1 URL query API
      try {
        final v1Resp = await http.get(
          Uri.parse('$_baseUrl/api/v1/manga/chapters?sourceId=$sourceId&url=${Uri.encodeComponent(mangaUrl)}'),
        ).timeout(const Duration(seconds: 15));
        if (v1Resp.statusCode == 200) {
          final list = (await _fastJsonDecode(v1Resp.body)) as List;
          final mapped = <dynamic>[];
          for (var chapter in list) {
            final String url = chapter['url'] ?? '';
            if (url.isEmpty) continue;
            final int hash = chapter['id'] ?? _generateHash('$sourceId:$url');
            await registerChapterPath(hash, sourceId, url);
            mapped.add({
              'id': hash,
              'mangaId': mangaId,
              'name': chapter['name'] ?? 'Chapter',
              'chapterNumber': chapter['chapterNumber'] ?? 1.0,
              'uploadDate': chapter['dateUpload'] ?? 0,
              'read': false,
            });
          }
          return mapped;
        }
      } catch (_) {}

      // 3. Legacy fallback
      final response = await http.get(
        Uri.parse('$_baseUrl/api/chapters?sourceId=$sourceId&url=${Uri.encodeComponent(mangaUrl)}'),
      ).timeout(const Duration(seconds: 15));

      _checkResponse(response);
      final decoded = jsonDecode(response.body);
      if (decoded['ok'] == true && decoded['data']?['chapters'] != null) {
        final list = decoded['data']['chapters'] as List;
        final mapped = <dynamic>[];

        for (var chapter in list) {
          final String url = chapter['url'] ?? '';
          if (url.isEmpty) continue;

          final int hash = chapter['id'] ?? _generateHash('$sourceId:$url');
          await registerChapterPath(hash, sourceId, url);

          mapped.add({
            'id': hash,
            'mangaId': mangaId,
            'name': chapter['name'] ?? 'Chapter',
            'chapterNumber': chapter['chapterNumber'] ?? 1.0,
            'uploadDate': chapter['dateUpload'] ?? 0,
            'read': false,
          });
        }
        return mapped;
      }
      return [];
    } catch (e, stack) {
      developer.log('getChapters Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return [];
    }
  }

  // Fetch pages list for reading
  Future<List<String>> getChapterPages(int chapterId, {int? mangaId}) async {
    try {
      // 1. Try GraphQL fetchChapterPages mutation
      try {
        const gqlQuery = '''
          mutation FetchPages(\$chapterId: Int!) {
            fetchChapterPages(input: { chapterId: \$chapterId }) {
              chapter {
                id
                mangaId
                sourceOrder
                pageCount
              }
            }
          }
        ''';
        final data = await _postGraphQL(gqlQuery, {'chapterId': chapterId});
        if (data != null && data['fetchChapterPages']?['chapter'] != null) {
          final chap = data['fetchChapterPages']['chapter'];
          final int pageCount = chap['pageCount'] ?? 0;
          final int mId = mangaId ?? chap['mangaId'] ?? 1;
          final int sOrder = chap['sourceOrder'] ?? chapterId;
          if (pageCount > 0) {
            return List.generate(
              pageCount,
              (index) => '$_baseUrl/api/v1/manga/$mId/chapter/$sOrder/page/$index',
            );
          }
        }
      } catch (e) {
        developer.log('GraphQL fetchChapterPages failed: $e', name: 'SuwayomiService');
      }

      // 2. Try v1 API directly by ID: GET /api/v1/chapter/$chapterId/pages
      try {
        final v1IdResp = await http.get(Uri.parse('$_baseUrl/api/v1/chapter/$chapterId/pages')).timeout(const Duration(seconds: 15));
        if (v1IdResp.statusCode == 200 && v1IdResp.body.startsWith('[')) {
          final list = jsonDecode(v1IdResp.body) as List;
          final pages = <String>[];
          for (var page in list) {
            final String pageUrl = page is Map ? (page['imageUrl'] ?? page['url'] ?? '') : page.toString();
            if (pageUrl.isEmpty) continue;
            pages.add(pageUrl.startsWith('http')
                ? pageUrl
                : '$_baseUrl$pageUrl');
          }
          if (pages.isNotEmpty) return pages;
        }
      } catch (_) {}

      final pathInfo = await getChapterPath(chapterId);
      if (pathInfo == null) return [];

      final sourceId = pathInfo['sourceId']!;
      final chapterUrl = pathInfo['url']!;

      // 3. Try v1 URL query API
      try {
        final v1Resp = await http.get(
          Uri.parse('$_baseUrl/api/v1/chapter/pages?sourceId=$sourceId&url=${Uri.encodeComponent(chapterUrl)}'),
        ).timeout(const Duration(seconds: 15));
        if (v1Resp.statusCode == 200 && v1Resp.body.startsWith('[')) {
          final list = jsonDecode(v1Resp.body) as List;
          final pages = <String>[];
          for (var page in list) {
            final String pageUrl = page['imageUrl'] ?? page['url'] ?? '';
            if (pageUrl.isEmpty) continue;
            pages.add(pageUrl.startsWith('http')
                ? '$_baseUrl/api/v1/source/$sourceId/cover?url=${Uri.encodeComponent(pageUrl)}'
                : '$_baseUrl$pageUrl');
          }
          if (pages.isNotEmpty) return pages;
        }
      } catch (_) {}

      // 4. Legacy fallback
      final response = await http.get(
        Uri.parse('$_baseUrl/api/pages?sourceId=$sourceId&url=${Uri.encodeComponent(chapterUrl)}'),
      ).timeout(const Duration(seconds: 15));

      _checkResponse(response);
      final decoded = jsonDecode(response.body);
      if (decoded['ok'] == true && decoded['data']?['pages'] != null) {
        final list = decoded['data']['pages'] as List;
        final pages = <String>[];

        for (var page in list) {
          final String pageUrl = page['imageUrl'] ?? page['url'] ?? '';
          if (pageUrl.isEmpty) continue;

          pages.add('$_baseUrl/api/image?url=${Uri.encodeComponent(pageUrl)}&sourceId=$sourceId');
        }
        return pages;
      }
      return [];
    } catch (e, stack) {
      developer.log('getChapterPages Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return [];
    }
  }

  void _checkResponse(http.Response response) {
    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded['ok'] == false && decoded['error'] != null) {
          throw Exception(decoded['error'].toString());
        }
      } catch (e) {
        if (e is Exception) rethrow;
      }
      throw Exception('Server error: HTTP ${response.statusCode}');
    }
  }
}
