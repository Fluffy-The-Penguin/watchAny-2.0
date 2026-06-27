import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'library_state.dart';
import 'app_settings.dart';

class PlaybackProgress {
  final int position; // in milliseconds
  final int duration; // in milliseconds

  PlaybackProgress({required this.position, required this.duration});
}

class PlayerState extends ChangeNotifier {
  static final PlayerState _instance = PlayerState._internal();
  factory PlayerState() => _instance;
  PlayerState._internal();

  Player? _player;
  VideoController? _controller;

  bool _isActive = false;
  bool _isMinimized = false;
  bool _isFullscreen = false;

  String? _streamUrl;
  String? _title;
  int? _anilistId;
  String? _movieId;
  List<String>? _titles;
  int? _episodeCount;
  int? _episodeNumber;
  bool? _isMovie;
  dynamic _media;
  List<dynamic>? _episodes;
  Map<int, dynamic>? _tmdbEpisodesMap;

  // Progress Tracking Subscriptions and variables
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  DateTime? _lastSaveTime;

  // Cache: key is "animeId_episodeNumber", value is PlaybackProgress
  final Map<String, PlaybackProgress> _progressCache = {};

  // Getters
  Player? get player => _player;
  VideoController? get controller => _controller;
  bool get isActive => _isActive;
  bool get isMinimized => _isMinimized;
  bool get isFullscreen => _isFullscreen;
  String? get streamUrl => _streamUrl;
  String? get title => _title;
  int? get anilistId => _anilistId;
  String? get movieId => _movieId;
  List<String>? get titles => _titles;
  int? get episodeCount => _episodeCount;
  int? get episodeNumber => _episodeNumber;
  bool? get isMovie => _isMovie;
  dynamic get media => _media;
  List<dynamic>? get episodes => _episodes;
  Map<int, dynamic>? get tmdbEpisodesMap => _tmdbEpisodesMap;

  // Progress helpers
  PlaybackProgress? getProgress(dynamic id, int episodeNumber) {
    return _progressCache['${id}_$episodeNumber'];
  }

  Future<void> loadProgressForAnime(dynamic id, List<int> episodeNumbers) async {
    final prefs = await SharedPreferences.getInstance();
    for (final epNum in episodeNumbers) {
      final key = '${id}_$epNum';
      final pos = prefs.getInt('playback_pos_$key');
      final dur = prefs.getInt('playback_dur_$key');
      if (pos != null && dur != null) {
        _progressCache[key] = PlaybackProgress(position: pos, duration: dur);
      }
    }
    notifyListeners();
  }

  void startPlayback({
    required String streamUrl,
    required String title,
    int? anilistId,
    String? movieId,
    List<String>? titles,
    int? episodeCount,
    int? episodeNumber,
    bool? isMovie,
    dynamic media,
    List<dynamic>? episodes,
    Map<int, dynamic>? tmdbEpisodesMap,
  }) {
    _cleanupPlayer();

    _streamUrl = streamUrl;
    _title = title;
    _anilistId = anilistId;
    _movieId = movieId;
    _titles = titles;
    _episodeCount = episodeCount;
    _episodeNumber = episodeNumber;
    _isMovie = isMovie;
    _media = media;
    _episodes = episodes;
    _tmdbEpisodesMap = tmdbEpisodesMap;

    _player = Player();

    try {
      final nativePlayer = _player!.platform as NativePlayer;
      nativePlayer.setProperty('hr-seek', 'no');
      nativePlayer.setProperty('demuxer-max-bytes', '52428800'); // 50MB max bytes cache
      nativePlayer.setProperty('demuxer-readahead-secs', '20'); // 20s readahead
    } catch (e) {
      debugPrint('[PlayerState] Error setting player performance options: $e');
    }

    _controller = VideoController(
      _player!,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: AppSettings().hardwareAccelerationEnabled,
      ),
    );

    _isActive = true;
    _isMinimized = false;
    _isFullscreen = false;

    // Set up listeners for progress saving
    _currentPosition = Duration.zero;
    _currentDuration = Duration.zero;
    _lastSaveTime = null;

    _positionSubscription = _player!.stream.position.listen((pos) {
      _currentPosition = pos;
      _onPositionChanged();
    });

    _durationSubscription = _player!.stream.duration.listen((dur) {
      _currentDuration = dur;
    });

    _playingSubscription = _player!.stream.playing.listen((isPlaying) {
      if (!isPlaying) {
        _saveCurrentProgress();
      }
    });

    // Start playing
    _player!.open(Media(streamUrl));

    final id = anilistId?.toString() ?? movieId;
    if (id != null && episodeNumber != null) {
      _resumePlayback(id, episodeNumber);
      _addToHistory(id, episodeNumber);
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('playback_stream_${id}_$episodeNumber', streamUrl);
        prefs.setString('playback_title_${id}_$episodeNumber', title);
      });
    }

    _saveMediaMetadata();

    notifyListeners();
  }

  void enterFullscreen() {
    if (_isActive && !_isFullscreen) {
      _isFullscreen = true;
      notifyListeners();
    }
  }

  void exitFullscreen() {
    if (_isFullscreen) {
      _isFullscreen = false;
      notifyListeners();
    }
  }

  void minimize() {
    if (_isActive && !_isMinimized) {
      _isMinimized = true;
      _isFullscreen = false;
      notifyListeners();
    }
  }

  void maximize() {
    if (_isActive && _isMinimized) {
      _isMinimized = false;
      notifyListeners();
    }
  }

  void stopPlayback() {
    _cleanupPlayer();
    _isActive = false;
    _isMinimized = false;
    _isFullscreen = false;
    notifyListeners();
  }

  void updateActiveEpisode({
    required String streamUrl,
    required String title,
    required int episodeNumber,
  }) {
    // Save current progress before switching episode
    _saveCurrentProgress();

    _streamUrl = streamUrl;
    _title = title;
    _episodeNumber = episodeNumber;

    // Reset current position trackers
    _currentPosition = Duration.zero;
    _currentDuration = Duration.zero;
    _lastSaveTime = null;

    _player?.open(Media(streamUrl));

    final id = _anilistId?.toString() ?? _movieId;
    if (id != null) {
      _resumePlayback(id, episodeNumber);
      _addToHistory(id, episodeNumber);
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('playback_stream_${id}_$episodeNumber', streamUrl);
        prefs.setString('playback_title_${id}_$episodeNumber', title);
      });
    }

    notifyListeners();
  }

  void _onPositionChanged() {
    final now = DateTime.now();
    if (_lastSaveTime == null || now.difference(_lastSaveTime!) >= const Duration(seconds: 5)) {
      _saveCurrentProgress();
    }
  }

  void _saveCurrentProgress() {
    final id = _anilistId?.toString() ?? _movieId;
    final ep = _episodeNumber;
    final pos = _currentPosition.inMilliseconds;
    final dur = _currentDuration.inMilliseconds;

    if (id != null && ep != null && pos > 0 && dur > 0) {
      _lastSaveTime = DateTime.now();
      final key = '${id}_$ep';
      _progressCache[key] = PlaybackProgress(position: pos, duration: dur);
      notifyListeners();

      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('playback_pos_$key', pos);
        prefs.setInt('playback_dur_$key', dur);
        prefs.setInt('continue_watching_timestamp_$id', DateTime.now().millisecondsSinceEpoch);
        prefs.setInt('continue_watching_last_ep_$id', ep);
      });

      if (_anilistId != null) {
        _checkCompletion(_anilistId!, ep, pos, dur);
      }
    }
  }

  void _saveMediaMetadata() {
    final id = _anilistId?.toString() ?? _movieId;
    if (id != null) {
      final med = _media;
      Map<String, dynamic> lightweightMedia;
      if (med != null && med is Map) {
        lightweightMedia = {
          'id': id,
          'title': med['title'],
          'coverImage': med['coverImage'],
          'averageScore': med['averageScore'],
          'format': med['format'],
          'episodes': med['episodes'] ?? _episodeCount,
        };
      } else {
        lightweightMedia = {
          'id': id,
          'title': _title ?? 'Media #$id',
          'coverImage': '',
          'averageScore': 0.0,
          'format': (_isMovie == true) ? 'MOVIE' : 'TV',
          'episodes': _episodeCount,
        };
      }
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('continue_watching_metadata_$id', jsonEncode(lightweightMedia));
      });
    }
  }

  static Future<List<dynamic>> getContinueWatchingList() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    final metadataKeys = keys.where((k) => k.startsWith('continue_watching_metadata_')).toList();
    final List<Map<String, dynamic>> items = [];
    
    for (final key in metadataKeys) {
      final id = key.replaceFirst('continue_watching_metadata_', '');
      final timestamp = prefs.getInt('continue_watching_timestamp_$id') ?? 0;
      final lastEp = prefs.getInt('continue_watching_last_ep_$id') ?? 1;
      
      final pos = prefs.getInt('playback_pos_${id}_$lastEp');
      final dur = prefs.getInt('playback_dur_${id}_$lastEp');
      
      if (pos != null && dur != null) {
        final ratio = pos / dur;
        if (ratio > 0.001 && ratio < 0.90) {
          final metadataJson = prefs.getString(key);
          if (metadataJson != null) {
            try {
              final mediaMap = jsonDecode(metadataJson) as Map<String, dynamic>;
              items.add({
                'media': mediaMap,
                'timestamp': timestamp,
              });
            } catch (_) {}
          }
        }
      }
    }
    
    items.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    return items.map((item) => item['media']).toList();
  }

  Future<void> _resumePlayback(String id, int episodeNumber) async {
    final key = '${id}_$episodeNumber';
    final prefs = await SharedPreferences.getInstance();
    final pos = prefs.getInt('playback_pos_$key');
    final dur = prefs.getInt('playback_dur_$key');
    if (pos != null && dur != null) {
      final ratio = pos / dur;
      if (ratio < 0.90) {
        await _player?.seek(Duration(milliseconds: pos));
      }
    }
  }

  void _checkCompletion(int id, int ep, int pos, int dur) {
    final ratio = pos / dur;
    if (ratio >= 0.90) {
      final library = LibraryState();
      final item = library.getItem(id, 'anime');
      if (item != null) {
        if (ep > item.watchedEpisodes) {
          library.saveItem(
            id: item.id,
            mode: item.mode,
            format: item.format,
            libraryStatus: item.libraryStatus,
            rating: item.rating,
            watchedEpisodes: ep,
            totalEpisodes: item.totalEpisodes,
          );
        }
      } else {
        // If not in library, add under 'watching' status automatically
        String formatVal = 'TV';
        if (_isMovie == true) {
          formatVal = 'MOVIE';
        } else if (_media != null && _media is Map && _media['format'] != null) {
          formatVal = _media['format'];
        }

        library.saveItem(
          id: id,
          mode: 'anime',
          format: formatVal,
          libraryStatus: 'watching',
          rating: 0.0,
          watchedEpisodes: ep,
          totalEpisodes: _episodeCount,
        );
      }
    }
  }

  void _cleanupPlayer() {
    _saveCurrentProgress(); // Save progress before disposing
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _durationSubscription?.cancel();
    _durationSubscription = null;
    _playingSubscription?.cancel();
    _playingSubscription = null;
    _player?.dispose();
    _player = null;
    _controller = null;
  }

  void _addToHistory(String id, int episodeNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = 'watched_episodes_$id';
    List<String> list = prefs.getStringList(key) ?? [];
    final String epStr = episodeNumber.toString();
    if (!list.contains(epStr)) {
      list.add(epStr);
      await prefs.setStringList(key, list);
    }
    await prefs.setInt('history_last_watched_timestamp_$id', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<Map<String, dynamic>>> getHistoryList() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> history = [];
    
    final keys = prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('watched_episodes_')) {
        final id = key.replaceFirst('watched_episodes_', '');
        final metadataStr = prefs.getString('continue_watching_metadata_$id');
        if (metadataStr == null) continue;
        
        try {
          final metadata = jsonDecode(metadataStr);
          final timestamp = prefs.getInt('history_last_watched_timestamp_$id') ?? 0;
          final List<String> epStrs = prefs.getStringList(key) ?? [];
          final List<int> eps = epStrs.map((e) => int.tryParse(e) ?? 0).toList();
          
          history.add({
            'id': id,
            'media': metadata,
            'episodes': eps,
            'timestamp': timestamp,
          });
        } catch (_) {}
      }
    }
    
    history.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
    return history;
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('watched_episodes_') || key.startsWith('history_last_watched_timestamp_')) {
        await prefs.remove(key);
      }
    }
  }
}
