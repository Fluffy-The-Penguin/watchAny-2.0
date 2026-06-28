import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/torrent.dart';
import '../state/app_settings.dart';

class TorrServerService {
  String? _customBaseUrl;

  TorrServerService({String? baseUrl}) : _customBaseUrl = baseUrl;

  String get baseUrl {
    final url = _customBaseUrl ?? AppSettings().torrServerUrl;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  set baseUrl(String url) {
    _customBaseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Checks if TorrServer is reachable.
  Future<bool> ping() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/echo'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Adds a torrent (magnet or .torrent URL), then polls until file metadata arrives.
  Future<TorrentInfo> addTorrent(String link, {String title = ''}) async {
    final uri = Uri.parse('$baseUrl/torrents');
    final body = jsonEncode({
      'action': 'add',
      'link': link,
      'title': title,
      'poster': '',
      'data': '',
      'save_to_db': false,
    });

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Failed to add torrent: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final hash = json['hash'] as String? ?? '';
    if (hash.isEmpty) {
      throw Exception('TorrServer returned no hash. Response: $json');
    }

    // Poll until file metadata is populated (TorrServer fetches metadata async)
    return _waitForFiles(hash);
  }

  /// Polls getTorrent every second until files appear or timeout (30s).
  Future<TorrentInfo> _waitForFiles(String hash, {int maxAttempts = 30}) async {
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        final info = await getTorrent(hash);
        // stat 2 = metadata ready, files should be populated
        if (info.files.isNotEmpty) return info;
      } catch (e) {
        debugPrint('Poll #$i error: $e');
      }
    }
    // Return whatever we have after timeout
    return getTorrent(hash);
  }

  /// Fetches updated torrent info (including file list and status).
  Future<TorrentInfo> getTorrent(String hash) async {
    final uri = Uri.parse('$baseUrl/torrents');
    final body = jsonEncode({'action': 'get', 'hash': hash});

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return TorrentInfo.fromJson(json);
    }
    throw Exception('Failed to get torrent: ${response.statusCode}');
  }

  /// Removes a torrent from TorrServer.
  Future<void> removeTorrent(String hash) async {
    try {
      final uri = Uri.parse('$baseUrl/torrents');
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'rem', 'hash': hash}),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Error removing torrent: $e');
    }
  }

  /// Constructs the direct HTTP stream URL for a given file index.
  /// NOTE: TorrServer uses 1-based file indexing in the stream URL.
  String getStreamUrl(String hash, int fileIndex) {
    return '$baseUrl/stream?link=$hash&index=${fileIndex + 1}&play';
  }

  /// Triggers a prebuffer/preload for a specific file index in the torrent.
  Future<void> preloadTorrentFile(String hash, int fileIndex) async {
    try {
      final uri = Uri.parse('$baseUrl/stream?link=$hash&index=${fileIndex + 1}&preload');
      final client = http.Client();
      final request = http.Request('GET', uri);
      
      client.send(request).then((response) {
        // Actively listen and discard bytes to prevent the TCP buffer from filling up,
        // which keeps TorrServer downloading at maximum speed.
        response.stream.listen(
          (chunk) {
            // Discard bytes
          },
          onDone: () => client.close(),
          onError: (_) => client.close(),
          cancelOnError: true,
        );
      }).catchError((_) {
        client.close();
      });
    } catch (_) {
      // Ignore
    }
  }
}
