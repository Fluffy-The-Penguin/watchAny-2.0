import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';

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
