import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
        Uri.parse('http://127.0.0.1:$port/api/v1/info'),
      ).timeout(const Duration(milliseconds: 500));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<int> _findAvailablePort(int startPort) async {
    int port = startPort;
    while (port < startPort + 100) {
      if (await isSuwayomiRunning(port)) {
        debugPrint('Suwayomi is already running on port $port. Will reuse.');
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
      debugPrint('Suwayomi already running or starting...');
      return;
    }
    try {
      statusNotifier.value = "Checking JRE...";
      // 1. Verify Java is installed
      bool javaInstalled = false;
      try {
        final checkResult = await Process.run('java', ['-version']);
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
      final repos = prefs.getStringList('manga_repos') ?? ["https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json"];

      if (await isSuwayomiRunning(_port)) {
        statusNotifier.value = "Manga engine running";
        debugPrint('Reusing existing Suwayomi instance on port $_port.');
        return;
      }

      final appDir = Directory('C:\\Users\\aryan\\AppData\\Local\\watch_any');
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      final suwayomiDir = Directory('${appDir.path}\\suwayomi');
      if (!await suwayomiDir.exists()) {
        await suwayomiDir.create(recursive: true);
      }

      // 3. Write server.conf HOCON config file
      final configFile = File('${suwayomiDir.path}\\server.conf');
      final reposHocon = repos.map((url) => '"$url"').join(', ');
      final configContent = '''
server.port = $_port
server.extensionRepos = [$reposHocon]
''';
      await configFile.writeAsString(configContent);

      // 4. Check/Download jar
      final jarPath = '${appDir.path}\\Suwayomi-Server.jar';
      final jarFile = File(jarPath);

      if (!await jarFile.exists() || await jarFile.length() == 0) {
        _isDownloading = true;
        statusNotifier.value = "Checking release version...";
        
        String downloadUrl = 'https://github.com/Suwayomi/Suwayomi-Server/releases/download/v2.2.2100/Suwayomi-Server-v2.2.2100.jar';
        try {
          final releaseResponse = await http.get(
            Uri.parse('https://api.github.com/repos/Suwayomi/Suwayomi-Server/releases/latest'),
            headers: {'User-Agent': 'watchAny-App'},
          ).timeout(const Duration(seconds: 5));
          
          if (releaseResponse.statusCode == 200) {
            final Map<String, dynamic> releaseData = jsonDecode(releaseResponse.body);
            final List<dynamic> assets = releaseData['assets'] ?? [];
            final jarAsset = assets.firstWhere(
              (asset) => asset['name'].toString().endsWith('.jar'),
              orElse: () => null,
            );
            if (jarAsset != null && jarAsset['browser_download_url'] != null) {
              downloadUrl = jarAsset['browser_download_url'];
              debugPrint('[SuwayomiManager] Found latest release jar: $downloadUrl');
            }
          }
        } catch (e) {
          debugPrint('[SuwayomiManager] Error fetching latest release metadata (using fallback): $e');
        }

        statusNotifier.value = "Downloading Manga engine...";
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(downloadUrl));
        final response = await client.send(request);
        
        if (response.statusCode != 200) {
          _isDownloading = false;
          statusNotifier.value = "Download failed!";
          throw Exception("Failed to download Suwayomi-Server.jar: HTTP ${response.statusCode}");
        }

        final int totalBytes = response.contentLength ?? 170000000;
        int receivedBytes = 0;
        final List<int> bytes = [];

        await response.stream.forEach((chunk) {
          bytes.addAll(chunk);
          receivedBytes += chunk.length;
          _downloadProgress = receivedBytes / totalBytes;
          statusNotifier.value = "Downloading Manga engine: ${(_downloadProgress * 100).toStringAsFixed(0)}%";
        });

        await jarFile.writeAsBytes(bytes);
        _isDownloading = false;
      }

      // 5. Start the background process
      statusNotifier.value = "Starting Manga engine...";
      debugPrint('[SuwayomiManager] Launching Suwayomi-Server on port $_port...');
      
      _process = await Process.start(
        'java',
        [
          '-Dsuwayomi.tachidesk.config.server.port=$_port',
          '-Dsuwayomi.tachidesk.config.server.rootDir=${suwayomiDir.path}',
          '-jar',
          jarPath,
        ],
        workingDirectory: appDir.path,
      );

      // Log process output for debugging
      _process!.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('[Suwayomi-stdout] $data');
      });
      _process!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('[Suwayomi-stderr] $data');
      });

      // Poll until the REST API responds
      int attempts = 0;
      while (attempts < 60) {
        if (await isSuwayomiRunning(_port)) {
          debugPrint('[SuwayomiManager] Suwayomi-Server is fully operational.');
          statusNotifier.value = "Manga engine running";
          return;
        }
        await Future.delayed(const Duration(seconds: 1));
        attempts++;
      }

      statusNotifier.value = "Engine startup timeout";
      throw Exception("Timed out waiting for Suwayomi-Server to start.");
    } catch (e) {
      debugPrint('[SuwayomiManager] Failed to start Suwayomi-Server: $e');
      statusNotifier.value = "Engine startup failed";
      _process = null;
      rethrow;
    }
  }

  static void stop() {
    if (_process != null) {
      debugPrint('[SuwayomiManager] Killing Suwayomi-Server process...');
      _process!.kill();
      _process = null;
      statusNotifier.value = "Manga engine stopped";
    }
  }
}
