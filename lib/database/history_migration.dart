import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as drift;
import 'app_database.dart' as db;

class HistoryMigration {
  static const String _migrationFlag = 'sqlite_history_migration_v2_done';

  static Future<void> runIfNeeded(db.AppDatabase database) async {
    final prefs = await SharedPreferences.getInstance();
    final bool done = prefs.getBool(_migrationFlag) ?? false;
    if (done) return;

    try {
      // 1. Migrate watch_history_flat_records
      final String? historyJsonStr = prefs.getString('watch_history_flat_records');
      if (historyJsonStr != null) {
        try {
          final List<dynamic> decoded = jsonDecode(historyJsonStr);
          for (var item in decoded) {
            if (item is! Map) continue;
            final map = Map<String, dynamic>.from(item);

            final String mediaId = map['id']?.toString() ?? '';
            if (mediaId.isEmpty) continue;

            final bool isAnime = map['isAnime'] == true;
            final bool isManga = map['isManga'] == true;
            final Map<String, dynamic> media = Map<String, dynamic>.from(map['media'] ?? {});

            // Extract title cleanly
            String titleStr = 'Unknown';
            final rawTitle = media['title'];
            if (rawTitle is String) {
              titleStr = rawTitle;
            } else if (rawTitle is Map) {
              titleStr = rawTitle['userPreferred'] ?? rawTitle['english'] ?? rawTitle['romaji'] ?? rawTitle['native'] ?? 'Unknown';
            }

            // Extract coverImage cleanly
            String coverUrl = '';
            final rawCover = media['coverImage'];
            if (rawCover is String) {
              coverUrl = rawCover;
            } else if (rawCover is Map) {
              coverUrl = rawCover['large'] ?? rawCover['medium'] ?? '';
            }

            final List<dynamic> epList = map['episodes'] ?? [];
            final List<int> episodes = epList.map((e) => int.tryParse(e.toString()) ?? 0).where((e) => e > 0).toList();

            await database.into(database.watchHistory).insertOnConflictUpdate(
              db.WatchHistoryCompanion.insert(
                mediaId: mediaId,
                isAnime: isAnime ? 1 : 0,
                isManga: isManga ? 1 : 0,
                title: titleStr,
                coverImage: coverUrl,
                format: media['format']?.toString() ?? 'UNKNOWN',
                averageScore: drift.Value((media['averageScore'] as num?)?.toDouble() ?? 0.0),
                totalEpisodes: drift.Value((media['episodes'] as num?)?.toInt() ?? 0),
                mediaTypeHint: drift.Value(media['type']?.toString() ?? ''),
                episodes: jsonEncode(episodes),
                timestamp: (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
              ),
            );
          }
        } catch (_) {}
      }

      // 2. Migrate continue_watching metadata & timestamps
      final keys = prefs.getKeys();
      for (String key in keys) {
        if (key.endsWith('_continue_watching_metadata_') || key.contains('_continue_watching_metadata_')) {
          final parts = key.split('_continue_watching_metadata_');
          final String prefix = parts.isNotEmpty ? '${parts[0]}_' : '';
          final String mediaId = parts.length > 1 ? parts[1] : '';

          if (mediaId.isNotEmpty) {
            final String? metadataStr = prefs.getString(key);
            final int timestamp = prefs.getInt('${prefix}continue_watching_timestamp_$mediaId') ?? 0;
            final int lastEp = prefs.getInt('${prefix}continue_watching_last_ep_$mediaId') ?? 1;

            if (metadataStr != null) {
              await database.into(database.continueWatching).insertOnConflictUpdate(
                db.ContinueWatchingCompanion.insert(
                  mediaId: mediaId,
                  prefix: prefix,
                  metadataJson: metadataStr,
                  lastEpisode: lastEp,
                  timestamp: timestamp > 0 ? timestamp : DateTime.now().millisecondsSinceEpoch,
                ),
              );
            }
          }
        }
      }

      // 3. Migrate playback positions & durations
      for (String key in keys) {
        if (key.contains('_playback_pos_')) {
          final parts = key.split('_playback_pos_');
          final String prefix = '${parts[0]}_';
          final String rest = parts[1]; // <mediaId>_<ep>
          final lastUnderscore = rest.lastIndexOf('_');
          if (lastUnderscore != -1) {
            final mediaId = rest.substring(0, lastUnderscore);
            final ep = int.tryParse(rest.substring(lastUnderscore + 1)) ?? 1;

            final int pos = prefs.getInt(key) ?? 0;
            final int dur = prefs.getInt('${prefix}playback_dur_${mediaId}_$ep') ?? 0;

            if (pos > 0) {
              await database.into(database.playbackPositions).insertOnConflictUpdate(
                db.PlaybackPositionsCompanion.insert(
                  mediaId: mediaId,
                  episode: ep,
                  prefix: prefix,
                  positionMs: pos,
                  durationMs: dur,
                  savedAt: DateTime.now().millisecondsSinceEpoch,
                ),
              );
            }
          }
        }
      }

      // Mark migration as completed
      await prefs.setBool(_migrationFlag, true);

      // Clean up old prefs keys to reclaim space
      await prefs.remove('watch_history_flat_records');
      for (String k in keys) {
        if (k.contains('_continue_watching_') || k.contains('_playback_pos_') || k.contains('_playback_dur_') || k.startsWith('watched_episodes_') || k.startsWith('history_last_watched_timestamp_')) {
          await prefs.remove(k);
        }
      }
    } catch (_) {}
  }
}
