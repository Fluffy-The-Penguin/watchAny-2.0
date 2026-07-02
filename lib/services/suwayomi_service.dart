import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SuwayomiService {
  static final SuwayomiService _instance = SuwayomiService._internal();
  factory SuwayomiService() => _instance;
  SuwayomiService._internal();

  static String host = '127.0.0.1';
  static int port = 4567;

  String get _baseUrl => 'http://$host:$port';

  int _generateHash(String input) {
    return input.hashCode.abs();
  }

  Future<void> registerMangaPath(int hash, String sourceId, String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manga_path_$hash', '$sourceId:$url');
  }

  Future<Map<String, String>?> getMangaPath(int hash) async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString('manga_path_$hash');
    if (val == null) return null;
    final parts = val.split(':');
    if (parts.length < 2) return null;
    final sourceId = parts[0];
    final url = parts.sublist(1).join(':');
    return {'sourceId': sourceId, 'url': url};
  }

  Future<void> registerChapterPath(int hash, String sourceId, String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chapter_path_$hash', '$sourceId:$url');
  }

  Future<Map<String, String>?> getChapterPath(int hash) async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString('chapter_path_$hash');
    if (val == null) return null;
    final parts = val.split(':');
    if (parts.length < 2) return null;
    final sourceId = parts[0];
    final url = parts.sublist(1).join(':');
    return {'sourceId': sourceId, 'url': url};
  }

  // Fetch all extensions (installed and available in repositories)
  Future<List<dynamic>> getExtensions() async {
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('$_baseUrl/api/installed')).timeout(const Duration(seconds: 20)),
        http.get(Uri.parse('$_baseUrl/api/list')).timeout(const Duration(seconds: 20)),
      ]).catchError((e) {
        throw Exception('Network request failed: $e');
      });
      final instResp = responses[0];
      final listResp = responses[1];

      if (instResp.statusCode != 200 || listResp.statusCode != 200) {
        throw Exception('Server error: installed_status=${instResp.statusCode}, list_status=${listResp.statusCode}');
      }

      dynamic installedData;
      dynamic listData;
      try {
        installedData = jsonDecode(instResp.body);
        listData = jsonDecode(listResp.body);
      } catch (e) {
        throw Exception('Failed to parse server response JSON: $e');
      }

      final installedList = installedData['data'] as List? ?? [];
      final listExts = listData['data'] as List? ?? [];

      final Map<String, Map<String, dynamic>> combined = {};

      for (var ext in installedList) {
        final String pkg = ext['pkg']?.toString() ?? '';
        if (pkg.isEmpty) continue;
        combined[pkg] = {
          'name': ext['name'] ?? '',
          'pkgName': pkg,
          'versionName': ext['version'] ?? '',
          'isInstalled': true,
          'lang': ext['lang'] ?? 'en',
          'nsfw': (ext['nsfw'] ?? 0) == 1,
        };
      }

      for (var ext in listExts) {
        final String pkg = ext['pkg']?.toString() ?? '';
        if (pkg.isEmpty) continue;
        if (combined.containsKey(pkg)) continue;
        combined[pkg] = {
          'name': ext['name'] ?? '',
          'pkgName': pkg,
          'versionName': ext['version'] ?? '',
          'isInstalled': false,
          'lang': ext['lang'] ?? 'en',
          'nsfw': (ext['nsfw'] ?? 0) == 1,
        };
      }

      return combined.values.toList();
    } catch (e, stack) {
      developer.log('getExtensions Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // Install extension
  Future<bool> installExtension(String pkgName) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/install?pkg=$pkgName'),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['ok'] == true;
      }
      return false;
    } catch (e, stack) {
      developer.log('installExtension Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return false;
    }
  }

  // Uninstall extension
  Future<bool> uninstallExtension(String pkgName) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/uninstall?pkg=$pkgName'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['ok'] == true;
      }
      return false;
    } catch (e, stack) {
      developer.log('uninstallExtension Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return false;
    }
  }

  // Seed default Keiyoushi repository on the server if the repository list is empty
  Future<void> seedExternalRepositories() async {
    try {
      final reposUrl = Uri.parse('$_baseUrl/api/repos');
      final reposResponse = await http.get(reposUrl).timeout(const Duration(seconds: 5));
      if (reposResponse.statusCode == 200) {
        final data = jsonDecode(reposResponse.body);
        final list = data['data'] as List?;
        if (list == null || list.isEmpty) {
          developer.log('Seeding Keiyoushi repository on server...', name: 'SuwayomiService');
          final repoUrl = "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json";
          final addUrl = Uri.parse('$_baseUrl/api/repos/add?url=${Uri.encodeComponent(repoUrl)}');
          await http.get(addUrl).timeout(const Duration(seconds: 15));
          developer.log('Seeding complete.', name: 'SuwayomiService');
          // Give the server 1.5 seconds to pull/sync the index in the background
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }
    } catch (e, stack) {
      developer.log('Error seeding external repositories', name: 'SuwayomiService', error: e, stackTrace: stack);
    }
  }

  // Fetch active manga sources
  Future<List<dynamic>> getSources() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/sources'),
      ).timeout(const Duration(seconds: 10)).catchError((e) {
        throw Exception('Network request failed: $e');
      });

      if (response.statusCode != 200) {
        throw Exception('Server error: status_code=${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded['ok'] == true) {
        final list = decoded['data'] as List? ?? [];
        return list.map((source) => {
          'id': source['id']?.toString() ?? '',
          'name': source['name'] ?? '',
          'lang': source['lang'] ?? 'en',
          'isNsfw': false,
          'supportsLatest': source['supportsLatest'] ?? true,
        }).toList();
      }
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
      final urlStr = query.isNotEmpty
          ? '$_baseUrl/api/search?sourceId=$sourceId&page=$page&q=${Uri.encodeComponent(query)}'
          : latest
              ? '$_baseUrl/api/latest?sourceId=$sourceId&page=$page'
              : '$_baseUrl/api/popular?sourceId=$sourceId&page=$page';

      final response = await http.get(Uri.parse(urlStr)).timeout(const Duration(seconds: 20)).catchError((e) {
        throw Exception('Network request failed: $e');
      });

      if (response.statusCode != 200) {
        throw Exception('Server error: status_code=${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded['ok'] == true && decoded['data']?['mangas'] != null) {
        final list = decoded['data']['mangas'] as List;
        final mapped = <dynamic>[];

        for (var manga in list) {
          final String url = manga['url'] ?? '';
          if (url.isEmpty) continue;

          final int hash = _generateHash('$sourceId:$url');
          await registerMangaPath(hash, sourceId, url);

          final coverUrl = manga['thumbnailUrl']?.toString() ?? '';
          final proxiedCover = coverUrl.isNotEmpty
              ? '$_baseUrl/api/image?url=${Uri.encodeComponent(coverUrl)}'
              : '';

          mapped.add({
            'id': hash,
            'title': manga['title'] ?? 'Unknown Manga',
            'thumbnailUrl': proxiedCover,
            'url': url,
          });
        }
        return mapped;
      }
      return [];
    } catch (e, stack) {
      developer.log('fetchSourceManga Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // Fetch manga details
  Future<Map<String, dynamic>?> getMangaDetails(int id) async {
    try {
      final pathInfo = await getMangaPath(id);
      if (pathInfo == null) return null;

      final sourceId = pathInfo['sourceId']!;
      final mangaUrl = pathInfo['url']!;

      final response = await http.get(
        Uri.parse('$_baseUrl/api/details?sourceId=$sourceId&url=${Uri.encodeComponent(mangaUrl)}'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
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
      final pathInfo = await getMangaPath(mangaId);
      if (pathInfo == null) return [];

      final sourceId = pathInfo['sourceId']!;
      final mangaUrl = pathInfo['url']!;

      final response = await http.get(
        Uri.parse('$_baseUrl/api/chapters?sourceId=$sourceId&url=${Uri.encodeComponent(mangaUrl)}'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['ok'] == true && decoded['data']?['chapters'] != null) {
          final list = decoded['data']['chapters'] as List;
          final mapped = <dynamic>[];

          for (var chapter in list) {
            final String url = chapter['url'] ?? '';
            if (url.isEmpty) continue;

            final int hash = _generateHash('$sourceId:$url');
            await registerChapterPath(hash, sourceId, url);

            mapped.add({
              'id': hash,
              'name': chapter['name'] ?? 'Chapter',
              'chapterNumber': chapter['chapterNumber'] ?? 1.0,
              'uploadDate': chapter['dateUpload'] ?? 0,
              'read': false,
            });
          }
          return mapped;
        }
      }
      return [];
    } catch (e, stack) {
      developer.log('getChapters Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return [];
    }
  }

  // Fetch pages list for reading
  Future<List<String>> getChapterPages(int chapterId) async {
    try {
      final pathInfo = await getChapterPath(chapterId);
      if (pathInfo == null) return [];

      final sourceId = pathInfo['sourceId']!;
      final chapterUrl = pathInfo['url']!;

      final response = await http.get(
        Uri.parse('$_baseUrl/api/pages?sourceId=$sourceId&url=${Uri.encodeComponent(chapterUrl)}'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['ok'] == true && decoded['data']?['pages'] != null) {
          final list = decoded['data']['pages'] as List;
          final pages = <String>[];

          for (var page in list) {
            final String pageUrl = page['imageUrl'] ?? page['url'] ?? '';
            if (pageUrl.isEmpty) continue;

            pages.add('$_baseUrl/api/image?url=${Uri.encodeComponent(pageUrl)}');
          }
          return pages;
        }
      }
      return [];
    } catch (e, stack) {
      developer.log('getChapterPages Error', name: 'SuwayomiService', error: e, stackTrace: stack);
      return [];
    }
  }
}
