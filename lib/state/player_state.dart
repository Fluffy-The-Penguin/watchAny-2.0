import 'dart:async';
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
      _resumePlayback(anilistId, episodeNumber);
    }

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
      _resumePlayback(_anilistId!, episodeNumber);
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
      });

      _checkCompletion(id, ep, pos, dur);
    }
  }

  Future<void> _resumePlayback(int animeId, int episodeNumber) async {
    final key = '${animeId}_$episodeNumber';
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
}
