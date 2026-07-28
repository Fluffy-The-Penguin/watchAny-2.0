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

  static final ChangeNotifier changeNotifier = ChangeNotifier();

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
    ).timeout(const Duration(seconds: 15));

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


  // Seed default Keiyoushi repository store on Suwayomi-Server
  Future<void> seedExternalRepositories() async {
    try {
      // 1. Try GraphQL addExtensionStore
      const addStoreQuery = '''
        mutation {
          addExtensionStore(input: { indexUrl: "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json" }) {
            extensionStore {
              indexUrl
              name
            }
          }
        }
      ''';
      await _postGraphQL(addStoreQuery).catchError((_) => null);

      // 2. Trigger fetchExtensions to populate store index
      const fetchQuery = '''
        mutation {
          fetchExtensions(input: {}) {
            clientMutationId
          }
        }
      ''';
      await _postGraphQL(fetchQuery).catchError((_) => null);

      // 3. Fallback REST seed
      final repoUrls = [
        "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json",
        "https://cdn.jsdelivr.net/gh/keiyoushi/extensions@repo/index.min.json",
      ];
      for (final repoUrl in repoUrls) {
        try {
          final addUrl = Uri.parse('$_baseUrl/api/repos/add?url=${Uri.encodeComponent(repoUrl)}');
          await http.get(addUrl).timeout(const Duration(seconds: 5)).catchError((_) => http.Response('', 500));
        } catch (_) {}
      }
    } catch (e) {
      developer.log('Error seeding external repositories: $e', name: 'SuwayomiService');
    }
  }

  // Fetch all extensions (installed AND available in store)
  Future<List<dynamic>> getExtensions() async {
    try {
      // 1. Local Native Server API (/api/installed & /api/list)
      try {
        final responses = await Future.wait([
          http.get(Uri.parse('$_baseUrl/api/installed')).timeout(const Duration(seconds: 15)),
          http.get(Uri.parse('$_baseUrl/api/list')).timeout(const Duration(seconds: 15)),
        ]);


        final instResp = responses[0];
        final listResp = responses[1];

        if (instResp.statusCode == 200 && listResp.statusCode == 200) {
          final installedData = await _fastJsonDecode(instResp.body);
          final listData = await _fastJsonDecode(listResp.body);

          final installedList = installedData['data'] as List? ?? [];
          final listExts = listData['data'] as List? ?? [];

          final Map<String, Map<String, dynamic>> combined = {};

          for (var ext in installedList) {
            final String pkg = ext['pkg']?.toString() ?? '';
            if (pkg.isEmpty) continue;
            final String iconName = ext['icon']?.toString() ?? 'icon/$pkg.png';
            final String iconCdn = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/$iconName';
            final String apkName = ext['apk']?.toString() ?? '$pkg.apk';
            final String apkUrl = ext['apkUrl']?.toString() ?? 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/apk/$apkName';
            combined[pkg] = {
              'id': pkg,
              'name': ext['name'] ?? '',
              'pkgName': pkg,
              'versionName': ext['version'] ?? '',
              'isInstalled': true,
              'hasUpdate': ext['hasUpdate'] == true || ext['hasUpdate'] == 1,
              'lang': ext['lang'] ?? 'en',
              'nsfw': (ext['nsfw'] ?? 0) == 1,
              'apkUrl': apkUrl,
              'iconUrl': ext['iconUrl']?.toString() ?? iconCdn,
              'sources': ext['sources'] ?? [],
            };

          }

          for (var ext in listExts) {
            final String pkg = ext['pkg']?.toString() ?? '';
            if (pkg.isEmpty) continue;
            final String iconName = ext['icon']?.toString() ?? 'icon/$pkg.png';
            final String iconCdn = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/$iconName';
            final String apkName = ext['apk']?.toString() ?? '$pkg.apk';
            final String apkUrl = ext['apkUrl']?.toString() ?? 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/apk/$apkName';
            if (combined.containsKey(pkg)) {
              final instVer = combined[pkg]!['versionName']?.toString() ?? '';
              final availVer = ext['version']?.toString() ?? '';
              if (availVer.isNotEmpty && instVer.isNotEmpty && availVer != instVer) {
                combined[pkg]!['hasUpdate'] = true;
                combined[pkg]!['availableVersion'] = availVer;
              }
              combined[pkg]!['apkUrl'] = apkUrl;
              if (combined[pkg]!['iconUrl'] == null || combined[pkg]!['iconUrl'].toString().isEmpty) {
                combined[pkg]!['iconUrl'] = iconCdn;
              }
              continue;
            }
            combined[pkg] = {
              'id': pkg,
              'name': ext['name'] ?? '',
              'pkgName': pkg,
              'versionName': ext['version'] ?? '',
              'isInstalled': false,
              'hasUpdate': false,
              'lang': ext['lang'] ?? 'en',
              'nsfw': (ext['nsfw'] ?? 0) == 1,
              'apkUrl': apkUrl,
              'iconUrl': ext['iconUrl']?.toString() ?? iconCdn,
            };
          }

          if (combined.isNotEmpty) {
            return combined.values.toList();
          }
        }
      } catch (_) {}

      // 2. Try GraphQL extensions query
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
      try {
        final data = await _postGraphQL(gqlQuery);
        if (data != null && data['extensions']?['nodes'] != null) {
          final List nodes = data['extensions']['nodes'] as List;
          if (nodes.isNotEmpty) {
            return nodes.map((ext) {
              final pkg = ext['pkgName'] ?? '';
              return {
                'id': pkg,
                'name': ext['name'] ?? '',
                'pkgName': pkg,
                'versionName': ext['versionName'] ?? ext['version'] ?? '',
                'isInstalled': ext['isInstalled'] == true,
                'hasUpdate': ext['hasUpdate'] == true || ext['hasUpdate'] == 1,
                'lang': ext['lang'] ?? 'en',
                'nsfw': ext['isNsfw'] == true || ext['nsfw'] == true,
                'iconUrl': ext['iconUrl']?.toString() ?? '',
              };
            }).toList();
          }
        }
      } catch (e) {
        developer.log('GraphQL extensions query failed: $e', name: 'SuwayomiService');
      }


      // 2. REST API v1 fallback
      try {
        final v1Resp = await http.get(Uri.parse('$_baseUrl/api/v1/extension/list')).timeout(const Duration(seconds: 10));
        if (v1Resp.statusCode == 200) {
          final List v1List = (await _fastJsonDecode(v1Resp.body)) as List;
          return v1List.map((ext) {
            final pkg = ext['pkgName'] ?? ext['pkg'] ?? '';
            return {
              'id': ext['id']?.toString() ?? pkg,
              'name': ext['name'] ?? '',
              'pkgName': pkg,
              'versionName': ext['versionName'] ?? ext['version'] ?? '',
              'isInstalled': ext['installed'] == true || ext['isInstalled'] == true,
              'hasUpdate': ext['hasUpdate'] == true || ext['hasUpdate'] == 1,
              'lang': ext['lang'] ?? 'en',
              'nsfw': ext['nsfw'] == true || ext['isNsfw'] == true,
              'iconUrl': ext['iconUrl']?.toString() ?? '',
            };
          }).toList();
        }
      } catch (_) {}

      // 3. Legacy REST API fallback
      final responses = await Future.wait([
        http.get(Uri.parse('$_baseUrl/api/installed')).timeout(const Duration(seconds: 10)),
        http.get(Uri.parse('$_baseUrl/api/list')).timeout(const Duration(seconds: 10)),
      ]).catchError((e) {
        throw Exception('Network request failed: $e');
      });

      final instResp = responses[0];
      final listResp = responses[1];

      if (instResp.statusCode != 200 || listResp.statusCode != 200) {
        throw Exception('Server error: installed_status=${instResp.statusCode}, list_status=${listResp.statusCode}');
      }

      final installedData = await _fastJsonDecode(instResp.body);
      final listData = await _fastJsonDecode(listResp.body);

      final installedList = installedData['data'] as List? ?? [];
      final listExts = listData['data'] as List? ?? [];

      final Map<String, Map<String, dynamic>> combined = {};

      for (var ext in installedList) {
        final String pkg = ext['pkg']?.toString() ?? '';
        if (pkg.isEmpty) continue;
        final String iconName = ext['icon']?.toString() ?? 'icon/$pkg.png';
        final String iconCdn = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/$iconName';
        final String apkName = ext['apk']?.toString() ?? '$pkg.apk';
        final String apkUrl = ext['apkUrl']?.toString() ?? 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/apk/$apkName';
        combined[pkg] = {
          'id': pkg,
          'name': ext['name'] ?? '',
          'pkgName': pkg,
          'versionName': ext['version'] ?? '',
          'isInstalled': true,
          'hasUpdate': ext['hasUpdate'] == true || ext['hasUpdate'] == 1,
          'lang': ext['lang'] ?? 'en',
          'nsfw': (ext['nsfw'] ?? 0) == 1,
          'apkUrl': apkUrl,
          'iconUrl': ext['iconUrl']?.toString() ?? iconCdn,
        };
      }

      for (var ext in listExts) {
        final String pkg = ext['pkg']?.toString() ?? '';
        if (pkg.isEmpty) continue;
        final String iconName = ext['icon']?.toString() ?? 'icon/$pkg.png';
        final String iconCdn = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/$iconName';
        final String apkName = ext['apk']?.toString() ?? '$pkg.apk';
        final String apkUrl = ext['apkUrl']?.toString() ?? 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/apk/$apkName';
        if (combined.containsKey(pkg)) {
          final instVer = combined[pkg]!['versionName']?.toString() ?? '';
          final availVer = ext['version']?.toString() ?? '';
          if (availVer.isNotEmpty && instVer.isNotEmpty && availVer != instVer) {
            combined[pkg]!['hasUpdate'] = true;
            combined[pkg]!['availableVersion'] = availVer;
          }
          combined[pkg]!['apkUrl'] = apkUrl;
          if (combined[pkg]!['iconUrl'] == null || combined[pkg]!['iconUrl'].toString().isEmpty) {
            combined[pkg]!['iconUrl'] = iconCdn;
          }
          continue;
        }
        combined[pkg] = {
          'id': pkg,
          'name': ext['name'] ?? '',
          'pkgName': pkg,
          'versionName': ext['version'] ?? '',
          'isInstalled': false,
          'hasUpdate': false,
          'lang': ext['lang'] ?? 'en',
          'nsfw': (ext['nsfw'] ?? 0) == 1,
          'apkUrl': apkUrl,
          'iconUrl': ext['iconUrl']?.toString() ?? iconCdn,
        };
      }


      if (combined.isNotEmpty) {
        return combined.values.toList();
      }

      // 4. Fallback: Keiyoushi GitHub Repository Index (Mihon-compatible)
      try {
        final repoResp = await http.get(Uri.parse('https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json')).timeout(const Duration(seconds: 15));
        if (repoResp.statusCode == 200) {
          final List repoList = (await _fastJsonDecode(repoResp.body)) as List;
          return repoList.map((ext) {
            final String pkg = ext['pkg']?.toString() ?? '';
            final String apk = ext['apk']?.toString() ?? '';
            final String iconName = ext['icon']?.toString() ?? 'icon/$pkg.png';
            final String iconCdn = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/$iconName';
            return {
              'id': pkg,
              'name': ext['name'] ?? '',
              'pkgName': pkg,
              'versionName': ext['version'] ?? '',
              'isInstalled': false,
              'hasUpdate': false,
              'lang': ext['lang'] ?? 'en',
              'nsfw': (ext['nsfw'] ?? 0) == 1,
              'apk': apk,
              'apkUrl': 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/apk/$apk',
              'iconUrl': iconCdn,
            };
          }).toList();
        }
      } catch (_) {}

      return [];
    } catch (e, stack) {
      developer.log('getExtensions Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return [];
    }
  }

  Future<bool> updateExtension(String pkgName, {String? extId}) async {
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
        await fetchExtensionsIndex();
        return true;
      }
    } catch (e) {
      developer.log('GraphQL updateExtension failed, falling back to install: $e', name: 'SuwayomiService');
    }
    final result = await installExtension(pkgName, extId: extId);
    if (result) {
      clearSourcesCache();
      await fetchExtensionsIndex();
    }
    return result;
  }


  Future<void> fetchExtensionsIndex() async {
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
    try {
      final id = extId ?? pkgName;

      // 1. On Android, install system-wide via native PackageInstaller Intent so both watchAny and Mihon see it
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final String downloadUrl = apkUrl ?? 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/apk/$pkgName.apk';
          final tempDir = await getTemporaryDirectory();
          final targetFile = File('${tempDir.path}/$pkgName.apk');

          final resp = await http.get(Uri.parse(downloadUrl)).timeout(const Duration(seconds: 60));
          if (resp.statusCode == 200) {
            await targetFile.writeAsBytes(resp.bodyBytes);
            const channel = MethodChannel('com.example.watch_any/native_path');
            final result = await channel.invokeMethod('installApk', {'filePath': targetFile.path});

            // Also inform local server to scan
            try {
              await http.get(Uri.parse('$_baseUrl/api/install?pkg=$pkgName')).timeout(const Duration(seconds: 5));
            } catch (_) {}

            changeNotifier.notifyListeners();
            return true;
          }
        } catch (e) {
          developer.log('Android native APK installer error: $e', name: 'SuwayomiService');
        }
      }

      // 2. Desktop (Windows/Mac/Linux) fallback to local server internal runtime
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/install?pkg=$pkgName'),
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded['ok'] == true) {
            changeNotifier.notifyListeners();
            return true;
          }
        }
      } catch (_) {}


      // 2. Try REST API v1 POST pkgName
      try {
        final v1Resp = await http.post(Uri.parse('$_baseUrl/api/v1/extension/install/$pkgName')).timeout(const Duration(seconds: 15));
        if (v1Resp.statusCode == 200) {
          changeNotifier.notifyListeners();
          return true;
        }
      } catch (_) {}

      // 3. Try GraphQL installExtension mutation by pkgName
      try {
        const gqlQuery = '''
          mutation InstallExt(\$pkgName: String!) {
            installExtension(input: { pkgName: \$pkgName }) {
              extension {
                pkgName
                isInstalled
              }
            }
          }
        ''';
        final data = await _postGraphQL(gqlQuery, {'pkgName': pkgName});
        if (data != null && data['installExtension'] != null) {
          changeNotifier.notifyListeners();
          return true;
        }
      } catch (e) {
        developer.log('GraphQL installExtension by pkgName failed: $e', name: 'SuwayomiService');
      }

      // 4. Android Native PackageInstaller Intent (Mihon method: download APK to cache & open PackageInstaller)
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final String downloadUrl = apkUrl ?? 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/apk/$pkgName.apk';
          final tempDir = await getTemporaryDirectory();
          final targetFile = File('${tempDir.path}/$pkgName.apk');

          final resp = await http.get(Uri.parse(downloadUrl)).timeout(const Duration(seconds: 60));
          if (resp.statusCode == 200) {
            await targetFile.writeAsBytes(resp.bodyBytes);
            const channel = MethodChannel('com.example.watch_any/native_path');
            final result = await channel.invokeMethod('installApk', {'filePath': targetFile.path});
            if (result == true) {
              changeNotifier.notifyListeners();
              return true;
            }
          }
        } catch (e) {
          developer.log('Android native APK installer error: $e', name: 'SuwayomiService');
        }
      }

      return false;
    } catch (e, stack) {
      developer.log('installExtension Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return false;
    }
  }



  Future<bool> uninstallExtension(String pkgName, {String? extId}) async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        try {
          const channel = MethodChannel('com.example.watch_any/native_path');
          await channel.invokeMethod('uninstallApk', {'pkgName': pkgName});
        } catch (e) {
          developer.log('Android uninstallApk channel error: $e', name: 'SuwayomiService');
        }
      }

      final id = extId ?? pkgName;


      // 1. Try GraphQL uninstallExtension mutation by pkgName
      try {
        const gqlQuery = '''
          mutation UninstallExt(\$pkgName: String!) {
            uninstallExtension(input: { pkgName: \$pkgName }) {
              extension {
                pkgName
                isInstalled
              }
            }
          }
        ''';
        final data = await _postGraphQL(gqlQuery, {'pkgName': pkgName});
        if (data != null && data['uninstallExtension'] != null) {
          changeNotifier.notifyListeners();
          return true;
        }
      } catch (e) {
        developer.log('GraphQL uninstallExtension by pkgName failed: $e', name: 'SuwayomiService');
      }

      // 2. Try GraphQL uninstallExtension mutation by id
      try {
        const gqlQuery = '''
          mutation UninstallExt(\$id: String!) {
            uninstallExtension(input: { id: \$id }) {
              extension {
                pkgName
                isInstalled
              }
            }
          }
        ''';
        final data = await _postGraphQL(gqlQuery, {'id': id});
        if (data != null && data['uninstallExtension'] != null) {
          changeNotifier.notifyListeners();
          return true;
        }
      } catch (e) {
        developer.log('GraphQL uninstallExtension by id failed: $e', name: 'SuwayomiService');
      }

      // 3. Try GraphQL updateExtension mutation with patch: { isInstalled: false }
      try {
        const gqlQuery = '''
          mutation UninstallExt(\$id: String!) {
            updateExtension(input: { id: \$id, patch: { isInstalled: false } }) {
              extension {
                pkgName
                isInstalled
              }
            }
          }
        ''';
        final data = await _postGraphQL(gqlQuery, {'id': id});
        if (data != null && data['updateExtension'] != null) {
          changeNotifier.notifyListeners();
          return true;
        }
      } catch (e) {
        developer.log('GraphQL updateExtension isInstalled false failed: $e', name: 'SuwayomiService');
      }

      // 4. Try REST HTTP DELETE
      try {
        final delResp = await http.delete(Uri.parse('$_baseUrl/api/v1/extension/pkg/$pkgName')).timeout(const Duration(seconds: 15));
        if (delResp.statusCode == 200) {
          changeNotifier.notifyListeners();
          return true;
        }
      } catch (_) {}

      // 5. Try REST HTTP POST uninstall
      try {
        final postResp = await http.post(Uri.parse('$_baseUrl/api/v1/extension/uninstall/$pkgName')).timeout(const Duration(seconds: 15));
        if (postResp.statusCode == 200) {
          changeNotifier.notifyListeners();
          return true;
        }
      } catch (_) {}

      // 6. Legacy REST API fallback
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/uninstall?pkg=$pkgName'),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded['ok'] == true || decoded['removed'] == true) {
            changeNotifier.notifyListeners();
            return true;
          }
        }
      } catch (_) {}

      // 7. Android fallback: open Android App Details settings page for package uninstallation
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final Uri uri = Uri.parse('package:$pkgName');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
            changeNotifier.notifyListeners();
            return true;
          }
        } catch (e) {
          developer.log('Android package details launch error: $e', name: 'SuwayomiService');
        }
      }

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
      // 1. Try local server GET /api/sources first (returns exact native sources with 64-bit IDs)
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
              }).toList();
              _cachedSources = mapped;
              return mapped;
            }
          }
        }
      } catch (e) {
        developer.log('GET /api/sources failed: $e', name: 'SuwayomiService');
      }

      // 2. Extract sources from installed extensions fallback
      try {
        final extensions = await getExtensions();
        final installedSources = <Map<String, dynamic>>[];
        for (var ext in extensions) {
          final sources = ext['sources'] as List? ?? [];
          if (sources.isNotEmpty) {
            for (var src in sources) {
              final String id = src['id']?.toString() ?? '';
              if (id.isEmpty) continue;
              installedSources.add({
                'id': id,
                'name': src['name'] ?? ext['name'] ?? '',
                'lang': src['lang'] ?? ext['lang'] ?? 'en',
                'isNsfw': ext['nsfw'] == true,
                'supportsLatest': src['supportsLatest'] ?? true,
                'pkg': ext['pkgName'] ?? ext['id'] ?? '',
              });
            }
          } else if (ext['isInstalled'] == true) {
            final String id = ext['id']?.toString() ?? ext['pkgName']?.toString() ?? '';
            if (id.isNotEmpty) {
              installedSources.add({
                'id': id,
                'name': ext['name'] ?? '',
                'lang': ext['lang'] ?? 'en',
                'isNsfw': ext['nsfw'] == true,
                'supportsLatest': true,
                'pkg': ext['pkgName'] ?? ext['id'] ?? '',
              });
            }
          }
        }

        if (installedSources.isNotEmpty) {
          _cachedSources = installedSources;
          return installedSources;
        }
      } catch (e) {
        developer.log('Extract sources from installed extensions failed: $e', name: 'SuwayomiService');
      }

      // 3. Try GraphQL sources query

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
          }).toList();
          if (mapped.isNotEmpty) {
            _cachedSources = mapped;
            return mapped;
          }
        }
      } catch (_) {}

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
      // 1. GraphQL fetchSourceManga — only for SEARCH (POPULAR/LATEST use v1 REST which has working thumbnail proxy)
      if (query.isNotEmpty) {
        try {
          final vars = <String, dynamic>{
            'source': sourceId,
            'type': 'SEARCH',
            'page': page,
            'query': query,
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
          developer.log('GraphQL fetchSourceManga failed: $e', name: 'SuwayomiService');
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

      final sourceId = pathInfo['sourceId']!;
      final mangaUrl = pathInfo['url']!;

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
