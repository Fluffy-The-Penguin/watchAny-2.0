import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'suwayomi_service.dart';

class SuwayomiManager {
  static Process? _process;
  static Future<void>? _startFuture;
  static int _port = 4567;
  static int get port => _port;
  static bool _isDownloading = false;
  static double _downloadProgress = 0.0;
  static final List<String> processLogs = [];

  static bool get isDownloading => _isDownloading;
  static double get downloadProgress => _downloadProgress;

  static final ValueNotifier<String> statusNotifier = ValueNotifier<String>("Manga engine idle");

  static const String suwayomiServerVersion = 'v2.3.2243';
  static const String suwayomiJarDownloadUrl =
      'https://github.com/Suwayomi/Suwayomi-Server/releases/download/v2.3.2243/Suwayomi-Server-v2.3.2243.jar';

  static Future<bool> isSuwayomiRunning(int port) async {
    try {
      final response = await http.get(
        Uri.parse('http://${SuwayomiService.host}:$port/api/health'),
      ).timeout(const Duration(seconds: 1));
      if (response.statusCode == 200) {
        return true;
      }
    } catch (_) {}

    try {
      final gqlResponse = await http.post(
        Uri.parse('http://${SuwayomiService.host}:$port/api/graphql'),
        headers: {'Content-Type': 'application/json'},
        body: '{"query":"query { __typename }"}',
      ).timeout(const Duration(seconds: 1));
      if (gqlResponse.statusCode == 200) {
        return true;
      }
    } catch (_) {}

    return false;
  }


  static Future<int> _findAvailablePort(int startPort) async {
    int port = startPort;
    while (port < startPort + 100) {
      if (await isSuwayomiRunning(port)) {
        developer.log('Manga engine is already running on port $port. Will reuse.', name: 'SuwayomiManager');
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

  static Future<bool> ensureRunning({int maxWaitSeconds = 45}) async {
    if (await isSuwayomiRunning(_port)) {
      statusNotifier.value = "Manga engine running";
      return true;
    }
    // Trigger start if not already started
    start();

    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed.inSeconds < maxWaitSeconds) {
      if (await isSuwayomiRunning(_port)) {
        statusNotifier.value = "Manga engine running";
        return true;
      }
      final remaining = maxWaitSeconds - stopwatch.elapsed.inSeconds;
      statusNotifier.value = "Starting Manga Engine (waiting ${remaining}s)...";
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return await isSuwayomiRunning(_port);
  }

  static Future<void> start() async {
    if (_process != null) return;
    if (_startFuture != null) {
      developer.log('Manga engine startup is already in progress. Awaiting existing startup...', name: 'SuwayomiManager');
      return _startFuture!;
    }

    _startFuture = _startInternal();
    try {
      await _startFuture!;
    } finally {
      _startFuture = null;
    }
  }

  static Future<void> _startInternal() async {
    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (!isDesktop) {
      developer.log('SuwayomiManager start skipped on non-desktop platform.', name: 'SuwayomiManager');
      statusNotifier.value = "Manga engine external connection ready";
      return;
    }
    try {
      statusNotifier.value = "Checking JRE...";

      final appDir = await getApplicationSupportDirectory();
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedJavaPath = prefs.getString('resolved_java_path');

      String javaPath = 'java';
      bool javaInstalled = false;

      if (cachedJavaPath != null) {
        if (cachedJavaPath == 'java') {
          try {
            final checkResult = await Process.run('java', ['-version']);
            if (checkResult.exitCode == 0 || checkResult.stderr.toString().contains('version')) {
              javaPath = 'java';
              javaInstalled = true;
            }
          } catch (_) {}
        } else {
          final cachedFile = File(cachedJavaPath);
          if (await cachedFile.exists()) {
            javaPath = cachedJavaPath;
            javaInstalled = true;
          }
        }
      }

      if (!javaInstalled) {
        try {
          final systemCheck = await Process.run('java', ['-version']);
          if (systemCheck.exitCode == 0 || systemCheck.stderr.toString().contains('version')) {
            javaPath = 'java';
            javaInstalled = true;
            await prefs.setString('resolved_java_path', 'java');
          }
        } catch (_) {}
      }

      if (!javaInstalled && Platform.isWindows) {
        final localJreDir = Directory(p.join(appDir.path, 'jre'));
        final localJavaExe = File(p.join(localJreDir.path, 'bin', 'java.exe'));

        if (await localJavaExe.exists()) {
          javaPath = localJavaExe.path;
          javaInstalled = true;
          await prefs.setString('resolved_java_path', javaPath);
        } else {
          statusNotifier.value = "Downloading JRE runtime...";
          _isDownloading = true;
          _downloadProgress = 0.0;

          final jreZipUrl = Uri.parse(
              'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.3%2B9/OpenJDK21U-jre_x64_windows_hotspot_21.0.3_9.zip');

          final jreZipPath = p.join(appDir.path, 'jre.zip');
          final jreZipFile = File(jreZipPath);

          final client = HttpClient();
          final request = await client.getUrl(jreZipUrl);
          final response = await request.close();

          if (response.statusCode == 200) {
            final totalBytes = response.contentLength;
            int receivedBytes = 0;

            final sink = jreZipFile.openWrite();
            await response.forEach((chunk) {
              receivedBytes += chunk.length;
              sink.add(chunk);
              if (totalBytes > 0) {
                _downloadProgress = receivedBytes / totalBytes;
                final pct = (_downloadProgress * 100).toStringAsFixed(0);
                statusNotifier.value = "Downloading Java JRE... ($pct%)";
              }
            });
            await sink.close();
            _isDownloading = false;

            statusNotifier.value = "Extracting JRE runtime...";
            final tempExtractDir = Directory(p.join(appDir.path, 'jre_temp'));
            if (await tempExtractDir.exists()) {
              await tempExtractDir.delete(recursive: true);
            }
            await tempExtractDir.create();

            final extractResult = await Process.run('powershell', [
              '-Command',
              'Expand-Archive -Path "$jreZipPath" -DestinationPath "${tempExtractDir.path}" -Force'
            ]);

            if (extractResult.exitCode != 0) {
              statusNotifier.value = "Error: JRE extraction failed.";
              throw Exception("Failed to extract JRE archive.");
            }

            await jreZipFile.delete();

            final extractedSubDirs = tempExtractDir.listSync();
            if (extractedSubDirs.isNotEmpty && extractedSubDirs.first is Directory) {
              final extractedJreDir = extractedSubDirs.first as Directory;
              if (await localJreDir.exists()) {
                await localJreDir.delete(recursive: true);
              }
              await extractedJreDir.rename(localJreDir.path);
            }
            await tempExtractDir.delete(recursive: true);

            if (await localJavaExe.exists()) {
              javaPath = localJavaExe.path;
              javaInstalled = true;
              await prefs.setString('resolved_java_path', javaPath);
            } else {
              statusNotifier.value = "Error: JRE verification failed.";
              throw Exception("Failed to verify JRE path.");
            }
          }
        }
      }

      final savedPort = prefs.getInt('manga_server_port') ?? 4567;
      _port = await _findAvailablePort(savedPort);
      SuwayomiService.port = _port;

      final jarFile = File(p.join(appDir.path, 'Suwayomi-Server.jar'));
      final String? savedVersion = prefs.getString('suwayomi_server_version');
      final bool needsDownload = !await jarFile.exists() || savedVersion != suwayomiServerVersion;

      if (!needsDownload && await isSuwayomiRunning(_port)) {
        statusNotifier.value = "Manga engine running";
        developer.log('Reusing existing Suwayomi-Server instance on port $_port.', name: 'SuwayomiManager');
        return;
      }

      if (needsDownload) {
        statusNotifier.value = "Downloading Suwayomi-Server...";
        _isDownloading = true;
        _downloadProgress = 0.0;
        developer.log('Downloading Suwayomi-Server $suwayomiServerVersion from $suwayomiJarDownloadUrl...', name: 'SuwayomiManager');

        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(suwayomiJarDownloadUrl));
        final response = await request.close();

        if (response.statusCode == 200) {
          final totalBytes = response.contentLength;
          int receivedBytes = 0;

          final tempJar = File(p.join(appDir.path, 'Suwayomi-Server.jar.tmp'));
          if (await tempJar.exists()) await tempJar.delete();

          final sink = tempJar.openWrite();
          await response.forEach((chunk) {
            receivedBytes += chunk.length;
            sink.add(chunk);
            if (totalBytes > 0) {
              _downloadProgress = receivedBytes / totalBytes;
              final pct = (_downloadProgress * 100).toStringAsFixed(0);
              statusNotifier.value = "Downloading Manga Server... ($pct%)";
            }
          });
          await sink.close();
          _isDownloading = false;

          if (await jarFile.exists()) {
            try { await jarFile.delete(); } catch (_) {}
          }
          await tempJar.rename(jarFile.path);
          await prefs.setString('suwayomi_server_version', suwayomiServerVersion);
          developer.log('Suwayomi-Server download complete (${await jarFile.length()} bytes).', name: 'SuwayomiManager');
        } else {
          _isDownloading = false;
          statusNotifier.value = "Error: Failed to download Suwayomi-Server (${response.statusCode})";
          throw Exception("Failed to download Suwayomi-Server: HTTP ${response.statusCode}");
        }
      }

      final runtimeDir = Directory(p.join(appDir.path, 'suwayomi'));
      if (!await runtimeDir.exists()) {
        await runtimeDir.create(recursive: true);
      }

      final confContent = '''
server.initialOpenInBrowserEnabled = false
server.webUIInterface = "BROWSER"
server.systemTrayEnabled = false
server.webUIEnabled = false
server.kcefEnabled = false
server.extensionRepos = [
  "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb"
]
''';

      final confFile = File(p.join(runtimeDir.path, 'server.conf'));
      await confFile.writeAsString(confContent);

      if (Platform.isWindows) {
        final localAppData = Platform.environment['LOCALAPPDATA'];
        if (localAppData != null) {
          final tachideskDir = Directory(p.join(localAppData, 'Tachidesk'));
          if (!await tachideskDir.exists()) {
            await tachideskDir.create(recursive: true);
          }
          final tachideskConf = File(p.join(tachideskDir.path, 'server.conf'));
          if (await tachideskConf.exists()) {
            final existing = await tachideskConf.readAsString();
            final updated = existing
                .replaceAll('server.initialOpenInBrowserEnabled = true', 'server.initialOpenInBrowserEnabled = false')
                .replaceAll('server.webUIInterface = "NONE"', 'server.webUIInterface = "BROWSER"');
            await tachideskConf.writeAsString(updated);
          } else {
            await tachideskConf.writeAsString(confContent);
          }
        }
      }

      statusNotifier.value = "Starting Manga Engine...";
      developer.log('Launching Suwayomi-Server on port $_port using: $javaPath', name: 'SuwayomiManager');

      _process = await Process.start(
        javaPath,
        [
          '-Dserver.initialOpenInBrowserEnabled=false',
          '-Dsuwayomi.server.downloadCef=false',
          '-Dsuwayomi.server.systemTrayEnabled=false',
          '-Dsuwayomi.server.initialOpenInBrowserEnabled=false',
          '-Dserver.port=$_port',
          '-noverify',
          '-Xss8m',
          '-jar',
          jarFile.path,
          '--server.port=$_port',
          '--server.initialOpenInBrowserEnabled=false',
          '--suwayomi.server.downloadCef=false',
          '--suwayomi.server.systemTrayEnabled=false',
          '--suwayomi.server.rootDir=${runtimeDir.path}',
        ],
        workingDirectory: appDir.path,
      );

      _process!.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        final line = data.trim();
        developer.log(line, name: 'SuwayomiServer-stdout');
        processLogs.add('[STDOUT] $line');
        if (processLogs.length > 50) processLogs.removeAt(0);
      });
      _process!.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        final line = data.trim();
        developer.log(line, name: 'SuwayomiServer-stderr');
        processLogs.add('[STDERR] $line');
        if (processLogs.length > 50) processLogs.removeAt(0);
      });

      bool serverReady = false;
      for (int i = 0; i < 120; i++) {
        if (await isSuwayomiRunning(_port)) {
          serverReady = true;
          break;
        }
        final elapsed = ((i + 1) * 0.5).toStringAsFixed(0);
        statusNotifier.value = "Starting Manga Engine (initializing server ${elapsed}s)...";
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (serverReady) {
        statusNotifier.value = "Manga engine running";
        developer.log('Suwayomi-Server is operational on port $_port.', name: 'SuwayomiManager');
      } else {
        statusNotifier.value = "Manga engine starting (waiting...)";
      }
    } catch (e, st) {
      _isDownloading = false;
      developer.log('Error starting Suwayomi-Server: $e', name: 'SuwayomiManager', error: e, stackTrace: st);
      statusNotifier.value = "Error starting Manga engine: $e";
    }
  }

  static Future<void> stop() async {
    if (_process != null) {
      developer.log('Stopping Suwayomi-Server process...', name: 'SuwayomiManager');
      _process!.kill();
      _process = null;
      statusNotifier.value = "Manga engine stopped";
    }
  }
}
