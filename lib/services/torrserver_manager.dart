import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/services.dart' show rootBundle, MethodChannel;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../state/app_settings.dart';
import 'log_service.dart';

class TorrServerManager {
  static Process? _process;
  static bool _isStarting = false;
  static int _port = 8090;
  static int get port => _port;
  static String? lastStartupError;

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
    while (port < startPort + 10) {
      try {
        // Try binding instantly (takes ~1ms)
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await socket.close();
        return port;
      } catch (_) {
        // Port is occupied, check if TorrServer is already running on it
        if (await _isTorrServerRunning(port)) {
          _log('TorrServer is already running on port $port. Will reuse.');
          return port;
        }
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
        _log('Optimal streaming settings applied successfully.');
      } catch (e, stack) {
        _log('Failed to apply streaming settings', level: 'ERROR', error: e, stackTrace: stack);
      }
    });
  }

  static Future<void> start() async {
    if (_process != null || _isStarting) {
      developer.log('TorrServer already running or starting...', name: 'TorrServerManager');
      return;
    }
    _isStarting = true;

    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final bool isAndroid = !kIsWeb && Platform.isAndroid;

    if (!isDesktop && !isAndroid) {
      developer.log('TorrServerManager start skipped on unsupported platform.', name: 'TorrServerManager');
      _isStarting = false;
      return;
    }

    try {
      _port = await _findAvailablePort(8090);
      AppSettings().updateLocalTorrServerPort(_port);

      if (await _isTorrServerRunning(_port)) {
        _log('Reusing existing TorrServer instance on port $_port.');
        _applySettings(_port);
        _isStarting = false;
        return;
      }

      if (isAndroid) {
        await _startAndroid();
      } else {
        await _startDesktop();
      }
    } catch (e, stack) {
      _log('Error starting TorrServer', level: 'ERROR', error: e, stackTrace: stack);
    } finally {
      _isStarting = false;
    }
  }

  static Future<void> _startAndroid() async {
    try {
      // Query the true native library directory path from MainActivity
      const platform = MethodChannel('com.example.watch_any/native_path');
      final String nativeLibDir = await platform.invokeMethod('getNativeLibraryDir');
      final nativeLibPath = '$nativeLibDir/libtorrserver.so';
      final dataDir = (await getApplicationSupportDirectory()).path;

      final file = File(nativeLibPath);
      if (!await file.exists()) {
        lastStartupError = "Native binary not found at $nativeLibPath. Verify extractNativeLibs is true in manifest.";
        _log(lastStartupError!, level: 'ERROR', error: lastStartupError);
        return;
      }

      // Check and set executable permissions if needed
      try {
        final result = await Process.run('chmod', ['755', nativeLibPath]);
        if (result.exitCode != 0) {
          developer.log('chmod failed: ${result.stderr}', name: 'TorrServerManager', error: result.stderr);
        }
      } catch (e, stack) {
        developer.log('Failed to chmod', name: 'TorrServerManager', error: e, stackTrace: stack);
      }

      developer.log('Launching TorrServer on Android, port $_port, db: $dataDir', name: 'TorrServerManager');
      _process = await Process.start(nativeLibPath, ['-p', '$_port', '-d', dataDir]);

      lastStartupError = null; // Clear old error

      _process!.stdout.transform(utf8.decoder).listen((data) {
        developer.log(data.trim(), name: 'TorrServer-STDOUT');
      });

      final StringBuffer errorBuffer = StringBuffer();
      _process!.stderr.transform(utf8.decoder).listen((data) {
        developer.log(data.trim(), name: 'TorrServer-STDERR');
        errorBuffer.write(data);
        lastStartupError = errorBuffer.toString();
      });

      _process!.exitCode.then((exitCode) {
        if (exitCode != 0) {
          final errStr = errorBuffer.toString();
          lastStartupError = "TorrServer failed to bind to port $_port. Exit code: $exitCode. Stderr: ${errStr.isEmpty ? 'No stderr' : errStr}";
          _log(lastStartupError!, level: 'ERROR');
        }
      });

      _log('TorrServer process started on Android!');
      _applySettings(_port);
    } catch (e, stack) {
      lastStartupError = 'Failed to start TorrServer: $e';
      _log(lastStartupError!, level: 'ERROR', error: e, stackTrace: stack);
    }
  }

  static Future<void> _startDesktop() async {
    final appDir = await getApplicationSupportDirectory();
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }

    final exePath = '${appDir.path}\\torrserver.exe';
    final file = File(exePath);

    // Copy from assets to local file if not exists or if size is 0
    if (!await file.exists() || await file.length() == 0) {
      _log('Extracting TorrServer binary to AppData...');
      final byteData = await rootBundle.load('assets/bin/torrserver.exe');
      final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      await file.writeAsBytes(bytes);
      _log('Extraction complete.');
    }

    // Start the process
    _log('Launching TorrServer process on port $_port with DB path: ${appDir.path}...');
    _process = await Process.start(exePath, ['-p', '$_port', '-d', appDir.path]);
    
    // Log stdout and stderr
    _process!.stdout.transform(utf8.decoder).listen((data) {
      developer.log(data.trim(), name: 'TorrServer-STDOUT');
    });
    _process!.stderr.transform(utf8.decoder).listen((data) {
      developer.log(data.trim(), name: 'TorrServer-STDERR');
    });

    _log('TorrServer started successfully!');
    _applySettings(_port);
  }

  static Future<void> stop() async {
    if (_process != null) {
      _log('Terminating TorrServer process...');
      _process!.kill();
      _process = null;
    }
  }

  static void _log(String message, {String level = 'INFO', dynamic error, StackTrace? stackTrace}) {
    developer.log(message, name: 'TorrServerManager', error: error, stackTrace: stackTrace);
    if (level == 'ERROR') {
      LogService().error('[TorrServerManager] $message', error, stackTrace);
    } else {
      LogService().info('[TorrServerManager] $message');
    }
  }
}
