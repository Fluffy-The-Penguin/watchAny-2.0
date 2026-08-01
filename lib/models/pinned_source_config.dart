import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PinnedSourceConfig {
  final String sourceId;
  bool showPopular;
  bool showLatest;

  PinnedSourceConfig({
    required this.sourceId,
    this.showPopular = true,
    this.showLatest = true,
  });

  Map<String, dynamic> toJson() => {
        'id': sourceId,
        'popular': showPopular,
        'latest': showLatest,
      };

  factory PinnedSourceConfig.fromJson(Map<String, dynamic> json) {
    return PinnedSourceConfig(
      sourceId: json['id']?.toString() ?? '',
      showPopular: json['popular'] ?? true,
      showLatest: json['latest'] ?? true,
    );
  }

  static const String prefKey = 'pinned_manga_sources_config_v2';
  static const String legacyPrefKey = 'pinned_manga_sources';

  static Future<List<PinnedSourceConfig>> loadPins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(prefKey);
      if (jsonList != null && jsonList.isNotEmpty) {
        return jsonList.map((str) {
          final map = jsonDecode(str) as Map<String, dynamic>;
          return PinnedSourceConfig.fromJson(map);
        }).toList();
      }

      // Legacy fallback
      final legacyList = prefs.getStringList(legacyPrefKey) ?? [];
      return legacyList.map((id) => PinnedSourceConfig(sourceId: id, showPopular: true, showLatest: true)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> savePins(List<PinnedSourceConfig> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = configs.map((c) => jsonEncode(c.toJson())).toList();
      await prefs.setStringList(prefKey, jsonList);
      await prefs.setStringList(legacyPrefKey, configs.map((c) => c.sourceId).toList());
    } catch (_) {}
  }
}
