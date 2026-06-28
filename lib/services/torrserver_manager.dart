import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../state/app_settings.dart';

class TorrServerManager {
  static Process? _process;
  static int _port = 8090;
  static int get port => _port;

  static Future<bool> _isTorrServerRunning(int port) async {
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/echo'),
      ).timeout(const Duration(milliseconds: 300));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<int> _findAvailablePort(int startPort) async {
    int port = startPort;
    while (port < startPort + 100) {
      if (await _isTorrServerRunning(port)) {
        debugPrint('TorrServer is already running on port $port. Will reuse.');
        return port;
      }
      try {
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await socket.close();
        return port;
      } catch (_) {
        port++;
      }
    }
    return startPort;
  }

  static Future<void> _applySettings(int port) async {
    // Delay slightly to give the server a moment to initialize if newly started
    Future.delayed(const Duration(seconds: 1), () async {
      try {
        final settingsUrl = 'http://127.0.0.1:$port/settings';
        await http.post(
          Uri.parse(settingsUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'set',
            'sets': {
              'CacheSize': 209715200,          // 200MB Cache for smooth buffering
              'Preload': 10,                   // 10% of CacheSize = 20MB Preload (super fast start!)
              'ReaderReadAhead': 90,           // 90% Read ahead
              'TorrentDisconnectTimeout': 30,  // Recycle stale connections quickly
              'PeersLifeTime': 30,
              'MaxPeers': 200,
              'PendingPeers': 20,
              'Aportlimit': true
            }
          }),
        ).timeout(const Duration(seconds: 3));
        debugPrint('[TorrServerManager] Optimal streaming settings applied successfully.');
      } catch (e) {
        debugPrint('[TorrServerManager] Failed to apply streaming settings: $e');
      }
    });
  }

  static Future<void> start() async {
    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (!isDesktop) {
      debugPrint('TorrServerManager start skipped on non-desktop platform.');
      return;
    }
    if (_process != null) {
      debugPrint('TorrServer already running or starting...');
      return;
    }
    try {
      _port = await _findAvailablePort(8090);
      AppSettings().updateLocalTorrServerPort(_port);

      if (await _isTorrServerRunning(_port)) {
        debugPrint('Reusing existing TorrServer instance on port $_port.');
        _applySettings(_port);
        return;
      }

      final appDir = Directory('C:\\Users\\aryan\\AppData\\Local\\watch_any');
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      final exePath = '${appDir.path}\\torrserver.exe';
      final file = File(exePath);

      // Copy from assets to local file if not exists or if size is 0
      if (!await file.exists() || await file.length() == 0) {
        debugPrint('Extracting TorrServer binary to AppData...');
        final byteData = await rootBundle.load('assets/bin/torrserver.exe');
        final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
        await file.writeAsBytes(bytes);
        debugPrint('Extraction complete.');
      }

      // Start the process
      debugPrint('Launching TorrServer process on port $_port with DB path: ${appDir.path}...');
      _process = await Process.start(exePath, ['-p', '$_port', '-d', appDir.path]);
      
      // Log stdout and stderr
      _process!.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('[TorrServer STDOUT] $data');
      });
      _process!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('[TorrServer STDERR] $data');
      });

      debugPrint('TorrServer started successfully!');
      _applySettings(_port);
    } catch (e) {
      debugPrint('Error starting TorrServer: $e');
    }
  }

  static Future<void> stop() async {
    if (_process != null) {
      debugPrint('Terminating TorrServer process...');
      _process!.kill();
      _process = null;
    }
  }
}
