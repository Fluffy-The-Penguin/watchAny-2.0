import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'suwayomi_manager.dart';

class SuwayomiService {
  static final SuwayomiService _instance = SuwayomiService._internal();
  factory SuwayomiService() => _instance;
  SuwayomiService._internal();

  String get _baseUrl => 'http://127.0.0.1:${SuwayomiManager.port}';

  Future<Map<String, dynamic>?> _postQuery(String query, {Map<String, dynamic>? variables}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/graphql'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'query': query,
          if (variables != null) 'variables': variables,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);
        if (decoded['errors'] != null) {
          debugPrint('[SuwayomiService] GraphQL Errors: ${decoded['errors']}');
        }
        return decoded['data'];
      }
      return null;
    } catch (e) {
      debugPrint('[SuwayomiService] HTTP Post Query Error: $e');
      return null;
    }
  }

  // Fetch all extensions (installed and available in repositories)
  Future<List<dynamic>> getExtensions() async {
    const query = r'''
      query GetExtensions {
        extensions {
          name
          pkgName
          versionName
          isInstalled
          lang
          nsfw
        }
      }
    ''';
    final data = await _postQuery(query);
    if (data != null && data['extensions'] != null) {
      return data['extensions'] as List;
    }
    // Fallback query if 'extensions' directly doesn't work
    const fallbackQuery = r'''
      query GetExtensionsFallback {
        fetchExtensions {
          extensions {
            name
            pkgName
            versionName
            isInstalled
            lang
            nsfw
          }
        }
      }
    ''';
    final fallbackData = await _postQuery(fallbackQuery);
    if (fallbackData != null && fallbackData['fetchExtensions']?['extensions'] != null) {
      return fallbackData['fetchExtensions']['extensions'] as List;
    }
    return [];
  }

  // Install extension
  Future<bool> installExtension(String pkgName) async {
    const mutation = r'''
      mutation InstallExtension($pkgName: String!) {
        installExtension(pkgName: $pkgName) {
          pkgName
        }
      }
    ''';
    final data = await _postQuery(mutation, variables: {'pkgName': pkgName});
    return data != null;
  }

  // Uninstall extension
  Future<bool> uninstallExtension(String pkgName) async {
    const mutation = r'''
      mutation UninstallExtension($pkgName: String!) {
        uninstallExtension(pkgName: $pkgName) {
          pkgName
        }
      }
    ''';
    final data = await _postQuery(mutation, variables: {'pkgName': pkgName});
    return data != null;
  }

  // Fetch active manga sources
  Future<List<dynamic>> getSources() async {
    const query = r'''
      query GetSources {
        sources {
          id
          name
          lang
          isNsfw
          supportsLatest
        }
      }
    ''';
    final data = await _postQuery(query);
    if (data != null && data['sources'] != null) {
      return data['sources'] as List;
    }
    return [];
  }

  // Search or browse catalog from a source
  Future<List<dynamic>> fetchSourceManga({
    required String sourceId,
    required int page,
    String query = "",
  }) async {
    // If query is empty, we perform browse popular / latest
    const q = r'''
      query FetchSourceManga($query: String!, $sourceId: String!, $page: Int!) {
        fetchSourceManga(query: $query, source: $sourceId, page: $page) {
          manga {
            id
            title
            thumbnailUrl
          }
        }
      }
    ''';
    
    final variables = {
      'query': query,
      'sourceId': sourceId,
      'page': page,
    };

    final data = await _postQuery(q, variables: variables);
    if (data != null && data['fetchSourceManga']?['manga'] != null) {
      return data['fetchSourceManga']['manga'] as List;
    }
    return [];
  }

  // Fetch manga details
  Future<Map<String, dynamic>?> getMangaDetails(int id) async {
    const query = r'''
      query GetMangaDetails($id: Int!) {
        manga(id: $id) {
          id
          title
          author
          description
          genre
          status
          thumbnailUrl
          sourceId
        }
      }
    ''';
    final data = await _postQuery(query, variables: {'id': id});
    if (data != null && data['manga'] != null) {
      return data['manga'] as Map<String, dynamic>;
    }
    return null;
  }

  // Fetch chapters list
  Future<List<dynamic>> getChapters(int mangaId) async {
    const query = r'''
      query GetChapters($mangaId: Int!) {
        chapters(mangaId: $mangaId) {
          id
          name
          chapterNumber
          uploadDate
          read
        }
      }
    ''';
    final data = await _postQuery(query, variables: {'mangaId': mangaId});
    if (data != null && data['chapters'] != null) {
      return data['chapters'] as List;
    }
    // Fallback query if 'chapters' directly doesn't work
    const fallbackQuery = r'''
      query GetChaptersFallback($mangaId: Int!) {
        fetchChapters(mangaId: $mangaId) {
          chapters {
            id
            name
            chapterNumber
            uploadDate
            read
          }
        }
      }
    ''';
    final fallbackData = await _postQuery(fallbackQuery, variables: {'mangaId': mangaId});
    if (fallbackData != null && fallbackData['fetchChapters']?['chapters'] != null) {
      return fallbackData['fetchChapters']['chapters'] as List;
    }
    return [];
  }

  // Fetch pages list for reading
  Future<List<String>> getChapterPages(int chapterId) async {
    const query = r'''
      query GetChapterPages($chapterId: Int!) {
        fetchChapterPages(chapterId: $chapterId) {
          pages
        }
      }
    ''';
    final data = await _postQuery(query, variables: {'chapterId': chapterId});
    if (data != null && data['fetchChapterPages']?['pages'] != null) {
      final pages = data['fetchChapterPages']['pages'] as List;
      // Prepend base URL to relative pages if needed
      return pages.map((p) {
        final String pageUrl = p.toString();
        if (pageUrl.startsWith('http')) {
          return pageUrl;
        }
        return '$_baseUrl$pageUrl';
      }).toList();
    }
    return [];
  }
}
