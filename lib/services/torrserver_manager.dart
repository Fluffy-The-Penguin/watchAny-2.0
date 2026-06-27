import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TorrServerManager {
  static Process? _process;

  static Future<void> start() async {
    if (_process != null) {
      debugPrint('TorrServer already running or starting...');
      return;
    }
    try {
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
      debugPrint('Launching TorrServer process with DB path: ${appDir.path}...');
      _process = await Process.start(exePath, ['-d', appDir.path]);
      
      // Log stdout and stderr
      _process!.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('[TorrServer STDOUT] $data');
      });
      _process!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('[TorrServer STDERR] $data');
      });

      debugPrint('TorrServer started successfully!');
      _applySettings();
    } catch (e) {
      debugPrint('Error starting TorrServer: $e');
    }
  }

  static Future<void> _applySettings() async {
    final String url = 'http://127.0.0.1:8090';
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        final response = await http.get(Uri.parse('$url/echo')).timeout(const Duration(seconds: 1));
        if (response.statusCode == 200) {
          debugPrint('TorrServer is online, applying fast cache/prebuffer settings...');
          final setResponse = await http.post(
            Uri.parse('$url/settings'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'set',
              'sets': {
                'CacheSize': 52428800,      // 50 MB Cache
                'PrebufferSize': 8388608,    // 8 MB Prebuffer
              }
            }),
          ).timeout(const Duration(seconds: 2));
          debugPrint('TorrServer settings response: ${setResponse.statusCode} - ${setResponse.body}');
          break;
        }
      } catch (_) {}
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
