import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SuwayomiManager {
  static Process? _process;
  static int _port = 4567;
  static int get port => _port;
  static bool _isDownloading = false;
  static double _downloadProgress = 0.0;

  static bool get isDownloading => _isDownloading;
  static double get downloadProgress => _downloadProgress;

  static final ValueNotifier<String> statusNotifier = ValueNotifier<String>("Manga engine idle");

  static Future<bool> isSuwayomiRunning(int port) async {
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/health'),
      ).timeout(const Duration(milliseconds: 500));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['ok'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<int> _findAvailablePort(int startPort) async {
    int port = startPort;
    while (port < startPort + 100) {
      if (await isSuwayomiRunning(port)) {
        debugPrint('Manga engine is already running on port $port. Will reuse.');
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

  static Future<void> start() async {
    if (_process != null) {
      debugPrint('Manga engine already running or starting...');
      return;
    }
    try {
      statusNotifier.value = "Checking JRE...";
      
      // Smart Java Executable Path Resolver (bypasses system environment PATH cache delay)
      String javaPath = 'java';
      final defaultJdk21 = File('C:\\Program Files\\Eclipse Adoptium\\jdk-21.0.11.10-hotspot\\bin\\java.exe');
      if (await defaultJdk21.exists()) {
        javaPath = defaultJdk21.path;
        debugPrint('[SuwayomiManager] Located installed JDK 21 at: $javaPath');
      }

      // 1. Verify Java is installed
      bool javaInstalled = false;
      try {
        final checkResult = await Process.run(javaPath, ['-version']);
        if (checkResult.exitCode == 0 || checkResult.stderr.toString().contains('version')) {
          javaInstalled = true;
        }
      } catch (_) {}

      if (!javaInstalled) {
        statusNotifier.value = "Error: Java Runtime (JRE) is not installed.";
        throw Exception("Java Runtime (JRE) is required but was not found on your system PATH.");
      }

      // 2. Resolve port and repos from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedPort = prefs.getInt('manga_server_port') ?? 4567;
      _port = await _findAvailablePort(savedPort);
      final repos = prefs.getStringList('manga_repos') ?? <String>[];

      if (await isSuwayomiRunning(_port)) {
        statusNotifier.value = "Manga engine running";
        debugPrint('Reusing existing Manga engine instance on port $_port.');
        return;
      }

      final appDir = Directory('C:\\Users\\aryan\\AppData\\Local\\watch_any');
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      final runtimeDir = Directory('${appDir.path}\\keiyoushi');
      if (!await runtimeDir.exists()) {
        await runtimeDir.create(recursive: true);
      }

      // 3. Extract keiyoushi-runtime.jar from assets
      final jarPath = '${appDir.path}\\keiyoushi-runtime.jar';
      final jarFile = File(jarPath);

      if (!await jarFile.exists() || await jarFile.length() == 0) {
        statusNotifier.value = "Extracting Manga engine...";
        debugPrint('[SuwayomiManager] Extracting keiyoushi-runtime.jar from assets...');
        final byteData = await rootBundle.load('assets/bin/keiyoushi-runtime.jar');
        final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
        await jarFile.writeAsBytes(bytes);
        debugPrint('[SuwayomiManager] Extraction complete.');
      }

      // 4. Start the background process
      statusNotifier.value = "Starting Manga engine...";
      debugPrint('[SuwayomiManager] Launching keiyoushi-runtime on port $_port using: $javaPath');
      
      _process = await Process.start(
        javaPath,
        [
          '-jar',
          jarPath,
          '--root',
          runtimeDir.path,
          'web',
          '$_port',
        ],
        workingDirectory: appDir.path,
      );

      // Log process output for debugging
      _process!.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('[MangaEngine-stdout] $data');
      });
      _process!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('[MangaEngine-stderr] $data');
      });

      // Poll until the REST API responds
      bool serverReady = false;
      for (int i = 0; i < 40; i++) {
        if (await isSuwayomiRunning(_port)) {
          serverReady = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (serverReady) {
        statusNotifier.value = "Manga engine running";
        debugPrint('[SuwayomiManager] Manga engine is fully operational on port $_port.');
        
        // Seed default/configured repositories
        try {
          final reposUrl = Uri.parse('http://127.0.0.1:$_port/api/repos');
          final reposResponse = await http.get(reposUrl).timeout(const Duration(seconds: 3));
          if (reposResponse.statusCode == 200) {
            final data = jsonDecode(reposResponse.body);
            final list = data['data'] as List?;
            if (list == null || list.isEmpty) {
              debugPrint('[SuwayomiManager] Seeding repositories in custom runtime...');
              for (final repo in repos) {
                final addUrl = Uri.parse('http://127.0.0.1:$_port/api/repos/add?url=${Uri.encodeComponent(repo)}');
                await http.get(addUrl).timeout(const Duration(seconds: 10));
              }
            }
          }
        } catch (e) {
          debugPrint('[SuwayomiManager] Error seeding repositories: $e');
        }
      } else {
        statusNotifier.value = "Engine startup timeout";
        throw Exception("Timed out waiting for Manga engine to start.");
      }
    } catch (e) {
      debugPrint('[SuwayomiManager] Failed to start Manga engine: $e');
      statusNotifier.value = "Engine startup failed";
      _process = null;
      rethrow;
    }
  }

  static void stop() {
    if (_process != null) {
      debugPrint('[SuwayomiManager] Killing Manga engine process...');
      _process!.kill();
      _process = null;
      statusNotifier.value = "Manga engine stopped";
    }
  }
}
