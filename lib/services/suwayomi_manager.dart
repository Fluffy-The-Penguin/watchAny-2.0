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
      
      final appDir = Directory('C:\\Users\\aryan\\AppData\\Local\\watch_any');
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      final localJreDir = Directory('${appDir.path}\\jre');
      final localJavaExe = File('${localJreDir.path}\\bin\\java.exe');
      
      String javaPath = 'java';
      bool javaInstalled = false;

      if (await localJavaExe.exists()) {
        javaPath = localJavaExe.path;
        javaInstalled = true;
        debugPrint('[SuwayomiManager] Located local JRE at: $javaPath');
      } else {
        // Smart Java Executable Path Resolver (bypasses system environment PATH cache delay)
        final defaultJdk21 = File('C:\\Program Files\\Eclipse Adoptium\\jdk-21.0.11.10-hotspot\\bin\\java.exe');
        if (await defaultJdk21.exists()) {
          javaPath = defaultJdk21.path;
          javaInstalled = true;
          debugPrint('[SuwayomiManager] Located installed JDK 21 at: $javaPath');
        } else {
          // Check system java
          try {
            final checkResult = await Process.run('java', ['-version']);
            if (checkResult.exitCode == 0 || checkResult.stderr.toString().contains('version')) {
              javaPath = 'java';
              javaInstalled = true;
              debugPrint('[SuwayomiManager] Located system JRE in PATH.');
            }
          } catch (_) {}
        }

        if (!javaInstalled) {
          // System Java not found. Let's download a minimal JRE automatically!
          statusNotifier.value = "Downloading JRE (Manga Runtime)...";
          debugPrint('[SuwayomiManager] System JRE not found. Initiating Adoptium JRE 21 download...');
          
          final jreZipPath = '${appDir.path}\\jre.zip';
          final jreZipFile = File(jreZipPath);
          
          // Download URL for a minimal, official OpenJDK JRE 21 for Windows x64
          final jreUrl = 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.2%2B13/OpenJDK21U-jre_x64_windows_hotspot_21.0.2_13.zip';
          
          // Download the file
          final response = await http.get(Uri.parse(jreUrl));
          if (response.statusCode == 200) {
            await jreZipFile.writeAsBytes(response.bodyBytes);
            debugPrint('[SuwayomiManager] JRE zip downloaded successfully.');
          } else {
            statusNotifier.value = "Error: Failed to download JRE.";
            throw Exception("Failed to download JRE from Adoptium (Status: ${response.statusCode}).");
          }

          // Unzip the file using PowerShell
          statusNotifier.value = "Extracting JRE (Manga Runtime)...";
          debugPrint('[SuwayomiManager] Extracting JRE archive using PowerShell...');
          final tempExtractDir = Directory('${appDir.path}\\jre_temp');
          if (await tempExtractDir.exists()) {
            await tempExtractDir.delete(recursive: true);
          }
          await tempExtractDir.create();

          // Run expand archive
          final extractResult = await Process.run('powershell', [
            '-Command',
            'Expand-Archive -Path "$jreZipPath" -DestinationPath "${tempExtractDir.path}" -Force'
          ]);

          if (extractResult.exitCode != 0) {
            debugPrint('[SuwayomiManager] Extraction failed: ${extractResult.stderr}');
            statusNotifier.value = "Error: Extraction failed.";
            throw Exception("Failed to extract JRE archive.");
          }

          // Clean up zip
          await jreZipFile.delete();

          // Move the extracted folder contents to localJreDir
          final extractedSubDirs = tempExtractDir.listSync();
          if (extractedSubDirs.isNotEmpty && extractedSubDirs.first is Directory) {
            final extractedJreDir = extractedSubDirs.first as Directory;
            if (await localJreDir.exists()) {
              await localJreDir.delete(recursive: true);
            }
            await extractedJreDir.rename(localJreDir.path);
            debugPrint('[SuwayomiManager] JRE placed at ${localJreDir.path}');
          } else {
            statusNotifier.value = "Error: Empty JRE archive.";
            throw Exception("Extracted JRE directory was empty.");
          }
          
          // Clean up temp directory
          await tempExtractDir.delete(recursive: true);

          if (await localJavaExe.exists()) {
            javaPath = localJavaExe.path;
            debugPrint('[SuwayomiManager] Local JRE successfully initialized at: $javaPath');
          } else {
            statusNotifier.value = "Error: Failed to verify JRE installation.";
            throw Exception("Failed to verify local JRE executable path.");
          }
        }
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
