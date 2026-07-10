import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final String changelog;
  final String downloadUrl;

  UpdateInfo({
    required this.version,
    required this.changelog,
    required this.downloadUrl,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    // Locate the correct asset
    final assets = json['assets'] as List<dynamic>? ?? [];
    String downloadUrl = '';
    
    if (Platform.isAndroid) {
      // Find APK. Prefer arm64-v8a asset.
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk') && name.contains('arm64-v8a')) {
          downloadUrl = asset['browser_download_url'] as String? ?? '';
          break;
        }
      }
      // Fallback to any APK
      if (downloadUrl.isEmpty) {
        for (final asset in assets) {
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'] as String? ?? '';
            break;
          }
        }
      }
    } else {
      // Locate the first executable (.exe) asset
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.exe')) {
          downloadUrl = asset['browser_download_url'] as String? ?? '';
          break;
        }
      }
    }

    // Parse tag name
    final tagName = json['tag_name'] as String? ?? '0.0.0';

    return UpdateInfo(
      version: tagName,
      changelog: json['body'] as String? ?? 'No release notes provided.',
      downloadUrl: downloadUrl,
    );
  }
}

class UpdateService extends ChangeNotifier {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const String currentVersion = '2.0.39';
  
  // GitHub Releases API Endpoint
  static const String gitHubReleasesUrl = 'https://api.github.com/repos/Fluffy-The-Penguin/watchAny-2.0/releases/latest';

  UpdateInfo? _latestUpdate;
  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _error;
  String? _downloadedFilePath;
  bool _hasChecked = false;

  UpdateInfo? get latestUpdate => _latestUpdate;
  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String? get error => _error;
  String? get downloadedFilePath => _downloadedFilePath;
  bool get hasChecked => _hasChecked;

  bool get hasUpdate {
    if (_latestUpdate == null) return false;
    final normalizedCurrent = _normalizeVersion(currentVersion);
    final normalizedLatest = _normalizeVersion(_latestUpdate!.version);
    return _compareVersions(normalizedCurrent, normalizedLatest) < 0;
  }

  String _normalizeVersion(String tag) {
    final match = RegExp(r'\d+(\.\d+)+').firstMatch(tag);
    if (match != null) {
      return match.group(0)!;
    }
    return tag;
  }

  int _compareVersions(String v1, String v2) {
    try {
      final parts1 = v1.split('.').map(int.parse).toList();
      final parts2 = v2.split('.').map(int.parse).toList();
      for (var i = 0; i < 3; i++) {
        final p1 = i < parts1.length ? parts1[i] : 0;
        final p2 = i < parts2.length ? parts2[i] : 0;
        if (p1 < p2) return -1;
        if (p1 > p2) return 1;
      }
    } catch (_) {}
    return 0;
  }

  Future<String> _getGhToken() async {
    // 1. Check system environment GITHUB_TOKEN
    final envToken = Platform.environment['GITHUB_TOKEN'] ?? '';
    if (envToken.isNotEmpty && !envToken.contains('invalid')) {
      return envToken.trim();
    }
    
    // 2. Try querying gh CLI auth token
    try {
      final result = await Process.run('gh', ['auth', 'token']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (_) {}

    return '';
  }

  Future<bool> checkForUpdates() async {
    _isChecking = true;
    _error = null;
    notifyListeners();

    try {
      final headers = <String, String>{'User-Agent': 'watchAny-Updater'};
      final token = await _getGhToken();
      if (token.isNotEmpty) {
        headers['Authorization'] = 'token $token';
        debugPrint('[UpdateService] Using GitHub Auth token for live update query.');
      }

      final response = await http.get(
        Uri.parse(gitHubReleasesUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        _latestUpdate = UpdateInfo.fromJson(json);
        if (_latestUpdate!.downloadUrl.isEmpty) {
          final ext = Platform.isAndroid ? 'APK' : 'executable (.exe)';
          throw Exception('No release asset ($ext) found in the latest release.');
        }
      } else {
        throw Exception('GitHub API returned status code: ${response.statusCode}');
      }
    } catch (e) {
      // Fallback mock update in case of failure
      _error = 'Live check failed ($e). Showing fallback updates.';
      _latestUpdate = UpdateInfo(
        version: 'v2.0.39',
        changelog: '• Fixed startup update dialog stretched layout width on desktop\n'
            '• Restored transparent floating logo startup animation\n'
            '• Fixed Hentai episode counts (e.g. Natsuzuma)\n'
            '• Vertically centered search bar layouts\n'
            '• Added global bouncy scroll physics (BouncingScrollPhysics)',
        downloadUrl: Platform.isAndroid 
            ? 'https://github.com/Fluffy-The-Penguin/watchAny-2.0/releases/download/v2.0.39/app-arm64-v8a-release.apk'
            : 'https://github.com/Fluffy-The-Penguin/watchAny-2.0/releases/download/v2.0.39/watchany_setup.exe',
      );
    } finally {
      _isChecking = false;
      _hasChecked = true;
      notifyListeners();
    }
    return hasUpdate;
  }

  Future<void> startUpdate() async {
    if (_latestUpdate == null || _isDownloading) return;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _error = null;
    notifyListeners();

    try {
      final url = _latestUpdate!.downloadUrl;
      final request = http.Request('GET', Uri.parse(url));
      final token = await _getGhToken();
      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'token $token';
      }
      
      final response = await http.Client().send(request);
      final contentLength = response.contentLength ?? 0;
      
      final tempDir = Platform.isAndroid 
          ? await getTemporaryDirectory() 
          : Directory.systemTemp;
      final ext = Platform.isAndroid ? 'apk' : 'exe';
      final filePath = '${tempDir.path}${Platform.pathSeparator}watchany_update_${_latestUpdate!.version}.$ext';
      final file = File(filePath);
      
      if (await file.exists()) {
        await file.delete();
      }

      var downloaded = 0;
      final sink = file.openWrite();
      
      try {
        await for (final chunk in response.stream) {
          downloaded += chunk.length;
          sink.add(chunk);
          if (contentLength > 0) {
            _downloadProgress = downloaded / contentLength;
            notifyListeners();
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      _downloadedFilePath = filePath;
      _isDownloading = false;
      notifyListeners();

      // Launch the installer
      await launchInstaller();
    } catch (e) {
      _error = 'Download failed: $e';
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<void> launchInstaller() async {
    if (_downloadedFilePath == null) return;
    try {
      if (Platform.isWindows) {
        await Process.start(_downloadedFilePath!, []);
        // Exit the current app so the installer can overwrite the executable
        exit(0);
      } else if (Platform.isAndroid) {
        const channel = MethodChannel('com.example.watch_any/native_path');
        await channel.invokeMethod('installApk', {'filePath': _downloadedFilePath});
      } else {
        throw Exception('Auto update is only supported on Windows and Android.');
      }
    } catch (e) {
      _error = 'Failed to launch installer: $e';
      notifyListeners();
    }
  }
}
