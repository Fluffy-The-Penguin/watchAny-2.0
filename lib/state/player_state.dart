import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'library_state.dart';

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

  bool _isSeeking = false;
  bool _isLoadingMedia = false;

  // Getters
  Player? get player => _player;
  VideoController? get controller => _controller;
  bool get isActive => _isActive;
  bool get isMinimized => _isMinimized;
  bool get isFullscreen => _isFullscreen;
  String? get streamUrl => _streamUrl;
  String? get title => _title;
  int? get anilistId => _anilistId;
  List<String>? get titles => _titles;
  int? get episodeCount => _episodeCount;
  int? get episodeNumber => _episodeNumber;
  bool? get isMovie => _isMovie;
  dynamic get media => _media;
  List<dynamic>? get episodes => _episodes;
  Map<int, dynamic>? get tmdbEpisodesMap => _tmdbEpisodesMap;
  bool get isSeeking => _isSeeking;
  bool get isLoadingMedia => _isLoadingMedia;

  // Progress helpers
  PlaybackProgress? getProgress(int animeId, int episodeNumber) {
    return _progressCache['${animeId}_$episodeNumber'];
  }

  Future<void> loadProgressForAnime(int animeId, List<int> episodeNumbers) async {
    final prefs = await SharedPreferences.getInstance();
    for (final epNum in episodeNumbers) {
      final key = '${animeId}_$epNum';
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
    _titles = titles;
    _episodeCount = episodeCount;
    _episodeNumber = episodeNumber;
    _isMovie = isMovie;
    _media = media;
    _episodes = episodes;
    _tmdbEpisodesMap = tmdbEpisodesMap;

    _player = Player();
    _controller = VideoController(_player!);

    _isActive = true;
    _isMinimized = false;
    _isFullscreen = false;
    _isLoadingMedia = true;
    _isSeeking = false;

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

    if (anilistId != null && episodeNumber != null) {
      _addToHistory(anilistId, episodeNumber);
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('playback_stream_${anilistId}_$episodeNumber', streamUrl);
        prefs.setString('playback_title_${anilistId}_$episodeNumber', title);
      });

      // Wait for a valid duration (media loaded) before seeking to resume position
      StreamSubscription<Duration>? tempSub;
      tempSub = _player!.stream.duration.listen((dur) {
        if (dur.inMilliseconds > 0) {
          tempSub?.cancel();
          _isLoadingMedia = false;
          _resumePlayback(anilistId, episodeNumber);
        }
      });
    } else {
      _isLoadingMedia = false;
      _isSeeking = false;
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

    if (_anilistId != null) {
      final id = _anilistId!;
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
    final id = _anilistId;
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

      _checkCompletion(id, ep, pos, dur);
    }
  }

  void _saveMediaMetadata() {
    final id = _anilistId;
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
          'title': _title ?? 'Anime #$id',
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
    
    // Find all continue watching metadata keys: continue_watching_metadata_${anilistId}
    final metadataKeys = keys.where((k) => k.startsWith('continue_watching_metadata_')).toList();
    
    final List<Map<String, dynamic>> items = [];
    
    for (final key in metadataKeys) {
      final animeIdStr = key.replaceFirst('continue_watching_metadata_', '');
      final animeId = int.tryParse(animeIdStr);
      if (animeId == null) continue;
      
      // Find the last episode they were watching
      final timestamp = prefs.getInt('continue_watching_timestamp_$animeId') ?? 0;
      final lastEp = prefs.getInt('continue_watching_last_ep_$animeId') ?? 1;
      
      // Fetch progress for this episode
      final pos = prefs.getInt('playback_pos_${animeId}_$lastEp');
      final dur = prefs.getInt('playback_dur_${animeId}_$lastEp');
      
      if (pos != null && dur != null) {
        final ratio = pos / dur;
        // Only include if they watched less than 90%
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
    
    // Sort items by timestamp descending (most recently watched first)
    items.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    
    // Return only the media maps
    return items.map((item) => item['media']).toList();
  }

  Future<void> _resumePlayback(int animeId, int episodeNumber) async {
    final key = '${animeId}_$episodeNumber';
    final prefs = await SharedPreferences.getInstance();
    final pos = prefs.getInt('playback_pos_$key');
    final dur = prefs.getInt('playback_dur_$key');
    if (pos != null && dur != null) {
      final ratio = pos / dur;
      if (ratio < 0.90) {
        _isSeeking = true;
        notifyListeners();
        await _player?.seek(Duration(milliseconds: pos));
      }
    }
    _isSeeking = false;
    notifyListeners();
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

  void _addToHistory(int anilistId, int episodeNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = 'watched_episodes_$anilistId';
    List<String> list = prefs.getStringList(key) ?? [];
    final String epStr = episodeNumber.toString();
    if (!list.contains(epStr)) {
      list.add(epStr);
      await prefs.setStringList(key, list);
    }
    await prefs.setInt('history_last_watched_timestamp_$anilistId', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<Map<String, dynamic>>> getHistoryList() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> history = [];
    
    final keys = prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('watched_episodes_')) {
        final idStr = key.replaceFirst('watched_episodes_', '');
        final int? id = int.tryParse(idStr);
        if (id == null) continue;
        
        final metadataStr = prefs.getString('continue_watching_metadata_$id');
        if (metadataStr == null) continue;
        
        try {
          final metadata = jsonDecode(metadataStr);
          final timestamp = prefs.getInt('history_last_watched_timestamp_$id') ?? 0;
          final List<String> epStrs = prefs.getStringList(key) ?? [];
          final List<int> eps = epStrs.map((e) => int.parse(e)).toList();
          
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
