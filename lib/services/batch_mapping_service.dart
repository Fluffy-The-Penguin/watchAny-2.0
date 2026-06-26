import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class BatchMappingService {
  static final BatchMappingService _instance = BatchMappingService._internal();
  factory BatchMappingService() => _instance;
  BatchMappingService._internal();

  final File _file = File('C:\\Users\\aryan\\OneDrive\\Documents\\watchAny 2.0\\batch_mappings.json');
  Map<String, dynamic> _mappings = {};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      if (await _file.exists()) {
        final content = await _file.readAsString();
        _mappings = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error loading batch mappings: $e');
    }
    _initialized = true;
  }

  Future<void> saveMapping({
    required int anilistId,
    required String torrentLink,
    required String torrentHash,
    required String torrentTitle,
    required Map<int, int> episodeToIndex,
  }) async {
    await init();
    
    final idStr = anilistId.toString();
    _mappings[idStr] = {
      'torrentLink': torrentLink,
      'torrentHash': torrentHash,
      'torrentTitle': torrentTitle,
      'episodes': episodeToIndex.map((k, v) => MapEntry(k.toString(), v)),
    };

    try {
      await _file.writeAsString(jsonEncode(_mappings));
    } catch (e) {
      debugPrint('Error saving batch mappings: $e');
    }
  }

  Map<String, dynamic>? getMapping(int anilistId, int episodeNumber) {
    if (!_initialized) {
      try {
        if (_file.existsSync()) {
          final content = _file.readAsStringSync();
          _mappings = jsonDecode(content) as Map<String, dynamic>;
        }
      } catch (e) {
        debugPrint('Error loading batch mappings synchronously: $e');
      }
      _initialized = true;
    }

    final idStr = anilistId.toString();
    final data = _mappings[idStr];
    if (data == null) return null;

    final eps = data['episodes'] as Map<String, dynamic>?;
    if (eps == null) return null;

    final epKey = episodeNumber.toString();
    final fileIndex = eps[epKey];
    if (fileIndex == null) return null;

    return {
      'torrentLink': data['torrentLink'] as String,
      'torrentHash': data['torrentHash'] as String,
      'torrentTitle': data['torrentTitle'] as String,
      'fileIndex': fileIndex as int,
    };
  }
}
