import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/video_proxy_service.dart';
import 'library_state.dart';
import 'app_settings.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../services/hstream_service.dart';
import '../services/log_service.dart';

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
  List<HstreamSource>? _hstreamSources;
  List<Map<String, String>>? _hstreamSubtitleTracks; // VTT subtitle tracks from HStream
  StreamSubscription? _tracksSubscription;            // fires once after media opens to load subtitle
  Map<String, String>? _headers;

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
  List<HstreamSource>? get hstreamSources => _hstreamSources;
  List<Map<String, String>>? get hstreamSubtitleTracks => _hstreamSubtitleTracks;

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
    List<HstreamSource>? hstreamSources,
    List<Map<String, String>>? hstreamSubtitleTracks,
    Map<String, String>? headers,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
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

  void _saveCurrentProgress() {
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

      SharedPreferences.getInstance().then((prefs) {
        final prefix = isAnimeMode ? 'anime_' : 'movie_';
        prefs.setInt('${prefix}playback_pos_$key', pos);
        prefs.setInt('${prefix}playback_dur_$key', dur);
        prefs.setInt('${prefix}continue_watching_timestamp_$id', DateTime.now().millisecondsSinceEpoch);
        prefs.setInt('${prefix}continue_watching_last_ep_$id', ep);
      });

      if (isAnimeMode) {
        _checkCompletion(_anilistId!, ep, pos, dur);
      } else {
        _checkMovieCompletion(id, ep, pos, dur);
      }
    }
  }

  void _saveMediaMetadata() {
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
      SharedPreferences.getInstance().then((prefs) {
        final prefix = isAnimeMode ? 'anime_' : 'movie_';
        prefs.setString('${prefix}continue_watching_metadata_$id', jsonEncode(lightweightMedia));
      });
    }
  }

  static Future<List<dynamic>> getContinueWatchingList({bool? isAnime}) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    // Migrate legacy continue watching keys to new partitioned prefixes
    for (final key in keys) {
      if (key.startsWith('continue_watching_metadata_')) {
        final id = key.replaceFirst('continue_watching_metadata_', '');
        final isAnimeItem = int.tryParse(id) != null;
        final prefix = isAnimeItem ? 'anime_' : 'movie_';
        
        final metadataJson = prefs.getString(key);
        if (metadataJson != null) {
          await prefs.setString('${prefix}continue_watching_metadata_$id', metadataJson);
          await prefs.remove(key);
        }
        
        final timestamp = prefs.getInt('continue_watching_timestamp_$id');
        if (timestamp != null) {
          await prefs.setInt('${prefix}continue_watching_timestamp_$id', timestamp);
          await prefs.remove('continue_watching_timestamp_$id');
        }
        
        final lastEp = prefs.getInt('continue_watching_last_ep_$id');
        if (lastEp != null) {
          await prefs.setInt('${prefix}continue_watching_last_ep_$id', lastEp);
          await prefs.remove('continue_watching_last_ep_$id');
        }
        
        // Migrate playback positions/durations
        final playKeys = keys.where((k) => k.startsWith('playback_pos_${id}_') || k.startsWith('playback_dur_${id}_')).toList();
        for (final pk in playKeys) {
          final val = prefs.getInt(pk);
          if (val != null) {
            final newPk = pk.replaceFirst('playback_pos_', '${prefix}playback_pos_').replaceFirst('playback_dur_', '${prefix}playback_dur_');
            await prefs.setInt(newPk, val);
            await prefs.remove(pk);
          }
        }
      }
    }
    
    // Refresh keys after migration
    final updatedKeys = prefs.getKeys();
    final prefix = (isAnime == true) ? 'anime_' : 'movie_';
    final metadataPrefix = '${prefix}continue_watching_metadata_';
    
    final metadataKeys = updatedKeys.where((k) => k.startsWith(metadataPrefix)).toList();
    final List<Map<String, dynamic>> items = [];
    
    for (final key in metadataKeys) {
      final id = key.replaceFirst(metadataPrefix, '');
      final timestamp = prefs.getInt('${prefix}continue_watching_timestamp_$id') ?? 0;
      final lastEp = prefs.getInt('${prefix}continue_watching_last_ep_$id') ?? 1;
      
      final pos = prefs.getInt('${prefix}playback_pos_${id}_$lastEp');
      final dur = prefs.getInt('${prefix}playback_dur_${id}_$lastEp');
      
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

  static Future<void> removeFromContinueWatching(String id, {required bool isAnime}) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = isAnime ? 'anime_' : 'movie_';
    
    await prefs.remove('${prefix}continue_watching_metadata_$id');
    await prefs.remove('${prefix}continue_watching_timestamp_$id');
    await prefs.remove('${prefix}continue_watching_last_ep_$id');
    
    final keys = prefs.getKeys();
    final posPrefix = '${prefix}playback_pos_${id}_';
    final durPrefix = '${prefix}playback_dur_${id}_';
    
    for (final key in keys) {
      if (key.startsWith(posPrefix) || key.startsWith(durPrefix)) {
        await prefs.remove(key);
      }
    }
    
    PlayerState().notifyListeners();
  }

  Future<void> _resumePlayback(String id, int episodeNumber) async {
    final key = '${id}_$episodeNumber';
    final prefs = await SharedPreferences.getInstance();
    final prefix = (_anilistId != null) ? 'anime_' : 'movie_';
    final pos = prefs.getInt('${prefix}playback_pos_$key');
    final dur = prefs.getInt('${prefix}playback_dur_$key');
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
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Determine mode and metadata
    var isAnime = true;
    var metadataStr = prefs.getString('anime_continue_watching_metadata_$id');
    if (metadataStr == null) {
      metadataStr = prefs.getString('movie_continue_watching_metadata_$id');
      isAnime = false;
    }
    if (metadataStr == null) return; // No metadata saved yet, skip adding to history

    Map<String, dynamic> metadata;
    try {
      metadata = jsonDecode(metadataStr);
    } catch (_) {
      return;
    }

    // 2. Load existing flat records list
    List<Map<String, dynamic>> records = [];
    final String? flatRecordsStr = prefs.getString('watch_history_flat_records');
    if (flatRecordsStr != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(flatRecordsStr);
        records = decodedList.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    } else {
      // Migrate legacy history if present
      records = await _migrateLegacyHistory(prefs);
    }

    // 3. Update or insert record
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Check if the most recent record (index 0) is the same show
    if (records.isNotEmpty && records[0]['id'] == id && records[0]['isManga'] != true) {
      // Continuous watch! Merge into existing most-recent record
      final List<dynamic> epList = records[0]['episodes'] ?? [];
      final List<int> eps = epList.map((e) => e as int).toList();
      if (!eps.contains(episodeNumber)) {
        eps.add(episodeNumber);
        records[0]['episodes'] = eps;
      }
      records[0]['timestamp'] = now;
    } else {
      // Remove any existing duplicate record elsewhere in the list before inserting at the top
      records.removeWhere((r) => r['id'] == id && r['isManga'] != true);

      // Not continuous watch! Create a brand new history entry at the top
      records.insert(0, {
        'id': id,
        'isAnime': isAnime,
        'isManga': false,
        'media': metadata,
        'episodes': [episodeNumber],
        'timestamp': now,
      });
    }

    // Keep history at a reasonable limit (e.g. 200 items)
    if (records.length > 200) {
      records = records.sublist(0, 200);
    }

    // 4. Save flat records
    await prefs.setString('watch_history_flat_records', jsonEncode(records));

    // Also keep legacy keys updated for compatibility/resuming
    final String legacyKey = 'watched_episodes_$id';
    List<String> legacyList = prefs.getStringList(legacyKey) ?? [];
    final String epStr = episodeNumber.toString();
    if (!legacyList.contains(epStr)) {
      legacyList.add(epStr);
      await prefs.setStringList(legacyKey, legacyList);
    }
    await prefs.setInt('history_last_watched_timestamp_$id', now);
  }

  static Future<void> addMangaToHistory(String mangaId, int chapterNumber, String mangaTitle) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Resolve cover image from cache or settings if we have it
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

    // Load existing flat records
    List<Map<String, dynamic>> records = [];
    final String? flatRecordsStr = prefs.getString('watch_history_flat_records');
    if (flatRecordsStr != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(flatRecordsStr);
        records = decodedList.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Check if the most recent record (index 0) is the same manga
    if (records.isNotEmpty && records[0]['id'] == mangaId && records[0]['isManga'] == true) {
      final List<dynamic> chList = records[0]['episodes'] ?? [];
      final List<int> chapters = chList.map((e) => e as int).toList();
      if (!chapters.contains(chapterNumber)) {
        chapters.add(chapterNumber);
        records[0]['episodes'] = chapters;
      }
      records[0]['timestamp'] = now;
    } else {
      // Remove any existing duplicate history item for this manga
      records.removeWhere((r) => r['id'] == mangaId && r['isManga'] == true);
      
      records.insert(0, {
        'id': mangaId,
        'isAnime': false,
        'isManga': true,
        'media': {
          'id': mangaId,
          'title': mangaTitle,
          'coverImage': coverUrl,
          'format': 'MANGA',
        },
        'episodes': [chapterNumber],
        'timestamp': now,
      });
    }

    if (records.length > 200) {
      records = records.sublist(0, 200);
    }

    await prefs.setString('watch_history_flat_records', jsonEncode(records));
  }

  static Future<List<Map<String, dynamic>>> _migrateLegacyHistory(SharedPreferences prefs) async {
    final List<Map<String, dynamic>> records = [];
    final keys = prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('watched_episodes_')) {
        final id = key.replaceFirst('watched_episodes_', '');
        var isAnime = true;
        var metadataStr = prefs.getString('anime_continue_watching_metadata_$id');
        if (metadataStr == null) {
          metadataStr = prefs.getString('movie_continue_watching_metadata_$id');
          isAnime = false;
        }
        if (metadataStr == null) continue;
        
        try {
          final metadata = jsonDecode(metadataStr);
          final timestamp = prefs.getInt('history_last_watched_timestamp_$id') ?? 0;
          final List<String> epStrs = prefs.getStringList(key) ?? [];
          final List<int> eps = epStrs.map((e) => int.tryParse(e) ?? 0).toList();
          
          records.add({
            'id': id,
            'isAnime': isAnime,
            'media': metadata,
            'episodes': eps,
            'timestamp': timestamp,
          });
        } catch (_) {}
      }
    }
    records.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
    return records;
  }

  static Future<List<Map<String, dynamic>>> getHistoryList() async {
    final prefs = await SharedPreferences.getInstance();
    final String? flatRecordsStr = prefs.getString('watch_history_flat_records');
    
    if (flatRecordsStr != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(flatRecordsStr);
        final List<Map<String, dynamic>> records = [];
        for (var item in decodedList) {
          final map = Map<String, dynamic>.from(item);
          if (map['episodes'] != null) {
            final List<dynamic> epsDecoded = map['episodes'];
            map['episodes'] = epsDecoded.map((e) => e as int).toList();
          } else {
            map['episodes'] = <int>[];
          }
          records.add(map);
        }
        return records;
      } catch (_) {}
    }

    // Migration / Fallback if flat records do not exist yet
    final migrated = await _migrateLegacyHistory(prefs);
    if (migrated.isNotEmpty) {
      await prefs.setString('watch_history_flat_records', jsonEncode(migrated));
    }
    return migrated;
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('watch_history_flat_records');
    final keys = prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('watched_episodes_') || key.startsWith('history_last_watched_timestamp_')) {
        await prefs.remove(key);
      }
    }
  }
}
