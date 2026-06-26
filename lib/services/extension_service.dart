import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;

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

  void _logError(String message) {
    try {
      final logFile = File('C:\\Users\\aryan\\OneDrive\\Documents\\watchAny 2.0\\extension_debug.log');
      logFile.writeAsStringSync('${DateTime.now().toIso8601String()}: $message\n', mode: FileMode.append);
    } catch (_) {}
  }

  List<ExtensionRepo> repos = [];
  List<Extension> extensions = [];
  bool _isInitialized = false;
  Future<void>? _initFuture;

  File get _storageFile {
    return File('C:\\Users\\aryan\\OneDrive\\Documents\\watchAny 2.0\\extensions_storage.json');
  }

  // Initialize and load saved state, seeding default repos if empty
  Future<void> init() async {
    if (_isInitialized) return;
    _initFuture ??= _doInit();
    return _initFuture;
  }

  Future<void> _doInit() async {
    try {
      debugPrint('[ExtensionService] Warming up Javascript engine...');
      // Initialize a dummy JS runtime to trigger native libraries cold start setup
      final runtime = await _createRuntime();
      runtime.dispose();
      debugPrint('[ExtensionService] Javascript engine warmed up successfully.');

      if (await _storageFile.exists()) {
        final content = await _storageFile.readAsString();
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
    } catch (e) {
      debugPrint('Error initializing ExtensionService: $e');
    }
  }

  // Save current repos and extensions to disk
  Future<void> save() async {
    try {
      final data = {
        'repos': repos.map((r) => r.toJson()).toList(),
        'extensions': extensions.map((e) => e.toJson()).toList(),
      };
      await _storageFile.writeAsString(jsonEncode(data));
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
      globalThis.fetch = function(url, options) {
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
    
    return polyfills + "\n" + transformedCode;
  }

  void _setupRuntime(JavascriptRuntime runtime) {
    runtime.onMessage('fetchChannel', (dynamic message) async {
      int? id;
      try {
        final Map<String, dynamic> req = jsonDecode(message);
        id = req['id'];
        final String url = req['url'];
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
          response = await _httpClient.post(Uri.parse(url), headers: stringHeaders, body: body);
        } else {
          response = await _httpClient.get(Uri.parse(url), headers: stringHeaders);
        }
        
        final responseData = {
          'statusCode': response.statusCode,
          'headers': response.headers,
          'body': response.body,
        };
        
        runtime.evaluate("globalThis.resolveFetch($id, ${jsonEncode(responseData)});");
        runtime.executePendingJob(); // Run microtasks immediately!
      } catch (e) {
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
      await init();
      
      final enabledExtensions = extensions.where((e) => e.isEnabled && e.cachedCode != null).toList();
      if (enabledExtensions.isEmpty) {
        controller.add([]);
        controller.close();
        return;
      }
      
      // Fetch mappings first to get alternative IDs (AniDB, TVDB, TMDB)
      final mappings = await _fetchMappings(anilistId);
      
      // Extract IDs
      final int? anidbAid = mappings != null ? _toInt(mappings['mappings']?['anidb_id']) : null;
      final int? tvdbId = mappings != null ? _toInt(mappings['mappings']?['thetvdb_id']) : null;
      final int? tmdbId = mappings != null ? _toInt(mappings['mappings']?['themoviedb_id']) : null;
      
      int? anidbEid;
      int? tvdbEId;
      
      if (mappings != null && mappings['episodes'] != null) {
        final epKey = episodeNumber.toString();
        final epData = mappings['episodes'][epKey];
        if (epData != null) {
          anidbEid = _toInt(epData['anidbEid']);
          tvdbEId = _toInt(epData['tvdbId']);
        }
      }
      
      int activeCount = enabledExtensions.length;
      
      for (final ext in enabledExtensions) {
        _runSingleExtension(
          ext: ext,
          anilistId: anilistId,
          titles: titles,
          episodeCount: episodeCount,
          episodeNumber: episodeNumber,
          anidbAid: anidbAid,
          anidbEid: anidbEid,
          tvdbId: tvdbId,
          tvdbEId: tvdbEId,
          tmdbId: tmdbId,
          media: media,
          resolution: resolution,
          exclusions: exclusions,
          isMovie: isMovie,
        ).then((streams) {
          if (streams.isNotEmpty) {
            allStreams.addAll(streams);
            allStreams.sort((a, b) => b.seeders.compareTo(a.seeders));
            controller.add(List.from(allStreams));
          }
          activeCount--;
          if (activeCount == 0) {
            controller.close();
          }
        }).catchError((err) {
          _logError('Error inside extension ${ext.name} async runner: $err');
          activeCount--;
          if (activeCount == 0) {
            controller.close();
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
              episode: $episodeNumber,
              resolution: ${jsonEncode(resolution ?? '')},
              exclusions: ${jsonEncode(exclusions ?? [])},
              tvdbId: ${tvdbId ?? 'null'},
              tvdbEId: ${tvdbEId ?? 'null'},
              tmdbId: ${tmdbId ?? 'null'},
              media: ${jsonEncode(media ?? {})},
              fetch: globalThis.fetch
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
}
