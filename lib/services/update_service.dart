import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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

  static const String currentVersion = '2.1.34';





































  
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


  Future<bool> checkForUpdates() async {
    _isChecking = true;
    _error = null;
    notifyListeners();

    try {
      final headers = <String, String>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) watchAny-App/$currentVersion',
        'Accept': 'application/vnd.github.v3+json',
      };

      http.Response? response;
      try {
        response = await http.get(
          Uri.parse(gitHubReleasesUrl),
          headers: headers,
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        // Fallback: Releases list endpoint if latest endpoint fails/redirects
        response = await http.get(
          Uri.parse('https://api.github.com/repos/Fluffy-The-Penguin/watchAny-2.0/releases'),
          headers: headers,
        ).timeout(const Duration(seconds: 10));
      }

      if (response != null && response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final json = decoded is List ? (decoded.isNotEmpty ? decoded.first : null) : decoded;

        if (json != null && json is Map<String, dynamic>) {
          final info = UpdateInfo.fromJson(json);
          if (info.downloadUrl.isNotEmpty) {
            _latestUpdate = info;
            _error = null;
          } else {
            final ext = Platform.isAndroid ? 'APK' : 'executable (.exe)';
            _error = 'Latest release found (${info.version}) but no $ext download asset was available.';
          }
        } else {
          _error = 'Unable to parse update details from release server.';
        }
      } else if (response != null && response.statusCode == 403) {
        _error = 'Update check rate-limited by GitHub. Please try again in a few minutes.';
      } else {
        _error = 'Update server responded with status code: ${response?.statusCode ?? 'Unknown'}';
      }
    } on SocketException {
      _error = 'Unable to check for updates: No internet connection or host unreachable.';
      _latestUpdate = null;
    } on TimeoutException {
      _error = 'Update check timed out. Please check your internet connection.';
      _latestUpdate = null;
    } catch (e) {
      _error = 'Unable to check for updates: ${e.toString().replaceAll(RegExp(r'^Exception:\s*'), '')}';
      _latestUpdate = null;
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
      request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) watchAny-App/$currentVersion';
      
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

      // SHA-256 verification: fetch checksums.txt from the same release and
      // compare against the hash of the downloaded file before executing it.
      final checksumUrl = _latestUpdate!.downloadUrl
          .replaceAll(RegExp(r'/[^/]+$'), '/checksums.txt');
      try {
        final checksumResp = await http.get(
          Uri.parse(checksumUrl),
          headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) watchAny-App/$currentVersion'},
        ).timeout(const Duration(seconds: 8));
        if (checksumResp.statusCode == 200) {
          final expectedHash = _extractHash(
            checksumResp.body,
            filePath.split(Platform.pathSeparator).last,
          );
          if (expectedHash != null) {
            final fileBytes = await File(filePath).readAsBytes();
            final actualHash = sha256.convert(fileBytes).toString();
            if (actualHash != expectedHash) {
              await File(filePath).delete();
              _downloadedFilePath = null;
              _error = 'SHA-256 mismatch — download may be corrupted or tampered. Please try again.';
              _isDownloading = false;
              notifyListeners();
              return;
            }
            debugPrint('[UpdateService] SHA-256 verified: $actualHash');
          } else {
            debugPrint('[UpdateService] No checksum entry found for this asset; skipping verification.');
          }
        } else {
          debugPrint('[UpdateService] checksums.txt not found (${checksumResp.statusCode}); skipping verification.');
        }
      } catch (e) {
        debugPrint('[UpdateService] Checksum fetch failed ($e); proceeding without verification.');
      }

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
        // Run Inno Setup installer silently and force close running app instance
        await Process.start(_downloadedFilePath!, [
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/CLOSEAPPLICATIONS',
          '/FORCECLOSEAPPLICATIONS',
        ]);
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

  /// Parses a standard `sha256sum` formatted file (each line: `<hash>  <filename>`)
  /// and returns the expected hash for [filename], or null if not found.
  String? _extractHash(String checksumsContent, String filename) {
    for (final line in checksumsContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // Format: "<64-char hash>  <filename>" (two spaces) or "<hash> <filename>"
      final spaceIdx = trimmed.indexOf(' ');
      if (spaceIdx == 64) {
        final hash = trimmed.substring(0, 64);
        final name = trimmed.substring(spaceIdx).trimLeft();
        if (name == filename) return hash;
      }
    }
    return null;
  }
}
