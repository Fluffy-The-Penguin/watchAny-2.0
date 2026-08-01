import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../services/aniskip_service.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart' as media_kit_video_controls;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/video_proxy_service.dart';
import 'library_state.dart';
import 'app_settings.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../services/hstream_service.dart';
import '../services/log_service.dart';
import '../services/torrserver_service.dart';
import '../database/app_database.dart' as db;
import 'package:drift/drift.dart' as drift;

class PlaybackProgress {
  final int position; // in milliseconds
  final int duration; // in milliseconds

  PlaybackProgress({required this.position, required this.duration});
}

class PlayerState extends ChangeNotifier {
  static final PlayerState _instance = PlayerState._internal();
  factory PlayerState() => _instance;
  PlayerState._internal();

  final db.AppDatabase _db = db.AppDatabase();

  Player? _player;
  VideoController? _controller;

  bool _isActive = false;
  bool _isMinimized = false;
  bool _isFullscreen = false;

  Offset _miniPlayerOffset = Offset.zero;
  bool _isDraggingMiniPlayer = false;


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
  List<HstreamSource>? _hstreamSources;
  List<Map<String, String>>? _hstreamSubtitleTracks; // VTT subtitle tracks from HStream
  StreamSubscription? _tracksSubscription;            // fires once after media opens to load subtitle
  Map<String, String>? _headers;

  BoxFit _videoFit = BoxFit.contain;
  String _fitName = 'Fit (Default)';
  bool _showFitToastFlag = false;
  Timer? _fitToastTimer;

  bool _showTorrentDashboard = false;
  bool _showSkipButton = false;
  SkipInterval? _activeSkipInterval;
  bool _isQualityEnhanced = false;
  bool _showAppBar = true;

  double _torrentSpeedBytes = 0.0;
  int _torrentActivePeers = 0;
  int _torrentTotalPeers = 0;
  final List<double> _torrentSpeedHistory = [];

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
  Offset get miniPlayerOffset => _miniPlayerOffset;
  bool get isDraggingMiniPlayer => _isDraggingMiniPlayer;
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
  List<HstreamSource>? get hstreamSources => _hstreamSources;
  List<Map<String, String>>? get hstreamSubtitleTracks => _hstreamSubtitleTracks;

  BoxFit get videoFit => _videoFit;
  String get fitName => _fitName;
  bool get showFitToastFlag => _showFitToastFlag;

  bool get showTorrentDashboard => _showTorrentDashboard;
  bool get showSkipButton => _showSkipButton;
  SkipInterval? get activeSkipInterval => _activeSkipInterval;
  bool get isQualityEnhanced => _isQualityEnhanced;

  void setShowTorrentDashboard(bool show) {
    _showTorrentDashboard = show;
    notifyListeners();
  }

  void setShowSkipButton(bool show) {
    _showSkipButton = show;
    notifyListeners();
  }

  void setActiveSkipInterval(SkipInterval? interval) {
    _activeSkipInterval = interval;
    notifyListeners();
  }

  void setIsQualityEnhanced(bool enhanced) {
    _isQualityEnhanced = enhanced;
    notifyListeners();
  }

  bool get showAppBar => _showAppBar;
  void setShowAppBar(bool show) {
    _showAppBar = show;
    notifyListeners();
  }

  double get torrentSpeedBytes => _torrentSpeedBytes;
  int get torrentActivePeers => _torrentActivePeers;
  int get torrentTotalPeers => _torrentTotalPeers;
  List<double> get torrentSpeedHistory => _torrentSpeedHistory;

  void updateTorrentStats(double speed, int active, int total) {
    _torrentSpeedBytes = speed;
    _torrentActivePeers = active;
    _torrentTotalPeers = total;
    
    final double mbps = speed / (1024.0 * 1024.0);
    _torrentSpeedHistory.add(mbps);
    if (_torrentSpeedHistory.length > 30) {
      _torrentSpeedHistory.removeAt(0);
    }
    notifyListeners();
  }

  void clearTorrentStats() {
    _torrentSpeedBytes = 0.0;
    _torrentActivePeers = 0;
    _torrentTotalPeers = 0;
    _torrentSpeedHistory.clear();
    notifyListeners();
  }

  void cycleVideoFit([BuildContext? context]) {
    if (_videoFit == BoxFit.contain) {
      _videoFit = BoxFit.fill;
      _showFitToast('Stretch (16:9)');
    } else if (_videoFit == BoxFit.fill) {
      _videoFit = BoxFit.cover;
      _showFitToast('Zoom / Fill');
    } else {
      _videoFit = BoxFit.contain;
      _showFitToast('Fit (Default)');
    }
    
    if (context != null) {
      try {
        final videoViewParametersNotifier = media_kit_video_controls.VideoStateInheritedWidget.maybeOf(context)?.videoViewParametersNotifier;
        if (videoViewParametersNotifier != null) {
          videoViewParametersNotifier.value = videoViewParametersNotifier.value.copyWith(fit: _videoFit);
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  void _showFitToast(String name) {
    _fitToastTimer?.cancel();
    _fitName = name;
    _showFitToastFlag = true;
    notifyListeners();

    _fitToastTimer = Timer(const Duration(seconds: 2), () {
      _showFitToastFlag = false;
      notifyListeners();
    });
  }

  // Progress helpers
  PlaybackProgress? getProgress(dynamic id, int episodeNumber) {
    return _progressCache['${id}_$episodeNumber'];
  }

  Future<void> loadProgressForAnime(dynamic id, List<int> episodeNumbers) async {
    final mediaId = id.toString();
    final query = _db.select(_db.playbackPositions)
      ..where((tbl) => tbl.mediaId.equals(mediaId) & tbl.episode.isIn(episodeNumbers));
    final rows = await query.get();
    for (final row in rows) {
      final key = '${mediaId}_${row.episode}';
      _progressCache[key] = PlaybackProgress(position: row.positionMs, duration: row.durationMs);
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
    List<HstreamSource>? hstreamSources,
    List<Map<String, String>>? hstreamSubtitleTracks,
    Map<String, String>? headers,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    _cleanupPlayer();

    _videoFit = BoxFit.contain;
    _fitName = 'Fit (Default)';
    _showFitToastFlag = false;
    _fitToastTimer?.cancel();

    _showTorrentDashboard = false;
    _showSkipButton = false;
    _activeSkipInterval = null;
    _isQualityEnhanced = false;
    _showAppBar = true;
    _torrentSpeedBytes = 0.0;
    _torrentActivePeers = 0;
    _torrentTotalPeers = 0;
    _torrentSpeedHistory.clear();

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
    _hstreamSources = hstreamSources;
    _hstreamSubtitleTracks = hstreamSubtitleTracks;
    _headers = headers;

    LogService().info('Initializing player for stream: $streamUrl, title: $title');
    _player = Player();

    try {
      final nativePlayer = _player!.platform as NativePlayer;
      final settings = AppSettings();
      
      // Explicitly set hardware decoding property for the mpv instance
      nativePlayer.setProperty('hwdec', settings.hardwareAccelerationEnabled ? 'auto-safe' : 'no');
      
      nativePlayer.setProperty('hr-seek', 'no');
      nativePlayer.setProperty('cache', 'yes');
      nativePlayer.setProperty('demuxer-seekable-cache', 'yes');
      nativePlayer.setProperty('demuxer-max-bytes', '157286400'); // 150MB max buffer
      nativePlayer.setProperty('demuxer-max-back-bytes', '52428800'); // 50MB max back buffer
      nativePlayer.setProperty('demuxer-readahead-secs', '30'); // 30s readahead
      nativePlayer.setProperty('cache-pause', 'yes');
      nativePlayer.setProperty('network-timeout', '60');         // Wait up to 60s for read operations
      nativePlayer.setProperty('demuxer-lavf-timeout', '60');     // Wait up to 60s for initial metadata/opening
      
      // Auto-apply persisted Video Enhancement if enabled
      if (settings.videoEnhancementEnabled) {
        nativePlayer.setProperty('deband', 'yes');
        
        final String iterations = settings.customEnhancementEnabled 
            ? settings.debandIterations.toString() 
            : '4';
        final String threshold = settings.customEnhancementEnabled 
            ? settings.debandThreshold.toString() 
            : '48';
        final String range = settings.customEnhancementEnabled 
            ? settings.debandRange.toString() 
            : '16';
        final String brightness = settings.customEnhancementEnabled
            ? settings.colorBrightness.toString()
            : '0';
        final String contrast = settings.customEnhancementEnabled
            ? settings.colorContrast.toString()
            : '3';
        final String saturation = settings.customEnhancementEnabled
            ? settings.colorSaturation.toString()
            : '4';

        nativePlayer.setProperty('deband-iterations', iterations);
        nativePlayer.setProperty('deband-threshold', threshold);
        nativePlayer.setProperty('deband-range', range);
        nativePlayer.setProperty('brightness', brightness);
        nativePlayer.setProperty('contrast', contrast);
        nativePlayer.setProperty('saturation', saturation);
        nativePlayer.setProperty('sharpen', '1.0');
        nativePlayer.setProperty('scale', 'spline36');
        nativePlayer.setProperty('cscale', 'spline36');
      }
    } catch (e, stack) {
      LogService().error('Error setting player performance options', e, stack);
    }

    _controller = VideoController(
      _player!,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
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

    _player!.stream.error.listen((err) {
      LogService().error('MediaKit Player Core Error: $err');
    });

    // Start playing via proxy if applicable (only on Desktop to avoid libmpv deadlock)
    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final bool useProxy = isDesktop;
    
    final isDash = streamUrl.endsWith('.mpd');
    final proxyUrl = (useProxy && streamUrl.startsWith('http') && !streamUrl.contains('127.0.0.1'))
        ? VideoProxyService().getProxyUrl(streamUrl, headers: _headers, isDash: isDash)
        : streamUrl;
    
    final headersToPass = useProxy ? null : _headers;
    LogService().info('Opening media stream. useProxy: $useProxy, proxyUrl: $proxyUrl, isDash: $isDash');
    _player!.open(Media(proxyUrl, httpHeaders: headersToPass));

    // Auto-load HStream subtitle track — works for both MP4 and DASH streams.
    // We listen for media to fully load, then download and inject the VTT locally
    // to prevent headers/403 errors and race conditions.
    _tracksSubscription?.cancel();
    _tracksSubscription = null;
    final pendingVttUrl = _hstreamSubtitleTracks?.isNotEmpty == true
        ? _hstreamSubtitleTracks!.first['url']
        : null;
    if (pendingVttUrl != null && pendingVttUrl.isNotEmpty) {
      _tracksSubscription = _player!.stream.tracks.listen((tracks) async {
        if (tracks.video.isNotEmpty || tracks.audio.isNotEmpty) {
          _tracksSubscription?.cancel();
          _tracksSubscription = null;
          try {
            LogService().info('Downloading HStream subtitle: $pendingVttUrl');
            final response = await http.get(
              Uri.parse(pendingVttUrl),
              headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
                'Referer': 'https://hstream.moe/',
              },
            ).timeout(const Duration(seconds: 10));
            
            if (response.statusCode == 200) {
              final tempDir = await getTemporaryDirectory();
              final tempFile = File('${tempDir.path}/hstream_subtitle.vtt');
              await tempFile.writeAsBytes(response.bodyBytes);
              
              LogService().info('Injecting local HStream subtitle: ${tempFile.path}');
              _player?.setSubtitleTrack(
                SubtitleTrack.uri(tempFile.uri.toString(), title: 'English', language: 'en'),
              );
            } else {
              LogService().error('Failed to download subtitle, status: ${response.statusCode}');
            }
          } catch (e, stack) {
            LogService().error('Error downloading/injecting subtitle', e, stack);
          }
        }
      });
    }

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
      _miniPlayerOffset = Offset.zero;
      _isDraggingMiniPlayer = false;
      notifyListeners();
    }
  }

  void maximize() {
    if (_isActive && _isMinimized) {
      _isMinimized = false;
      _miniPlayerOffset = Offset.zero;
      _isDraggingMiniPlayer = false;
      notifyListeners();
    }
  }

  void stopPlayback() {
    _cleanupPlayer();
    _isActive = false;
    _isMinimized = false;
    _isFullscreen = false;
    _miniPlayerOffset = Offset.zero;
    _isDraggingMiniPlayer = false;
    notifyListeners();
  }

  void setMiniPlayerOffset(Offset offset) {
    _miniPlayerOffset = offset;
    notifyListeners();
  }

  void setDraggingMiniPlayer(bool dragging) {
    _isDraggingMiniPlayer = dragging;
    notifyListeners();
  }

  void resetMiniPlayerOffset() {
    _miniPlayerOffset = Offset.zero;
    _isDraggingMiniPlayer = false;
    notifyListeners();
  }


  Future<void> switchHstreamQuality(String newUrl) async {
    if (_player == null) return;
    final currentPosition = _currentPosition;
    _streamUrl = newUrl;
    
    // Open the new URL via proxy if applicable (only on Desktop)
    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final bool useProxy = isDesktop;
    
    final isDash = newUrl.endsWith('.mpd');
    final proxyUrl = (useProxy && newUrl.startsWith('http') && !newUrl.contains('127.0.0.1'))
        ? VideoProxyService().getProxyUrl(newUrl, headers: _headers, isDash: isDash)
        : newUrl;
        
    final headersToPass = useProxy ? null : _headers;
    await _player!.open(Media(proxyUrl, httpHeaders: headersToPass));
    
    // Seek back to where we were
    await _player!.seek(currentPosition);
    notifyListeners();
  }

  void updateActiveEpisode({
    required String streamUrl,
    required String title,
    required int episodeNumber,
    List<HstreamSource>? hstreamSources,
    List<Map<String, String>>? hstreamSubtitleTracks,
    Map<String, String>? headers,
  }) {
    // Save current progress before switching episode
    _saveCurrentProgress();

    _streamUrl = streamUrl;
    _title = title;
    _episodeNumber = episodeNumber;
    if (hstreamSources != null) _hstreamSources = hstreamSources;
    if (hstreamSubtitleTracks != null) _hstreamSubtitleTracks = hstreamSubtitleTracks;
    _headers = headers;

    // Reset current position trackers
    _currentPosition = Duration.zero;
    _currentDuration = Duration.zero;
    _lastSaveTime = null;

    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final bool useProxy = isDesktop;
    
    final isDash = streamUrl.endsWith('.mpd');
    final proxyUrl = (useProxy && streamUrl.startsWith('http') && !streamUrl.contains('127.0.0.1'))
        ? VideoProxyService().getProxyUrl(streamUrl, headers: _headers, isDash: isDash)
        : streamUrl;
    
    final headersToPass = useProxy ? null : _headers;
    _player?.open(Media(proxyUrl, httpHeaders: headersToPass));

    // Auto-load subtitle for the new episode
    _tracksSubscription?.cancel();
    _tracksSubscription = null;
    final pendingVttUrl = _hstreamSubtitleTracks?.isNotEmpty == true
        ? _hstreamSubtitleTracks!.first['url']
        : null;
    if (pendingVttUrl != null && pendingVttUrl.isNotEmpty) {
      _tracksSubscription = _player!.stream.tracks.listen((_) {
        _tracksSubscription?.cancel();
        _tracksSubscription = null;
        _player?.setSubtitleTrack(
          SubtitleTrack.uri(pendingVttUrl, title: 'English', language: 'en'),
        );
      });
    }

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

  void _saveCurrentProgress() async {
    final isAnimeMode = _anilistId != null;
    final id = isAnimeMode ? _anilistId.toString() : _movieId;
    final ep = _episodeNumber ?? 1;
    final pos = _currentPosition.inMilliseconds;
    final dur = _currentDuration.inMilliseconds;

    if (id != null && pos > 0 && dur > 0) {
      _lastSaveTime = DateTime.now();
      final key = '${id}_$ep';
      _progressCache[key] = PlaybackProgress(position: pos, duration: dur);
      notifyListeners();

      final prefix = isAnimeMode ? 'anime_' : 'movie_';
      final now = DateTime.now().millisecondsSinceEpoch;

      await _db.into(_db.playbackPositions).insertOnConflictUpdate(
        db.PlaybackPositionsCompanion.insert(
          mediaId: id,
          episode: ep,
          prefix: prefix,
          positionMs: pos,
          durationMs: dur,
          savedAt: now,
        ),
      );

      final existingCw = await (_db.select(_db.continueWatching)..where((tbl) => tbl.mediaId.equals(id))).getSingleOrNull();
      if (existingCw != null) {
        await _db.into(_db.continueWatching).insertOnConflictUpdate(
          db.ContinueWatchingCompanion.insert(
            mediaId: id,
            prefix: prefix,
            metadataJson: existingCw.metadataJson,
            lastEpisode: ep,
            timestamp: now,
          ),
        );
      }

      if (isAnimeMode) {
        _checkCompletion(_anilistId!, ep, pos, dur);
      } else {
        _checkMovieCompletion(id, ep, pos, dur);
      }
    }
  }

  void _saveMediaMetadata() async {
    final isAnimeMode = _anilistId != null;
    final id = isAnimeMode ? _anilistId.toString() : _movieId;
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
          'isAnime': isAnimeMode,
          'type': med['type'] ?? (med['format'] == 'MOVIE' ? 'movie' : 'series'),
        };
      } else {
        lightweightMedia = {
          'id': id,
          'title': _title ?? 'Media #$id',
          'coverImage': '',
          'averageScore': 0.0,
          'format': (_isMovie == true) ? 'MOVIE' : 'TV',
          'episodes': _episodeCount,
          'isAnime': isAnimeMode,
          'type': (_isMovie == true) ? 'movie' : 'series',
        };
      }

      final prefix = isAnimeMode ? 'anime_' : 'movie_';
      final now = DateTime.now().millisecondsSinceEpoch;
      final ep = _episodeNumber ?? 1;

      final existingCw = await (_db.select(_db.continueWatching)..where((tbl) => tbl.mediaId.equals(id))).getSingleOrNull();
      final timestamp = existingCw?.timestamp ?? now;

      await _db.into(_db.continueWatching).insertOnConflictUpdate(
        db.ContinueWatchingCompanion.insert(
          mediaId: id,
          prefix: prefix,
          metadataJson: jsonEncode(lightweightMedia),
          lastEpisode: ep,
          timestamp: timestamp,
        ),
      );
    }
  }

  static Future<List<dynamic>> getContinueWatchingList({bool? isAnime}) async {
    final database = PlayerState()._db;

    final prefix = (isAnime == true) ? 'anime_' : 'movie_';
    
    final query = database.select(database.continueWatching)
      ..where((tbl) => tbl.prefix.equals(prefix))
      ..orderBy([(tbl) => drift.OrderingTerm.desc(tbl.timestamp)]);
    
    final cwRows = await query.get();
    final List<Map<String, dynamic>> items = [];

    for (final cw in cwRows) {
      final pbQuery = database.select(database.playbackPositions)
        ..where((tbl) => tbl.mediaId.equals(cw.mediaId) & tbl.episode.equals(cw.lastEpisode));
      final pb = await pbQuery.getSingleOrNull();

      if (pb != null && pb.durationMs > 0) {
        final ratio = pb.positionMs / pb.durationMs;
        if (ratio > 0.001 && ratio < 0.90) {
          try {
            final mediaMap = jsonDecode(cw.metadataJson) as Map<String, dynamic>;
            items.add({
              'media': mediaMap,
              'timestamp': cw.timestamp,
            });
          } catch (_) {}
        }
      }
    }

    items.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    return items.map((item) => item['media']).toList();
  }

  static Future<void> removeFromContinueWatching(String id, {required bool isAnime}) async {
    final database = PlayerState()._db;
    await (database.delete(database.continueWatching)..where((tbl) => tbl.mediaId.equals(id))).go();
    await (database.delete(database.playbackPositions)..where((tbl) => tbl.mediaId.equals(id))).go();
    PlayerState().notifyListeners();
  }

  Future<void> _resumePlayback(String id, int episodeNumber) async {
    final query = _db.select(_db.playbackPositions)
      ..where((tbl) => tbl.mediaId.equals(id) & tbl.episode.equals(episodeNumber));
    final pb = await query.getSingleOrNull();

    if (pb != null && pb.durationMs > 0) {
      final ratio = pb.positionMs / pb.durationMs;
      if (ratio < 0.90) {
        await _player?.seek(Duration(milliseconds: pb.positionMs));
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

  int _imdbToLibraryId(String id) {
    if (id.isEmpty) return 0;
    final digits = RegExp(r'\d+').allMatches(id).map((m) => m.group(0)!).join();
    final parsed = int.tryParse(digits);
    if (parsed != null && parsed > 0) return parsed;
    return id.hashCode.abs();
  }

  void _checkMovieCompletion(String movieId, int ep, int pos, int dur) {
    final ratio = pos / dur;
    final int libId = _imdbToLibraryId(movieId);
    final library = LibraryState();
    final item = library.getItem(libId, 'movies');

    if (item == null) {
      if (ratio >= 0.01) {
        final formatVal = (_isMovie == true) ? 'MOVIE' : 'TV';
        library.saveItem(
          id: libId,
          mode: 'movies',
          format: formatVal,
          libraryStatus: ratio >= 0.90 ? 'completed' : 'watching',
          rating: 0.0,
          watchedEpisodes: _isMovie == true ? 1 : ep,
          totalEpisodes: _episodeCount,
        );

        final Map<String, dynamic> metadata = {};
        if (_media != null && _media is Map) {
          metadata.addAll(Map<String, dynamic>.from(_media as Map));
        }
        if (!metadata.containsKey('id')) metadata['id'] = libId;
        if (!metadata.containsKey('title')) metadata['title'] = _title ?? 'Media #$libId';
        if (!metadata.containsKey('format')) metadata['format'] = formatVal;
        
        library.updateMovieCache(libId, metadata);
      }
    } else {
      if (ratio >= 0.90) {
        if (_isMovie == true) {
          if (item.libraryStatus != 'completed') {
            library.saveItem(
              id: libId,
              mode: 'movies',
              format: item.format,
              libraryStatus: 'completed',
              rating: item.rating,
              watchedEpisodes: 1,
              totalEpisodes: item.totalEpisodes,
            );
          }
        } else {
          final nextWatched = max(item.watchedEpisodes, ep);
          final bool isLastEpisode = ep == (item.totalEpisodes ?? _episodeCount ?? ep);
          library.saveItem(
            id: libId,
            mode: 'movies',
            format: item.format,
            libraryStatus: isLastEpisode ? 'completed' : item.libraryStatus,
            rating: item.rating,
            watchedEpisodes: nextWatched,
            totalEpisodes: item.totalEpisodes ?? _episodeCount,
          );
        }
      } else if (ratio >= 0.01) {
        if (_isMovie != true) {
          final nextWatched = max(item.watchedEpisodes, ep);
          if (item.libraryStatus == 'planning') {
            library.saveItem(
              id: libId,
              mode: 'movies',
              format: item.format,
              libraryStatus: 'watching',
              rating: item.rating,
              watchedEpisodes: nextWatched,
              totalEpisodes: item.totalEpisodes ?? _episodeCount,
            );
          } else {
            library.saveItem(
              id: libId,
              mode: 'movies',
              format: item.format,
              libraryStatus: item.libraryStatus,
              rating: item.rating,
              watchedEpisodes: nextWatched,
              totalEpisodes: item.totalEpisodes ?? _episodeCount,
            );
          }
        } else {
          if (item.libraryStatus == 'planning') {
            library.saveItem(
              id: libId,
              mode: 'movies',
              format: item.format,
              libraryStatus: 'watching',
              rating: item.rating,
              watchedEpisodes: item.watchedEpisodes,
              totalEpisodes: item.totalEpisodes,
            );
          }
        }
      }
    }
  }

  void _cleanupPlayer() {
    _saveCurrentProgress(); // Save progress before disposing
    _tracksSubscription?.cancel();
    _tracksSubscription = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _durationSubscription?.cancel();
    _durationSubscription = null;
    _playingSubscription?.cancel();
    _playingSubscription = null;
    _player?.dispose();
    _player = null;
    _controller = null;
    _hstreamSources = null;
    _hstreamSubtitleTracks = null;
    _headers = null;
    try {
      TorrServerService().cancelAllPreloads();
    } catch (_) {}
  }

  void toggleHardwareAcceleration(bool enabled) {
    if (_player == null || !_isActive) return;

    // Save current playback position
    final currentPos = _player!.state.position;

    // Toggle the setting
    AppSettings().setHardwareAccelerationEnabled(enabled);

    // Save details to restart
    final url = _streamUrl;
    final t = _title;
    final aId = _anilistId;
    final mId = _movieId;
    final ts = _titles;
    final epCount = _episodeCount;
    final epNum = _episodeNumber;
    final movie = _isMovie;
    final med = _media;
    final eps = _episodes;
    final hSources = _hstreamSources;
    final hSubTracks = _hstreamSubtitleTracks;
    final hdrs = _headers;

    // Restart playback at the saved position
    startPlayback(
      streamUrl: url!,
      title: t!,
      anilistId: aId,
      movieId: mId,
      titles: ts,
      episodeCount: epCount,
      episodeNumber: epNum,
      isMovie: movie,
      media: med,
      episodes: eps,
      hstreamSources: hSources,
      hstreamSubtitleTracks: hSubTracks,
      headers: hdrs,
    );

    // Seek to the saved position once loaded
    _player!.stream.duration.first.then((_) {
      _player!.seek(currentPos);
    });
  }

  void _addToHistory(String id, int episodeNumber) async {
    final cwQuery = _db.select(_db.continueWatching)..where((tbl) => tbl.mediaId.equals(id));
    final cw = await cwQuery.getSingleOrNull();
    if (cw == null) return;

    Map<String, dynamic> metadata;
    try {
      metadata = jsonDecode(cw.metadataJson);
    } catch (_) {
      return;
    }

    final isAnime = cw.prefix == 'anime_';
    final now = DateTime.now().millisecondsSinceEpoch;

    String titleStr = 'Unknown';
    final rawTitle = metadata['title'];
    if (rawTitle is String) {
      titleStr = rawTitle;
    } else if (rawTitle is Map) {
      titleStr = rawTitle['userPreferred'] ?? rawTitle['english'] ?? rawTitle['romaji'] ?? rawTitle['native'] ?? 'Unknown';
    }

    String coverUrl = '';
    final rawCover = metadata['coverImage'];
    if (rawCover is String) {
      coverUrl = rawCover;
    } else if (rawCover is Map) {
      coverUrl = rawCover['large'] ?? rawCover['medium'] ?? '';
    }

    final existingQuery = _db.select(_db.watchHistory)..where((tbl) => tbl.mediaId.equals(id) & tbl.isManga.equals(0));
    final existing = await existingQuery.getSingleOrNull();

    List<int> eps = [];
    if (existing != null) {
      try {
        final List<dynamic> decodedEps = jsonDecode(existing.episodes);
        eps = decodedEps.map((e) => (e as num).toInt()).toList();
      } catch (_) {}
    }

    if (!eps.contains(episodeNumber)) {
      eps.add(episodeNumber);
    }

    await _db.into(_db.watchHistory).insertOnConflictUpdate(
      db.WatchHistoryCompanion.insert(
        mediaId: id,
        isAnime: isAnime ? 1 : 0,
        isManga: 0,
        title: titleStr,
        coverImage: coverUrl,
        format: metadata['format']?.toString() ?? 'UNKNOWN',
        averageScore: drift.Value((metadata['averageScore'] as num?)?.toDouble() ?? 0.0),
        totalEpisodes: drift.Value((metadata['episodes'] as num?)?.toInt() ?? 0),
        mediaTypeHint: drift.Value(metadata['type']?.toString() ?? ''),
        episodes: jsonEncode(eps),
        timestamp: now,
      ),
    );
  }

  static Future<void> addMangaToHistory(String mangaId, int chapterNumber, String mangaTitle) async {
    final database = PlayerState()._db;

    final prefs = await SharedPreferences.getInstance();
    String coverUrl = '';
    try {
      final cacheJson = prefs.getString('manga_library_cache');
      if (cacheJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(cacheJson);
        if (decoded.containsKey(mangaId)) {
          coverUrl = decoded[mangaId]['thumbnailUrl'] ?? '';
        }
      }
    } catch (_) {}

    final now = DateTime.now().millisecondsSinceEpoch;

    final existingQuery = database.select(database.watchHistory)..where((tbl) => tbl.mediaId.equals(mangaId) & tbl.isManga.equals(1));
    final existing = await existingQuery.getSingleOrNull();

    List<int> chapters = [];
    if (existing != null) {
      try {
        final List<dynamic> decodedCh = jsonDecode(existing.episodes);
        chapters = decodedCh.map((e) => (e as num).toInt()).toList();
      } catch (_) {}
    }

    if (!chapters.contains(chapterNumber)) {
      chapters.add(chapterNumber);
    }

    await database.into(database.watchHistory).insertOnConflictUpdate(
      db.WatchHistoryCompanion.insert(
        mediaId: mangaId,
        isAnime: 0,
        isManga: 1,
        title: mangaTitle,
        coverImage: coverUrl,
        format: 'MANGA',
        averageScore: const drift.Value(0.0),
        totalEpisodes: const drift.Value(0),
        mediaTypeHint: const drift.Value(''),
        episodes: jsonEncode(chapters),
        timestamp: now,
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> getHistoryList() async {
    final database = PlayerState()._db;

    final query = database.select(database.watchHistory)
      ..orderBy([(tbl) => drift.OrderingTerm.desc(tbl.timestamp)]);

    final rows = await query.get();
    final List<Map<String, dynamic>> records = [];

    for (final row in rows) {
      List<int> eps = [];
      try {
        final List<dynamic> decodedEps = jsonDecode(row.episodes);
        eps = decodedEps.map((e) => (e as num).toInt()).toList();
      } catch (_) {}

      records.add({
        'id': row.mediaId,
        'isAnime': row.isAnime == 1,
        'isManga': row.isManga == 1,
        'media': {
          'id': row.mediaId,
          'title': row.title,
          'coverImage': row.coverImage,
          'format': row.format,
          'averageScore': row.averageScore,
          'episodes': row.totalEpisodes > 0 ? row.totalEpisodes : null,
          'isAnime': row.isAnime == 1,
          'type': row.mediaTypeHint,
        },
        'episodes': eps,
        'timestamp': row.timestamp,
      });
    }

    return records;
  }

  static Future<void> clearHistory() async {
    final database = PlayerState()._db;
    await database.delete(database.watchHistory).go();
  }
}
