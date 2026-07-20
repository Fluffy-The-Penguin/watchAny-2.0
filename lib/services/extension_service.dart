import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'log_service.dart';

class ExtensionRepo {
  final String url;
  final String name;

  ExtensionRepo({required this.url, required this.name});

  Map<String, dynamic> toJson() => {'url': url, 'name': name};

  factory ExtensionRepo.fromJson(Map<String, dynamic> json) {
    return ExtensionRepo(
      url: json['url'] ?? '',
      name: json['name'] ?? '',
    );
  }
}

class Extension {
  final String id;
  final String name;
  final String version;
  final String type;
  final String accuracy;
  final List<String> languages;
  final String icon;
  final String codeUrl;
  final String repoUrl;
  bool isEnabled;
  String? cachedCode;

  Extension({
    required this.id,
    required this.name,
    required this.version,
    required this.type,
    required this.accuracy,
    required this.languages,
    required this.icon,
    required this.codeUrl,
    required this.repoUrl,
    this.isEnabled = true,
    this.cachedCode,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'type': type,
      'accuracy': accuracy,
      'languages': languages,
      'icon': icon,
      'codeUrl': codeUrl,
      'repoUrl': repoUrl,
      'isEnabled': isEnabled,
      'cachedCode': cachedCode,
    };
  }

  factory Extension.fromJson(Map<String, dynamic> json) {
    return Extension(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      version: json['version'] ?? '',
      type: json['type'] ?? '',
      accuracy: json['accuracy'] ?? '',
      languages: List<String>.from(json['languages'] ?? []),
      icon: json['icon'] ?? '',
      codeUrl: json['code'] ?? json['codeUrl'] ?? '',
      repoUrl: json['repoUrl'] ?? '',
      isEnabled: json['isEnabled'] ?? true,
      cachedCode: json['cachedCode'],
    );
  }
}

class TorrentStream {
  final String title;
  final String link;
  final int seeders;
  final int leechers;
  final int downloads;
  final String hash;
  final int size;
  final String accuracy;
  final String? type;
  final DateTime? date;
  final String extensionName;

  TorrentStream({
    required this.title,
    required this.link,
    required this.seeders,
    required this.leechers,
    required this.downloads,
    required this.hash,
    required this.size,
    required this.accuracy,
    this.type,
    this.date,
    required this.extensionName,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'link': link,
      'seeders': seeders,
      'leechers': leechers,
      'downloads': downloads,
      'hash': hash,
      'size': size,
      'accuracy': accuracy,
      'type': type,
      'date': date?.toIso8601String(),
      'extensionName': extensionName,
    };
  }

  factory TorrentStream.fromJson(Map<String, dynamic> json, String extensionName) {
    return TorrentStream(
      title: json['title'] ?? '',
      link: json['link'] ?? '',
      seeders: json['seeders'] is int ? json['seeders'] : (int.tryParse(json['seeders']?.toString() ?? '0') ?? 0),
      leechers: json['leechers'] is int ? json['leechers'] : (int.tryParse(json['leechers']?.toString() ?? '0') ?? 0),
      downloads: json['downloads'] is int ? json['downloads'] : (int.tryParse(json['downloads']?.toString() ?? '0') ?? 0),
      hash: json['hash'] ?? '',
      size: json['size'] is int ? json['size'] : (int.tryParse(json['size']?.toString() ?? '0') ?? 0),
      accuracy: json['accuracy'] ?? 'medium',
      type: json['type'],
      date: json['date'] != null ? DateTime.tryParse(json['date']) : null,
      extensionName: extensionName,
    );
  }
}

class ExtensionService extends ChangeNotifier {
  static final ExtensionService _instance = ExtensionService._internal();
  factory ExtensionService() => _instance;
  ExtensionService._internal();

  final http.Client _httpClient = http.Client();
  static final Map<int, Map<String, dynamic>> _mappingsCache = {};
  static final Map<int, Future<Map<String, dynamic>?>> _mappingsFetchFutures = {};

  Future<void> preloadMappings(int anilistId) async {
    if (_mappingsCache.containsKey(anilistId)) return;
    final mappings = await _fetchMappings(anilistId);
    if (mappings != null) {
      _mappingsCache[anilistId] = mappings;
    }
  }

  Future<Map<String, dynamic>?> getMappings(int anilistId) async {
    return _fetchMappings(anilistId);
  }

  static Future<JavascriptRuntime>? _runtimeLock;

  static Future<JavascriptRuntime> _createRuntime() async {
    final currentLock = _runtimeLock;
    final completer = Completer<JavascriptRuntime>();
    _runtimeLock = completer.future;
    
    if (currentLock != null) {
      try {
        await currentLock;
      } catch (_) {}
    }
    
    try {
      final runtime = getJavascriptRuntime();
      completer.complete(runtime);
      return runtime;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    }
  }

  File? _storageFile;
  File? _logFile;

  void _logError(String message) {
    try {
      if (_logFile != null) {
        _logFile!.writeAsStringSync('${DateTime.now().toIso8601String()}: $message\n', mode: FileMode.append);
      }
      LogService().error('[ExtensionService] $message');
    } catch (_) {}
  }

  List<ExtensionRepo> repos = [];
  List<Extension> extensions = [];
  Map<String, String> availableUpdates = {};
  bool isCheckingForUpdates = false;

  // Check for updates across all extensions in registered repositories
  Future<void> checkForUpdates() async {
    isCheckingForUpdates = true;
    notifyListeners();

    final newUpdates = <String, String>{};

    for (final repo in repos) {
      try {
        final response = await http.get(Uri.parse(repo.url)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final List<dynamic> indexList = jsonDecode(response.body);
          for (final item in indexList) {
            final id = item['id']?.toString() ?? '';
            final newVersion = item['version']?.toString() ?? '';
            if (id.isEmpty || newVersion.isEmpty) continue;

            // Find installed extension matching id and repo
            final installed = extensions.firstWhere(
              (e) => e.id == id && e.repoUrl == repo.url,
              orElse: () => Extension(id: '', name: '', version: '', type: '', accuracy: '', languages: [], icon: '', codeUrl: '', repoUrl: ''),
            );

            if (installed.id.isNotEmpty) {
              if (_isVersionNewer(installed.version, newVersion)) {
                newUpdates[id] = newVersion;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[ExtensionService] Error checking updates for repo ${repo.url}: $e');
      }
    }

    availableUpdates = newUpdates;
    isCheckingForUpdates = false;
    notifyListeners();
  }

  // Compare versions semver-style
  bool _isVersionNewer(String current, String remote) {
    try {
      final cleanCurrent = current.trim().replaceFirst(RegExp(r'^[vV]'), '');
      final cleanRemote = remote.trim().replaceFirst(RegExp(r'^[vV]'), '');

      final currentParts = cleanCurrent.split('.').map((e) {
        final match = RegExp(r'^\d+').firstMatch(e);
        return match != null ? (int.tryParse(match.group(0)!) ?? 0) : 0;
      }).toList();

      final remoteParts = cleanRemote.split('.').map((e) {
        final match = RegExp(r'^\d+').firstMatch(e);
        return match != null ? (int.tryParse(match.group(0)!) ?? 0) : 0;
      }).toList();

      final maxLen = currentParts.length > remoteParts.length ? currentParts.length : remoteParts.length;
      for (int i = 0; i < maxLen; i++) {
        final currentVal = i < currentParts.length ? currentParts[i] : 0;
        final remoteVal = i < remoteParts.length ? remoteParts[i] : 0;
        if (remoteVal > currentVal) return true;
        if (remoteVal < currentVal) return false;
      }
    } catch (_) {}
    return false;
  }

  // Update a single extension by ID
  Future<void> updateExtension(String id) async {
    final ext = extensions.firstWhere(
      (e) => e.id == id,
      orElse: () => throw Exception('Extension not found.'),
    );
    final repoUrl = ext.repoUrl;
    if (repoUrl.isEmpty) throw Exception('No repository associated with this extension.');

    final response = await http.get(Uri.parse(repoUrl)).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch repository index: HTTP ${response.statusCode}');
    }

    final List<dynamic> indexList = jsonDecode(response.body);
    final item = indexList.firstWhere(
      (i) => i['id'] == id,
      orElse: () => null,
    );
    if (item == null) {
      throw Exception('Extension not found in repository index.');
    }

    final newManifest = Extension.fromJson(item);
    String codeUrl = newManifest.codeUrl;
    if (!codeUrl.startsWith('http')) {
      final uri = Uri.parse(repoUrl);
      codeUrl = uri.resolve(codeUrl).toString();
    }

    final codeResponse = await http.get(Uri.parse(codeUrl)).timeout(const Duration(seconds: 12));
    if (codeResponse.statusCode != 200) {
      throw Exception('Failed to fetch extension code: HTTP ${codeResponse.statusCode}');
    }

    final jsCode = codeResponse.body;
    final idx = extensions.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final existing = extensions[idx];
      extensions[idx] = Extension(
        id: newManifest.id,
        name: newManifest.name,
        version: newManifest.version,
        type: newManifest.type,
        accuracy: newManifest.accuracy,
        languages: newManifest.languages,
        icon: newManifest.icon,
        codeUrl: codeUrl,
        repoUrl: repoUrl,
        isEnabled: existing.isEnabled,
        cachedCode: jsCode,
      );
    }
    availableUpdates.remove(id);
    await save();
  }

  // Update all available extensions
  Future<void> updateAllExtensions() async {
    final idsToUpdate = availableUpdates.keys.toList();
    for (final id in idsToUpdate) {
      try {
        await updateExtension(id);
      } catch (e) {
        debugPrint('[ExtensionService] Failed to update extension $id: $e');
      }
    }
  }

  bool _isInitialized = false;
  Future<void>? _initFuture;

  // Initialize and load saved state, seeding default repos if empty
  Future<void> init() async {
    if (_isInitialized) return;
    _initFuture ??= _doInit();
    return _initFuture;
  }

  Future<void> _doInit() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      _storageFile = File('${appDir.path}\\extensions_storage.json');
      _logFile = File('${appDir.path}\\extension_debug.log');

      // Warm up JS engine in the background after startup completes to prevent launch lag
      Future.delayed(const Duration(seconds: 4), () async {
        debugPrint('[ExtensionService] Warming up Javascript engine...');
        try {
          final runtime = await _createRuntime();
          runtime.dispose();
          debugPrint('[ExtensionService] Javascript engine warmed up successfully.');
        } catch (e) {
          debugPrint('[ExtensionService] Javascript warmup error: $e');
        }
      });

      if (await _storageFile!.exists()) {
        final content = await _storageFile!.readAsString();
        final data = jsonDecode(content);
        
        repos = (data['repos'] as List? ?? [])
            .map((r) => ExtensionRepo.fromJson(r))
            .toList();
            
        extensions = (data['extensions'] as List? ?? [])
            .map((e) => Extension.fromJson(e))
            .toList();
      } else {
        // Start with empty lists - user adds manually
        repos = [];
        extensions = [];
        await save();
      }
      _isInitialized = true;
      notifyListeners();
      unawaited(ensureExtensionCodesLoaded());
    } catch (e) {
      debugPrint('Error initializing ExtensionService: $e');
    }
  }

  Future<void> ensureExtensionCodesLoaded() async {
    bool changed = false;
    for (int i = 0; i < extensions.length; i++) {
      final ext = extensions[i];
      if ((ext.cachedCode == null || ext.cachedCode!.isEmpty) && ext.codeUrl.isNotEmpty) {
        try {
          final response = await http.get(Uri.parse(ext.codeUrl)).timeout(const Duration(seconds: 12));
          if (response.statusCode == 200 && response.body.isNotEmpty) {
            ext.cachedCode = response.body;
            changed = true;
          }
        } catch (e) {
          debugPrint('[ExtensionService] Failed to load code for ${ext.name}: $e');
        }
      }
    }
    if (changed) {
      await save();
    }
  }

  Future<void> importCloudData({List<dynamic>? reposJson, List<dynamic>? extensionsJson}) async {
    await init();
    bool changed = false;

    if (reposJson != null && reposJson.isNotEmpty) {
      final cloudRepos = reposJson.map((r) => ExtensionRepo.fromJson(Map<String, dynamic>.from(r))).toList();
      for (final cr in cloudRepos) {
        if (cr.url.isNotEmpty && !repos.any((r) => r.url.toLowerCase() == cr.url.toLowerCase())) {
          repos.add(cr);
          changed = true;
        }
      }
    }

    if (extensionsJson != null && extensionsJson.isNotEmpty) {
      final cloudExts = extensionsJson.map((e) => Extension.fromJson(Map<String, dynamic>.from(e))).toList();
      for (final ce in cloudExts) {
        if (ce.id.isNotEmpty && !extensions.any((e) => e.id == ce.id)) {
          extensions.add(ce);
          changed = true;
        }
      }
    }

    if (changed) {
      await save();
      await ensureExtensionCodesLoaded();
      unawaited(checkForUpdates());
    }
  }

  // Save current repos and extensions to disk
  Future<void> save() async {
    try {
      if (_storageFile == null) return;
      final data = {
        'repos': repos.map((r) => r.toJson()).toList(),
        'extensions': extensions.map((e) => e.toJson()).toList(),
      };
      await _storageFile!.writeAsString(jsonEncode(data));
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving ExtensionService data: $e');
    }
  }

  // Add new extension repository and immediately sync it
  Future<void> addRepo(String url, String name) async {
    url = url.trim();
    if (url.isEmpty) return;
    if (repos.any((r) => r.url.toLowerCase() == url.toLowerCase())) {
      throw Exception('Repository URL already exists.');
    }
    
    final newRepo = ExtensionRepo(url: url, name: name.isEmpty ? 'Custom Repo' : name);
    repos.add(newRepo);
    await save();
    
    try {
      await syncRepo(url);
    } catch (e) {
      // Rollback if sync failed
      repos.removeWhere((r) => r.url == url);
      await save();
      rethrow;
    }
  }

  // Remove a repo and all its extensions
  Future<void> removeRepo(String url) async {
    repos.removeWhere((r) => r.url == url);
    extensions.removeWhere((e) => e.repoUrl == url);
    await save();
  }

  // Sync / Refresh extensions from a repo
  Future<void> syncRepo(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch repository index: HTTP ${response.statusCode}');
      }
      
      final List<dynamic> indexList = jsonDecode(response.body);
      
      for (final item in indexList) {
        final newManifest = Extension.fromJson(item);
        
        // Setup code URL relative to the repo URL if it doesn't specify domain
        String codeUrl = newManifest.codeUrl;
        if (!codeUrl.startsWith('http')) {
          final uri = Uri.parse(url);
          codeUrl = uri.resolve(codeUrl).toString();
        }
        
        // Fetch JS code content
        final codeResponse = await http.get(Uri.parse(codeUrl));
        if (codeResponse.statusCode != 200) {
          debugPrint('Failed to fetch code for extension ${newManifest.name} from $codeUrl');
          continue;
        }
        
        final jsCode = codeResponse.body;
        
        // Check if extension already exists
        final existingIdx = extensions.indexWhere((e) => e.id == newManifest.id && e.repoUrl == url);
        
        if (existingIdx != -1) {
          // Update manifest and cached code
          final existing = extensions[existingIdx];
          extensions[existingIdx] = Extension(
            id: newManifest.id,
            name: newManifest.name,
            version: newManifest.version,
            type: newManifest.type,
            accuracy: newManifest.accuracy,
            languages: newManifest.languages,
            icon: newManifest.icon,
            codeUrl: codeUrl,
            repoUrl: url,
            isEnabled: existing.isEnabled, // Retain user preference
            cachedCode: jsCode,
          );
        } else {
          // Add new extension
          extensions.add(Extension(
            id: newManifest.id,
            name: newManifest.name,
            version: newManifest.version,
            type: newManifest.type,
            accuracy: newManifest.accuracy,
            languages: newManifest.languages,
            icon: newManifest.icon,
            codeUrl: codeUrl,
            repoUrl: url,
            isEnabled: true,
            cachedCode: jsCode,
          ));
        }
      }
      
      await save();
    } catch (e) {
      debugPrint('Error syncing repository $url: $e');
      rethrow;
    }
  }

  // Toggle extension state
  Future<void> toggleExtension(String id, bool enabled) async {
    for (var ext in extensions) {
      if (ext.id == id) {
        ext.isEnabled = enabled;
      }
    }
    await save();
  }

  // Formulate standard sandboxed JS environment with polyfills
  String _prepareJSCode(String code) {
    const polyfills = """
      globalThis.navigator = { onLine: true };
      globalThis.atob = function(input) {
        var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
        var str = String(input).replace(/[=]+\$/, '');
        if (str.length % 4 == 1) {
          throw new Error("'atob' failed: The string to be decoded is not correctly encoded.");
        }
        var bc = 0, bs, r = "", idx = 0;
        for (
          ;
          char = str.charAt(idx++);
          ~char && (bs = bc % 4 ? bs * 64 + char : char,
            bc++ % 4) ? r += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0
        ) {
          char = chars.indexOf(char);
        }
        return r;
      };
      
      globalThis.URLSearchParams = class URLSearchParams {
        constructor(init) {
          this.params = [];
          if (typeof init === 'string') {
            var pairs = init.split('&');
            for (var i = 0; i < pairs.length; i++) {
              var pair = pairs[i].split('=');
              this.params.push([decodeURIComponent(pair[0]), decodeURIComponent(pair[1] || '')]);
            }
          } else if (init && typeof init === 'object') {
            for (var key in init) {
              this.params.push([key, String(init[key])]);
            }
          }
        }
        append(key, value) {
          this.params.push([key, String(value)]);
        }
        toString() {
          var parts = [];
          for (var i = 0; i < this.params.length; i++) {
            var pair = this.params[i];
            parts.push(encodeURIComponent(pair[0]) + '=' + encodeURIComponent(pair[1]));
          }
          return parts.join('&');
        }
      };

      globalThis.fetchCount = 0;
      globalThis.fetchResolvers = {};
      globalThis.resolveFetch = function(id, response) {
        if (globalThis.fetchResolvers[id]) {
          globalThis.fetchResolvers[id].resolve({
            status: response.statusCode,
            ok: response.statusCode >= 200 && response.statusCode < 300,
            headers: {
              get: function(name) {
                return response.headers[name] || response.headers[name.toLowerCase()] || null;
              }
            },
            text: async function() { return response.body; },
            json: async function() { return JSON.parse(response.body); }
          });
          delete globalThis.fetchResolvers[id];
        }
      };
      globalThis.rejectFetch = function(id, error) {
        if (globalThis.fetchResolvers[id]) {
          globalThis.fetchResolvers[id].reject(new Error(error));
          delete globalThis.fetchResolvers[id];
        }
      };
      globalThis.customFetch = function(url, options) {
        return new Promise(function(resolve, reject) {
          var id = ++globalThis.fetchCount;
          globalThis.fetchResolvers[id] = { resolve: resolve, reject: reject };
          var req = {
            id: id,
            url: url,
            method: (options && options.method) || 'GET',
            headers: (options && options.headers) || {},
            body: (options && options.body) || null
          };
          sendMessage('fetchChannel', JSON.stringify(req));
        });
      };
      try {
        globalThis.fetch = globalThis.customFetch;
      } catch(e) {}
    """;
    
    // Replace export default new class <Name> with globalThis.extension = new class <Name>
    var transformedCode = code.replaceFirst(
      RegExp(r'export\s+default\s+new\s+class\s*\w*'),
      'globalThis.extension = new class'
    );
    
    // Fix strict equality type mismatch bugs in extensions (e.g. String vs Int)
    transformedCode = transformedCode
        .replaceAll('=== tvdbEId', '== tvdbEId')
        .replaceAll('=== tvdbId', '== tvdbId')
        .replaceAll('=== anidbEid', '== anidbEid')
        .replaceAll('=== episode', '== episode')
        .replaceAll('=== anilistId', '== anilistId');
    
    // Wrap transformedCode in an IIFE to localise `fetch` so it overrides globalThis.fetch
    final wrappedCode = """
      (function() {
        const fetch = globalThis.customFetch;
        $transformedCode
      })();
    """;
    
    return polyfills + "\n" + wrappedCode;
  }

  void _setupRuntime(JavascriptRuntime runtime) {
    runtime.onMessage('fetchChannel', (dynamic message) async {
      int? id;
      String? url;
      try {
        final Map<String, dynamic> req;
        if (message is Map) {
          req = Map<String, dynamic>.from(message);
        } else if (message is String) {
          req = jsonDecode(message);
        } else {
          throw 'Invalid message type: ${message.runtimeType}';
        }
        id = req['id'];
        url = req['url'];
        final String method = req['method'];
        final Map<String, dynamic> headers = req['headers'] ?? {};
        final String? body = req['body'];
        
        final Map<String, String> stringHeaders = headers.map((k, v) => MapEntry(k, v.toString()));
        
        // Inject custom User-Agent to avoid Cloudflare/API blocks
        if (!stringHeaders.containsKey('User-Agent') && !stringHeaders.containsKey('user-agent')) {
          stringHeaders['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
        }
        
        http.Response response;
        if (method == 'POST') {
          response = await _httpClient.post(Uri.parse(url!), headers: stringHeaders, body: body);
        } else {
          response = await _httpClient.get(Uri.parse(url!), headers: stringHeaders);
        }
        
        LogService().info('[Extension Fetch] URL: $url -> Status: ${response.statusCode}, Body Length: ${response.body.length}');
        if (response.statusCode != 200) {
          LogService().warning('[Extension Fetch] Non-200 response body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');
        }
        
        final responseData = {
          'statusCode': response.statusCode,
          'headers': response.headers,
          'body': response.body,
        };
        
        runtime.evaluate("globalThis.resolveFetch($id, ${jsonEncode(responseData)});");
        runtime.executePendingJob(); // Run microtasks immediately!
      } catch (e) {
        LogService().error('[Extension Fetch] Error requesting $url: $e');
        if (id != null) {
          try {
            runtime.evaluate("globalThis.rejectFetch($id, ${jsonEncode(e.toString())});");
            runtime.executePendingJob(); // Run microtasks immediately!
          } catch (_) {}
        } else {
          try {
            final Map<String, dynamic> req = jsonDecode(message);
            final int fallbackId = req['id'];
            runtime.evaluate("globalThis.rejectFetch($fallbackId, ${jsonEncode(e.toString())});");
            runtime.executePendingJob(); // Run microtasks immediately!
          } catch (_) {}
        }
      }
    });
  }

  // Test an individual extension by running its test() method in JS runtime
  Future<bool> testExtension(Extension ext) async {
    if (ext.cachedCode == null || ext.cachedCode!.isEmpty) {
      throw Exception('Extension code is not loaded/cached.');
    }
    
    final JavascriptRuntime runtime = await _createRuntime();
    _setupRuntime(runtime);
    Timer? timer;
    try {
      final preparedCode = _prepareJSCode(ext.cachedCode!);
      
      // Load the extension code
      await runtime.evaluateAsync(preparedCode);
      
      // Start event loop execution timer
      timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        runtime.executePendingJob();
      });
      
      // Run test IIFE
      final runTestJS = """
        (async () => {
          try {
            if (globalThis.extension && typeof globalThis.extension.test === 'function') {
              var result = await globalThis.extension.test();
              return JSON.stringify({ success: !!result });
            } else {
              return JSON.stringify({ error: "test() method not found on extension." });
            }
          } catch (e) {
            return JSON.stringify({ error: e.message || e.toString() });
          }
        })()
      """;
      
      final evalResult = await runtime.evaluateAsync(runTestJS);
      final resolvedResult = await runtime.handlePromise(evalResult);
      
      if (resolvedResult.isError) {
        throw Exception(resolvedResult.stringResult);
      }
      
      final jsonResponse = jsonDecode(resolvedResult.stringResult);
      if (jsonResponse['error'] != null) {
        throw Exception(jsonResponse['error']);
      }
      
      return jsonResponse['success'] == true;
    } catch (e, stack) {
      _logError('Error testing extension ${ext.name}: $e\n$stack');
      rethrow;
    } finally {
      timer?.cancel();
      runtime.dispose();
    }
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return int.tryParse(value.toString());
  }

  // Fetch AniList -> AniDB mappings from api.ani.zip using Request Coalescing (Single Flight)
  Future<Map<String, dynamic>?> _fetchMappings(int anilistId) async {
    if (_mappingsCache.containsKey(anilistId)) {
      return _mappingsCache[anilistId];
    }
    
    if (_mappingsFetchFutures.containsKey(anilistId)) {
      debugPrint('[_fetchMappings] Sharing in-flight request for mappings: $anilistId');
      return _mappingsFetchFutures[anilistId];
    }

    final future = () async {
      try {
        debugPrint('[_fetchMappings] Requesting mappings for $anilistId from api.ani.zip...');
        final response = await _httpClient.get(
          Uri.parse('https://api.ani.zip/mappings?anilist_id=$anilistId')
        ).timeout(const Duration(seconds: 5));
        
        debugPrint('[_fetchMappings] Mappings response for $anilistId: status ${response.statusCode}');
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          _mappingsCache[anilistId] = data;
          return data;
        }
      } catch (e) {
        debugPrint('Error fetching mappings from api.ani.zip: $e');
      } finally {
        _mappingsFetchFutures.remove(anilistId);
      }
      return null;
    }();

    _mappingsFetchFutures[anilistId] = future;
    return future;
  }

  // Query all active extensions for torrent streams in parallel using Stream for lazy loading
  Stream<List<TorrentStream>> searchStreamsStream({
    required int anilistId,
    required List<String> titles,
    required int episodeCount,
    required int episodeNumber,
    Map<String, dynamic>? media,
    String? resolution,
    List<String>? exclusions,
    bool isMovie = false,
  }) {
    final controller = StreamController<List<TorrentStream>>();
    final List<TorrentStream> allStreams = [];
    
    _searchStreamsAsync(
      controller: controller,
      allStreams: allStreams,
      anilistId: anilistId,
      titles: titles,
      episodeCount: episodeCount,
      episodeNumber: episodeNumber,
      media: media,
      resolution: resolution,
      exclusions: exclusions,
      isMovie: isMovie,
    );
    
    return controller.stream;
  }

  Future<void> _searchStreamsAsync({
    required StreamController<List<TorrentStream>> controller,
    required List<TorrentStream> allStreams,
    required int anilistId,
    required List<String> titles,
    required int episodeCount,
    required int episodeNumber,
    Map<String, dynamic>? media,
    String? resolution,
    List<String>? exclusions,
    bool isMovie = false,
  }) async {
    try {
      LogService().info('Starting extension search (VERIFY NEW CODE v2) for: titles: $titles, episode: $episodeNumber');
      await init();
      
      final enabledExtensions = extensions.where((e) => e.isEnabled && e.cachedCode != null).toList();
      if (enabledExtensions.isEmpty) {
        controller.add([]);
        controller.close();
        return;
      }
      
      // Expand and normalize titles list (removing season suffix variations to search absolute indexers)
      final uniqueTitles = _normalizeSearchTitles(titles);

      // Fetch mappings first to get alternative IDs (AniDB, TVDB, TMDB)
      final mappings = await _fetchMappings(anilistId);
      
      // Extract IDs
      final int? anidbAid = mappings != null ? _toInt(mappings['mappings']?['anidb_id']) : null;
      final int? tvdbId = mappings != null ? _toInt(mappings['mappings']?['thetvdb_id']) : null;
      final int? tmdbId = mappings != null ? _toInt(mappings['mappings']?['themoviedb_id']) : null;
      
      int? anidbEid;
      int? tvdbEId;
      int? targetSeason;
      int? targetAbsoluteEpisode;
      
      if (mappings != null && mappings['episodes'] != null) {
        final rawEpisodes = mappings['episodes'] as Map<String, dynamic>;
        Map<String, dynamic>? targetEpData;
        
        // Scan episodes to find the one matching local episodeNumber
        for (final value in rawEpisodes.values) {
          if (value is Map<String, dynamic>) {
            final localEp = _toInt(value['episodeNumber']) ?? _toInt(value['episode']);
            if (localEp == episodeNumber) {
              targetEpData = value;
              break;
            }
          }
        }
        
        // Fallback to key lookup if scan fails
        if (targetEpData == null) {
          final epKey = episodeNumber.toString();
          if (rawEpisodes[epKey] != null) {
            targetEpData = rawEpisodes[epKey] as Map<String, dynamic>?;
          }
        }
        
        if (targetEpData != null) {
          anidbEid = _toInt(targetEpData['anidbEid']);
          tvdbEId = _toInt(targetEpData['tvdbId']);
          targetSeason = _toInt(targetEpData['seasonNumber']);
          targetAbsoluteEpisode = _toInt(targetEpData['absoluteEpisodeNumber']);
        }
      }
      
      int activeCount = enabledExtensions.length;
      for (final ext in enabledExtensions) {
        _runSingleExtension(
          ext: ext,
          anilistId: anilistId,
          titles: uniqueTitles,
          episodeCount: episodeCount,
          episodeNumber: episodeNumber,
          targetAbsoluteEpisode: targetAbsoluteEpisode,
          anidbAid: anidbAid,
          anidbEid: anidbEid,
          tvdbId: tvdbId,
          tvdbEId: tvdbEId,
          tmdbId: tmdbId,
          media: media,
          resolution: resolution,
          exclusions: exclusions,
          isMovie: isMovie,
        ).timeout(const Duration(seconds: 8)).then((streams) {
          if (streams.isNotEmpty) {
            final filtered = _filterStreams(
              streams: streams,
              targetSeason: targetSeason,
              targetAbsolute: targetAbsoluteEpisode,
              episodeNumber: episodeNumber,
            );
            if (filtered.isNotEmpty) {
              allStreams.addAll(filtered);
              allStreams.sort((a, b) => b.seeders.compareTo(a.seeders));
              if (!controller.isClosed) {
                controller.add(List.from(allStreams));
              }
            }
          }
          activeCount--;
          if (activeCount == 0) {
            if (!controller.isClosed) {
              controller.close();
            }
          }
        }).catchError((err) {
          _logError('Error inside extension ${ext.name} async runner: $err');
          activeCount--;
          if (activeCount == 0) {
            if (!controller.isClosed) {
              controller.close();
            }
          }
        });
      }
    } catch (e, stack) {
      _logError('Global error in searchStreamsAsync: $e\n$stack');
      controller.addError(e);
      controller.close();
    }
  }

  Future<List<TorrentStream>> _runSingleExtension({
    required Extension ext,
    required int anilistId,
    required List<String> titles,
    required int episodeCount,
    required int episodeNumber,
    int? targetAbsoluteEpisode,
    int? anidbAid,
    int? anidbEid,
    int? tvdbId,
    int? tvdbEId,
    int? tmdbId,
    Map<String, dynamic>? media,
    String? resolution,
    List<String>? exclusions,
    bool isMovie = false,
  }) async {
    final cleanResolution = (resolution == 'All' || resolution == 'all') ? '' : (resolution ?? '');
    final JavascriptRuntime runtime = await _createRuntime();
    _setupRuntime(runtime);
    Timer? timer;
    try {
      final preparedCode = _prepareJSCode(ext.cachedCode!);
      await runtime.evaluateAsync(preparedCode);
      
      timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        runtime.executePendingJob();
      });
      
      final method = isMovie ? 'movie' : 'single';
      
      // Pass arguments object
      final runSearchJS = """
        (async () => {
          try {
            if (!globalThis.extension || typeof globalThis.extension.$method !== 'function') {
              return JSON.stringify([]);
            }
            var args = {
              anilistId: $anilistId,
              titles: ${jsonEncode(titles)},
              episodeCount: $episodeCount,
              anidbEid: ${anidbEid ?? 'null'},
              anidbAid: ${anidbAid ?? 'null'},
              episode: ${targetAbsoluteEpisode ?? episodeNumber},
              localEpisode: $episodeNumber,
              absoluteEpisode: ${targetAbsoluteEpisode ?? 'null'},
              resolution: ${jsonEncode(cleanResolution)},
              exclusions: ${jsonEncode(exclusions ?? [])},
              tvdbId: ${tvdbId ?? 'null'},
              tvdbEId: ${tvdbEId ?? 'null'},
              tmdbId: ${tmdbId ?? 'null'},
              media: ${jsonEncode(media ?? {})},
              fetch: globalThis.customFetch
            };
            var options = ${jsonEncode(ext.toJson()['options'] ?? {})};
            var result = await globalThis.extension.$method(args, options);
            return JSON.stringify(result || []);
          } catch (e) {
            return JSON.stringify({ error: e.message || e.toString() });
          }
        })()
      """;
      
      final evalResult = await runtime.evaluateAsync(runSearchJS);
      final resolvedResult = await runtime.handlePromise(evalResult);
      
      if (resolvedResult.isError) {
        _logError('JS Execution Error in extension ${ext.name}: ${resolvedResult.stringResult}');
        return <TorrentStream>[];
      }
      
      final parsed = jsonDecode(resolvedResult.stringResult);
      if (parsed is Map && parsed['error'] != null) {
        _logError('Extension ${ext.name} search returned error: ${parsed['error']}');
        return <TorrentStream>[];
      }
      
      if (parsed is List) {
        return parsed.map((item) => TorrentStream.fromJson(item, ext.name)).toList();
      }
    } catch (e, stack) {
      _logError('Exception running extension ${ext.name}: $e\n$stack');
    } finally {
      timer?.cancel();
      runtime.dispose();
    }
    return <TorrentStream>[];
  }

  List<String> _normalizeSearchTitles(List<String> titles) {
    final List<String> variations = [];
    final seasonRegex = RegExp(
      r'\b(?:s(?:eason)?|part|cour)\s*0*[1-9]\d*\b|\b\d+(?:st|nd|rd|th)\s*(?:season|cour)\b',
      caseSensitive: false,
    );

    for (final rawTitle in titles) {
      // 1. Normalize typographic quotes and characters
      var t = rawTitle
          .replaceAll('’', "'")
          .replaceAll('‘', "'")
          .replaceAll('“', '"')
          .replaceAll('”', '"')
          .trim();
          
      variations.add(t);

      // 2. Normalize Roman numerals
      variations.addAll(_normalizeTitleRomanNumerals(t));

      // 3. Strip season/part/cour suffixes
      if (seasonRegex.hasMatch(t)) {
        final stripped = t.replaceAll(seasonRegex, '').replaceAll(RegExp(r'\s+-\s*$|\s*:\s*$|\s+$'), '').trim();
        if (stripped.isNotEmpty && stripped.length > 2) {
          variations.add(stripped);
          variations.addAll(_normalizeTitleRomanNumerals(stripped));
        }
      }
    }

    // 4. Split by colon / dash to extract main franchise name/base title
    final List<String> currentVariations = List.from(variations);
    for (final v in currentVariations) {
      if (v.contains(':') || v.contains(' -')) {
        final parts = v.split(RegExp(r':| -'));
        final mainTitle = parts[0].trim();
        if (mainTitle.isNotEmpty && mainTitle.length > 2) {
          variations.add(mainTitle);
          variations.addAll(_normalizeTitleRomanNumerals(mainTitle));
        }
      }
    }

    // 5. Clean up punctuation (colons, dashes, apostrophes, commas) to create clean search variants
    final List<String> cleanedVariations = [];
    for (final v in variations) {
      cleanedVariations.add(v);
      
      final clean = v
          .replaceAll(RegExp(r"[:\-\–\—,!?,_]"), ' ')
          .replaceAll(RegExp(r"\s+"), ' ')
          .trim();
      if (clean != v && clean.isNotEmpty) {
        cleanedVariations.add(clean);
      }

      if (v.contains("'")) {
        final noApostrophe = v.replaceAll("'", "");
        cleanedVariations.add(noApostrophe);
        
        final apostropheToSpace = v.replaceAll("'", " ");
        cleanedVariations.add(apostropheToSpace);
      }
    }

    return cleanedVariations
        .map((e) => e.trim())
        .where((e) => e.length > 2)
        .toSet()
        .toList();
  }

  List<String> _normalizeTitleRomanNumerals(String title) {
    final List<String> variations = [title];
    final romanMap = {
      r'\bii\b': '2',
      r'\biii\b': '3',
      r'\biv\b': '4',
      r'\bv\b': '5',
      r'\bvi\b': '6',
      r'\bvii\b': '7',
      r'\bviii\b': '8',
      r'\bix\b': '9',
      r'\bx\b': '10',
    };
    for (final entry in romanMap.entries) {
      final regex = RegExp(entry.key, caseSensitive: false);
      if (regex.hasMatch(title)) {
        final withArabic = title.replaceAllMapped(regex, (m) => entry.value);
        variations.add(withArabic);
        
        final endRegex = RegExp(entry.key + r'\s*$', caseSensitive: false);
        if (endRegex.hasMatch(title)) {
          variations.add(title.replaceAllMapped(endRegex, (m) => 'Season ${entry.value}'));
          variations.add(title.replaceAllMapped(endRegex, (m) => 'S${entry.value}'));
        }
      }
    }
    return variations;
  }

  List<TorrentStream> _filterStreams({
    required List<TorrentStream> streams,
    int? targetSeason,
    int? targetAbsolute,
    required int episodeNumber,
  }) {
    if (targetSeason == null) return streams;

    final List<TorrentStream> result = [];
    final String epLocalStr = episodeNumber.toString().padLeft(2, '0');
    final String? epAbsStr = targetAbsolute?.toString();

    for (final s in streams) {
      final name = s.title.toLowerCase();

      // 1. Season Mismatch Check (e.g. S03 vs S01)
      final seasonMatches = RegExp(r'\bs(?:eason)?\s*0*([1-9]\d*)\b|\b0*([1-9]\d*)st\s*season\b|\b0*([1-9]\d*)nd\s*season\b|\b0*([1-9]\d*)rd\s*season\b|\b0*([1-9]\d*)th\s*season\b').allMatches(name);
      
      bool seasonMismatch = false;
      if (seasonMatches.isNotEmpty) {
        bool hasMatchingSeason = false;
        for (final m in seasonMatches) {
          final matchedSeasonStr = m.group(1) ?? m.group(2);
          if (matchedSeasonStr != null) {
            final matchedSeason = int.tryParse(matchedSeasonStr);
            if (matchedSeason == targetSeason) {
              hasMatchingSeason = true;
              break;
            }
          }
        }
        if (!hasMatchingSeason) {
          seasonMismatch = true;
        }
      }

      if (seasonMismatch) {
        continue;
      }

      // 2. Exclude other seasons' explicit indicators if we are looking for Season 1
      if (targetSeason == 1) {
        final hasOtherSeason = RegExp(r'\bs(?:eason)?\s*0*([2-9]\d*)\b').hasMatch(name);
        if (hasOtherSeason) continue;
      }

      // 3. Absolute vs Local Episode Alignment
      if (targetSeason > 1 && targetAbsolute != null && targetAbsolute != episodeNumber) {
        final bool containsAbsolute = name.contains(RegExp(r'\b0*' + epAbsStr! + r'\b'));
        final bool containsLocalSeason = RegExp(r'\bs(?:eason)?\s*0*' + targetSeason.toString() + r'\b').hasMatch(name) ||
                                         name.contains('s' + targetSeason.toString()) ||
                                         name.contains('s' + targetSeason.toString().padLeft(2, '0'));
        
        if (!containsAbsolute && !containsLocalSeason) {
          final bool containsLocalEp = RegExp(r'\b0*' + episodeNumber.toString() + r'\b').hasMatch(name) ||
                                       name.contains('e' + epLocalStr) ||
                                       name.contains('ep' + epLocalStr);
          if (containsLocalEp) {
            continue; // Exclude Season 1 Episode 4
          }
        }
      }

      result.add(s);
    }
    return result;
  }
}
