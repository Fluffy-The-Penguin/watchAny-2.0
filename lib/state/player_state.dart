import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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

    // Start playing
    _player!.open(Media(streamUrl));

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
    _streamUrl = streamUrl;
    _title = title;
    _episodeNumber = episodeNumber;
    _player?.open(Media(streamUrl));
    notifyListeners();
  }

  void _cleanupPlayer() {
    _player?.dispose();
    _player = null;
    _controller = null;
  }
}
