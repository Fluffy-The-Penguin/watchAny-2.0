import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class StremioAddon {
  final String url; // base url normalized to https:// without manifest.json
  final String id;
  final String name;
  final String description;
  final String version;
  final String icon;
  final List<String> types;
  final List<String> resources;
  final List<Map<String, dynamic>> catalogs;
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
    this.isEnabled = true,
  });

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
        (json['catalogs'] as List?)?.map((c) => Map<String, dynamic>.from(c)) ?? [],
      ),
      isEnabled: json['isEnabled'] ?? true,
    );
  }
}

class StremioAddonService extends ChangeNotifier {
  static final StremioAddonService _instance = StremioAddonService._internal();
  factory StremioAddonService() => _instance;
  StremioAddonService._internal();

  List<StremioAddon> addons = [];
  bool _isInitialized = false;

  File get _storageFile {
    return File('C:\\Users\\aryan\\OneDrive\\Documents\\watchAny 2.0\\stremio_addons.json');
  }

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      if (await _storageFile.exists()) {
        final content = await _storageFile.readAsString();
        final List decoded = jsonDecode(content);
        addons = decoded.map((json) => StremioAddon.fromJson(json)).toList();
        debugPrint('[StremioAddonService] Loaded ${addons.length} addons from storage.');
      } else {
        await _seedDefaultAddons();
      }
      _isInitialized = true;
    } catch (e) {
      debugPrint('[StremioAddonService] Error during initialization: $e');
      await _seedDefaultAddons();
      _isInitialized = true;
    }
  }

  Future<void> _seedDefaultAddons() async {
    debugPrint('[StremioAddonService] No default addons seeded.');
    addons = [];
    await save();
  }

  Future<void> save() async {
    try {
      final jsonStr = jsonEncode(addons.map((a) => a.toJson()).toList());
      await _storageFile.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('[StremioAddonService] Error saving addons: $e');
    }
  }

  String normalizeUrl(String url) {
    var u = url.trim();
    if (u.startsWith('stremio://')) {
      u = u.replaceFirst('stremio://', 'https://');
    }
    if (!u.startsWith('http')) {
      u = 'https://$u';
    }
    return u;
  }

  Future<void> installAddon(String manifestUrl) async {
    await init();
    final url = normalizeUrl(manifestUrl);
    
    // Check if already installed
    if (addons.any((a) => a.url == url)) {
      throw Exception('Addon already installed.');
    }

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch manifest: HTTP ${response.statusCode}');
      }

      final manifest = jsonDecode(response.body) as Map<String, dynamic>;
      final id = manifest['id'] as String? ?? '';
      final name = manifest['name'] as String? ?? '';
      
      if (id.isEmpty || name.isEmpty) {
        throw Exception('Invalid manifest: "id" and "name" are required.');
      }

      // Check if ID is already installed
      if (addons.any((a) => a.id == id)) {
        throw Exception('Addon with ID "$id" is already installed.');
      }

      final newAddon = StremioAddon(
        url: url,
        id: id,
        name: name,
        description: manifest['description'] as String? ?? '',
        version: manifest['version'] as String? ?? '0.0.1',
        icon: manifest['logo'] as String? ?? manifest['icon'] as String? ?? '',
        types: List<String>.from(manifest['types'] ?? []),
        resources: (manifest['resources'] as List?)?.map((r) {
              if (r is Map) {
                return r['name'] as String? ?? '';
              }
              return r as String? ?? '';
            }).where((r) => r.isNotEmpty).toList() ??
            [],
        catalogs: List<Map<String, dynamic>>.from(
          (manifest['catalogs'] as List?)?.map((c) => Map<String, dynamic>.from(c)) ?? [],
        ),
      );

      addons.add(newAddon);
      await save();
      notifyListeners();
      debugPrint('[StremioAddonService] Installed addon: ${newAddon.name} (${newAddon.id})');
    } catch (e) {
      debugPrint('[StremioAddonService] Error installing addon: $e');
      rethrow;
    }
  }

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
}
