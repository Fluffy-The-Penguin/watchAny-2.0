import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─── Model ──────────────────────────────────────────────────────────────────

class StremioAddon {
  final String url; // manifest URL (normalised, always ends with /manifest.json)
  final String id;
  final String name;
  final String description;
  final String version;
  final String icon;
  final List<String> types;
  final List<String> resources; // plain resource names: catalog, meta, stream, subtitles
  final List<Map<String, dynamic>> catalogs;
  final List<String> idPrefixes;
  bool isEnabled;

  StremioAddon({
    required this.url,
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.icon,
    required this.types,
    required this.resources,
    required this.catalogs,
    required this.idPrefixes,
    this.isEnabled = true,
  });

  /// Base URL without /manifest.json — used to build all API endpoint paths
  String get baseUrl {
    if (url.endsWith('/manifest.json')) {
      return url.substring(0, url.length - '/manifest.json'.length);
    }
    // Already without manifest.json
    return url;
  }

  bool supportsResource(String resource) => resources.contains(resource);
  bool supportsType(String type) => types.contains(type);

  /// Returns true if this addon can handle the given item ID.
  /// If idPrefixes is empty, the addon accepts any ID (standard Stremio behaviour).
  bool matchesId(String itemId) {
    if (idPrefixes.isEmpty) return true;
    return idPrefixes.any((p) => itemId.startsWith(p));
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'id': id,
        'name': name,
        'description': description,
        'version': version,
        'icon': icon,
        'types': types,
        'resources': resources,
        'catalogs': catalogs,
        'idPrefixes': idPrefixes,
        'isEnabled': isEnabled,
      };

  factory StremioAddon.fromJson(Map<String, dynamic> json) {
    return StremioAddon(
      url: json['url'] ?? '',
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      version: json['version'] ?? '',
      icon: json['icon'] ?? '',
      types: List<String>.from(json['types'] ?? []),
      resources: List<String>.from(json['resources'] ?? []),
      catalogs: List<Map<String, dynamic>>.from(
        (json['catalogs'] as List?)?.map((c) => Map<String, dynamic>.from(c as Map)) ?? [],
      ),
      idPrefixes: List<String>.from(json['idPrefixes'] ?? []),
      isEnabled: json['isEnabled'] ?? true,
    );
  }
}

// ─── Manifest Parsing Helpers ─────────────────────────────────────────────────

/// Extracts the set of plain resource-name strings from a manifest's "resources" field.
/// Handles both formats:
///   - Simple strings: ["catalog", "meta", "stream"]
///   - Objects:        [{"name":"catalog","types":[...],"idPrefixes":[...]}]
List<String> _parseResources(List raw) {
  final names = <String>{};
  for (final r in raw) {
    if (r is String && r.isNotEmpty) {
      names.add(r.toLowerCase().trim());
    } else if (r is Map) {
      final name = (r['name'] as String? ?? '').toLowerCase().trim();
      if (name.isNotEmpty) names.add(name);
    }
  }
  return names.toList();
}

/// Extracts idPrefixes from both the top-level manifest field and any nested resource objects.
List<String> _parseIdPrefixes(Map<String, dynamic> manifest) {
  final prefixes = <String>{};

  final topLevel = manifest['idPrefixes'];
  if (topLevel is List) {
    prefixes.addAll(topLevel.whereType<String>());
  }

  final resources = manifest['resources'];
  if (resources is List) {
    for (final r in resources) {
      if (r is Map) {
        final nested = r['idPrefixes'];
        if (nested is List) {
          prefixes.addAll(nested.whereType<String>());
        }
      }
    }
  }

  return prefixes.toList();
}

// ─── Service ──────────────────────────────────────────────────────────────────

const _kStorageKey = 'stremio_addons_v2';

class StremioAddonService extends ChangeNotifier {
  static final StremioAddonService _instance = StremioAddonService._internal();
  factory StremioAddonService() => _instance;
  StremioAddonService._internal();

  List<StremioAddon> addons = [];
  bool _isInitialized = false;

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_kStorageKey);
      if (stored != null && stored.isNotEmpty) {
        final List decoded = jsonDecode(stored);
        addons = decoded
            .whereType<Map>()
            .map((j) => StremioAddon.fromJson(Map<String, dynamic>.from(j)))
            .toList();
        debugPrint('[StremioAddonService] Loaded ${addons.length} addons from prefs.');
      } else {
        // First-time launch: pre-install default Stremio addons so app works out of the box
        await _installDefaultAddons();
      }
      _isInitialized = true;
    } catch (e) {
      debugPrint('[StremioAddonService] Error during initialization: $e');
      _isInitialized = true;
    }
  }

  Future<void> _installDefaultAddons() async {
    final defaultAddons = [
      {
        'url': 'https://v3-cinemeta.strem.io/manifest.json',
        'id': 'org.stremio.cinemeta',
        'name': 'Cinemeta',
        'description': 'Official Stremio metadata addon for movies and series.',
        'version': '3.0.4',
        'types': ['movie', 'series'],
        'resources': ['catalog', 'meta'],
        'catalogs': [
          {'id': 'top', 'type': 'movie', 'name': 'Popular Movies'},
          {'id': 'top', 'type': 'series', 'name': 'Popular TV Shows'},
        ],
        'idPrefixes': ['tt'],
      },
      {
        'url': 'https://torrentio.strem.fun/manifest.json',
        'id': 'torrentio.stremio',
        'name': 'Torrentio',
        'description': 'Provides torrent streams from public providers.',
        'version': '0.0.14',
        'types': ['movie', 'series'],
        'resources': ['stream'],
        'catalogs': [],
        'idPrefixes': ['tt'],
      },
      {
        'url': 'https://opensubtitles-v3.strem.io/manifest.json',
        'id': 'opensubtitles-v3',
        'name': 'OpenSubtitles v3',
        'description': 'Official OpenSubtitles v3 addon.',
        'version': '1.0.0',
        'types': ['movie', 'series'],
        'resources': ['subtitles'],
        'catalogs': [],
        'idPrefixes': ['tt'],
      },
    ];

    for (final def in defaultAddons) {
      final String url = def['url'] as String;
      final normalized = normalizeUrl(url);
      if (!addons.any((x) => normalizeUrl(x.url) == normalized)) {
        addons.add(StremioAddon(
          url: normalized,
          id: def['id'] as String,
          name: def['name'] as String,
          description: def['description'] as String,
          version: def['version'] as String,
          icon: '',
          types: List<String>.from(def['types'] as List),
          resources: List<String>.from(def['resources'] as List),
          catalogs: List<Map<String, dynamic>>.from(def['catalogs'] as List),
          idPrefixes: List<String>.from(def['idPrefixes'] as List),
        ));
      }
    }
    await save();
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(addons.map((a) => a.toJson()).toList());
      await prefs.setString(_kStorageKey, jsonStr);
    } catch (e) {
      debugPrint('[StremioAddonService] Error saving addons: $e');
    }
  }

  // ── URL normalisation ─────────────────────────────────────────────────────

  String normalizeUrl(String raw) {
    var u = raw.trim();
    if (u.startsWith('stremio://')) {
      u = u.replaceFirst('stremio://', 'https://');
    }
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    if (!u.endsWith('/manifest.json')) {
      // Remove trailing slash before appending
      if (u.endsWith('/')) u = u.substring(0, u.length - 1);
      u = '$u/manifest.json';
    }
    return u;
  }

  // ── Install ───────────────────────────────────────────────────────────────

  Future<void> installAddon(String manifestUrl) async {
    await init();
    final url = normalizeUrl(manifestUrl);

    if (addons.any((a) => a.url == url)) {
      throw Exception('Addon already installed.');
    }

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch manifest: HTTP ${response.statusCode}');
      }

      final manifest = jsonDecode(response.body) as Map<String, dynamic>;
      final id = manifest['id'] as String? ?? '';
      final name = manifest['name'] as String? ?? '';

      if (id.isEmpty || name.isEmpty) {
        throw Exception('Invalid manifest: "id" and "name" are required.');
      }

      if (addons.any((a) => a.id == id)) {
        throw Exception('Addon with ID "$id" is already installed.');
      }

      // Parse resources (handles both string and object forms)
      final rawResources = manifest['resources'];
      var resources = <String>[];
      if (rawResources is List) {
        resources = _parseResources(rawResources);
      }

      // If the manifest has catalogs but "catalog" is not listed in resources, add it
      final rawCatalogs = manifest['catalogs'];
      if (rawCatalogs is List && rawCatalogs.isNotEmpty && !resources.contains('catalog')) {
        resources = ['catalog', ...resources];
      }

      final newAddon = StremioAddon(
        url: url,
        id: id,
        name: name,
        description: manifest['description'] as String? ?? '',
        version: manifest['version'] as String? ?? '0.0.1',
        icon: manifest['logo'] as String? ?? manifest['icon'] as String? ?? '',
        types: List<String>.from(manifest['types'] ?? []),
        resources: resources,
        catalogs: (rawCatalogs as List?)
                ?.map((c) => Map<String, dynamic>.from(c as Map))
                .toList() ??
            [],
        idPrefixes: _parseIdPrefixes(manifest),
      );

      addons.add(newAddon);
      await save();
      notifyListeners();
      debugPrint('[StremioAddonService] Installed addon: ${newAddon.name} (${newAddon.id})');
      debugPrint('  baseUrl: ${newAddon.baseUrl}');
      debugPrint('  resources: ${newAddon.resources}');
      debugPrint('  idPrefixes: ${newAddon.idPrefixes}');
      debugPrint('  types: ${newAddon.types}');
      debugPrint('  catalogs: ${newAddon.catalogs.length}');
    } catch (e) {
      debugPrint('[StremioAddonService] Error installing addon: $e');
      rethrow;
    }
  }

  // ── Remove / Toggle ───────────────────────────────────────────────────────

  Future<void> removeAddon(String id) async {
    await init();
    addons.removeWhere((a) => a.id == id);
    await save();
    notifyListeners();
    debugPrint('[StremioAddonService] Removed addon with ID: $id');
  }

  Future<void> toggleAddon(String id, bool enabled) async {
    await init();
    for (var addon in addons) {
      if (addon.id == id) {
        addon.isEnabled = enabled;
      }
    }
    await save();
    notifyListeners();
    debugPrint('[StremioAddonService] Toggled addon $id to $enabled');
  }

  // ── Convenience Getters ───────────────────────────────────────────────────

  List<StremioAddon> get catalogAddons =>
      addons.where((a) => a.isEnabled && a.resources.contains('catalog')).toList();

  List<StremioAddon> get metaAddons =>
      addons.where((a) => a.isEnabled && a.resources.contains('meta')).toList();

  List<StremioAddon> get streamAddons =>
      addons.where((a) => a.isEnabled && a.resources.contains('stream')).toList();
}
