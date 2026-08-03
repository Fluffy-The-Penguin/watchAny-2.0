import '../services/notification_service.dart';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/torrent_selector_panel.dart';
import '../widgets/movie_stream_selector_panel.dart';
import '../services/download_service.dart';
import '../services/hstream_service.dart';
import '../state/player_state.dart';
import '../services/stremio_addon_service.dart';
import '../services/extension_service.dart';
import '../state/app_settings.dart';
import '../services/torrserver_service.dart';
import '../services/batch_mapping_service.dart';
import '../services/filler_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/aniskip_service.dart';
import '../state/navigation_state.dart';
import 'settings_page.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final int? anilistId;
  final List<String>? titles;
  final int? episodeCount;
  final int? episodeNumber;
  final bool? isMovie;
  final dynamic media;
  final List<dynamic>? episodes;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.anilistId,
    this.titles,
    this.episodeCount,
    this.episodeNumber,
    this.isMovie,
    this.media,
    this.episodes,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WindowListener {
  late final Player player = PlayerState().player!;
  late final VideoController controller = PlayerState().controller!;
  late final FocusNode _playerFocusNode = FocusNode();
  bool _isMaximized = false;

  Timer? _hideControlsTimer;
  bool _hideCursor = false;
  bool _showAppBar = true;

  void _resetHideControlsTimer() {
    final ps = PlayerState();
    if (_hideCursor || !_showAppBar) {
      if (mounted) {
        setState(() {
          _hideCursor = false;
          _showAppBar = true;
        });
        ps.setShowAppBar(true);
      }
    }
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _overlayEntry == null) {
        setState(() {
          _hideCursor = true;
          _showAppBar = false;
        });
        ps.setShowAppBar(false);
      }
    });
  }

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  DateTime? _lastClosedTime;
  DateTime? _lastOpenedTime;


  // Track settings open/close hover state
  Duration _controlsHoverDuration = const Duration(seconds: 3);
  final ValueNotifier<bool> _isQualityEnhancedNotifier = ValueNotifier<bool>(AppSettings().videoEnhancementEnabled);
  
  final List<StreamSubscription> _subscriptions = [];
  final TorrServerService _torrServerService = TorrServerService();

  // AniSkip state
  List<SkipInterval> _skipIntervals = [];
  bool _hasFetchedSkipTimes = false;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  int? _currentEpNum;
  String? _currentStreamUrl;
  final Set<SkipInterval> _autoSkippedIntervals = {};

  // Playback statistics HUD state variables
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;

  Timer? _torrentStatsTimer;
  double _torrentSpeedBytes = 0.0;
  int _torrentActivePeers = 0;
  int _torrentTotalPeers = 0;
  final List<double> _torrentSpeedHistory = [];




  String? _getTorrentHash(String? url) {
    if (url == null) return null;
    final match = RegExp(r'link=([a-fA-F0-9]+)').firstMatch(url);
    if (match != null) return match.group(1);
    if (url.startsWith('magnet:?xt=urn:btih:')) {
      final matchHex = RegExp(r'urn:btih:([a-fA-F0-9]+)', caseSensitive: false).firstMatch(url);
      if (matchHex != null) return matchHex.group(1);
    }
    return null;
  }

  void _updateTorrentTimer() {
    final hash = _getTorrentHash(_currentStreamUrl);
    if (hash != null) {
      _torrentStatsTimer?.cancel();
      _torrentStatsTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }
        try {
          final info = await _torrServerService.getTorrent(hash);
          if (mounted) {
            setState(() {
              _torrentSpeedBytes = info.downloadSpeed;
              _torrentActivePeers = info.activePeers;
              _torrentTotalPeers = info.totalPeers;
            });
            PlayerState().updateTorrentStats(info.downloadSpeed, info.activePeers, info.totalPeers);
          }
        } catch (_) {}
      });
    } else {
      _torrentStatsTimer?.cancel();
      _torrentStatsTimer = null;
      if (mounted) {
        setState(() {
          _torrentSpeedBytes = 0.0;
          _torrentActivePeers = 0;
          _torrentTotalPeers = 0;
          _torrentSpeedHistory.clear();
        });
      }
      PlayerState().clearTorrentStats();
    }
  }


  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return "0 B/s";
    if (bytesPerSec < 1024) return "${bytesPerSec.toStringAsFixed(0)} B/s";
    if (bytesPerSec < 1024 * 1024) return "${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s";
    return "${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s";
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) {
      return "${d.inSeconds}s";
    }
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return "${minutes}m ${seconds}s";
  }

  void _handlePlayerStateChange() {
    final playerState = PlayerState();
    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    
    if (!isDesktop) {
      if (playerState.isMinimized) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      } else if (playerState.isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    }

    // Detect active episode change
    final activeEp = playerState.episodeNumber ?? widget.episodeNumber;
    final activeUrl = playerState.streamUrl ?? widget.streamUrl;
    if (activeEp != _currentEpNum || activeUrl != _currentStreamUrl) {
      _currentEpNum = activeEp;
      _currentStreamUrl = activeUrl;
      if (mounted) {
        setState(() {
          _skipIntervals = [];
          _autoSkippedIntervals.clear();
          _hasFetchedSkipTimes = false;
        });
        _updateTorrentTimer();
      }
    }
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _resetHideControlsTimer();
    windowManager.addListener(this);
    _checkMaximizedState();
    
    // Set initial values from player state
    _position = player.state.position;
    _duration = player.state.duration;
    _buffer = player.state.buffer;

    _subscriptions.add(player.stream.completed.listen((completed) {
      if (completed && AppSettings().autoNext) {
        _playNextEpisode();
      }
    }));
    _subscriptions.add(player.stream.width.listen((_) {
      if (mounted) setState(() {});
    }));
    _subscriptions.add(player.stream.height.listen((_) {
      if (mounted) setState(() {});
    }));
    _subscriptions.add(player.stream.position.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subscriptions.add(player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subscriptions.add(player.stream.buffer.listen((b) {
      if (mounted) setState(() => _buffer = b);
    }));

    _currentEpNum = PlayerState().episodeNumber ?? widget.episodeNumber;
    _currentStreamUrl = PlayerState().streamUrl ?? widget.streamUrl;

    PlayerState().addListener(_handlePlayerStateChange);
    _handlePlayerStateChange();
    AppSettings().addListener(_onSettingsChanged);

    _updateTorrentTimer();

    // Fetch skip times once duration is loaded
    if (widget.anilistId != null) {
      _durationSubscription = player.stream.duration.listen((duration) {
        if (duration.inSeconds > 0 && !_hasFetchedSkipTimes) {
          _hasFetchedSkipTimes = true;
          _fetchSkipTimes(duration.inSeconds.toDouble());
        }
      });

      _positionSubscription = player.stream.position.listen((position) {
        _checkSkipTimes(position.inSeconds.toDouble());
      });
    }
  }

  Duration? _pendingSeekTarget;
  Timer? _pendingSeekTimer;

  void _performSeekOffset(int offsetSeconds) {
    final currentPos = player.state.position;
    final duration = player.state.duration;
    
    if (_pendingSeekTarget == null) {
      _pendingSeekTarget = currentPos;
    }
    
    _pendingSeekTarget = Duration(
      seconds: (_pendingSeekTarget!.inSeconds + offsetSeconds).clamp(0, duration.inSeconds),
    );
    
    player.seek(_pendingSeekTarget!);
    
    _pendingSeekTimer?.cancel();
    _pendingSeekTimer = Timer(const Duration(milliseconds: 600), () {
      _pendingSeekTarget = null;
    });
  }

  void _toggleFullscreen() {
    final isFull = PlayerState().isFullscreen;
    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isFull) {
      PlayerState().exitFullscreen();
      if (isDesktop) {
        windowManager.setFullScreen(false);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight
        ]);
      }
    } else {
      PlayerState().enterFullscreen();
      if (isDesktop) {
        windowManager.setFullScreen(true);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight
        ]);
      }
    }
  }

  void _toggleSubtitles() {
    final isOff = player.state.track.subtitle.id == 'no';
    if (isOff) {
      final firstTrack = player.state.tracks.subtitle.firstWhere(
        (t) => t.id != 'no' && t.id != 'auto',
        orElse: () => player.state.tracks.subtitle.first,
      );
      player.setSubtitleTrack(firstTrack);
    } else {
      player.setSubtitleTrack(SubtitleTrack.no());
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _torrentStatsTimer?.cancel();
    _hideControlsTimer?.cancel();
    _pendingSeekTimer?.cancel();
    AppSettings().removeListener(_onSettingsChanged);
    PlayerState().removeListener(_handlePlayerStateChange);
    _playerFocusNode.dispose();
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
    windowManager.removeListener(this);
    
    // Ensure we exit fullscreen if the player is closed/disposed
    PlayerState().exitFullscreen();
    windowManager.isFullScreen().then((isFullScreen) {
      if (isFullScreen) {
        windowManager.setFullScreen(false);
      }
    }).catchError((_) {});

    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (!isDesktop) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    }

    super.dispose();
  }

  Future<void> _checkMaximizedState() async {
    try {
      final max = await windowManager.isMaximized();
      if (mounted && max != _isMaximized) {
        setState(() {
          _isMaximized = max;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchSkipTimes(double durationSeconds) async {
    final targetEpNum = _currentEpNum ?? widget.episodeNumber;
    if (widget.anilistId == null || targetEpNum == null) return;
    try {
      final intervals = await AniSkipService().fetchSkipTimes(
        anilistId: widget.anilistId!,
        episodeNumber: targetEpNum,
        episodeLength: durationSeconds,
      );
      if (mounted) {
        setState(() {
          _skipIntervals = intervals;
        });
      }
    } catch (e) {
      developer.log('Error fetching skip times: $e', name: 'watchAny.PlayerScreen');
    }
  }

  void _checkSkipTimes(double positionSeconds) {
    if (_skipIntervals.isEmpty) return;

    SkipInterval? matchingInterval;
    for (var interval in _skipIntervals) {
      if (positionSeconds >= interval.startTime && positionSeconds <= interval.endTime) {
        matchingInterval = interval;
        break;
      }
    }

    if (matchingInterval != null) {
      if (AppSettings().autoSkipIntro) {
        final target = matchingInterval.endTime.toInt();
        if (player.state.position.inSeconds < target - 1) {
          if (!_autoSkippedIntervals.contains(matchingInterval)) {
            _autoSkippedIntervals.add(matchingInterval);
            player.seek(Duration(seconds: target));
            developer.log(
              'Auto-skipped ${matchingInterval.skipType} to ${target}s',
              name: 'watchAny.PlayerScreen',
            );
          }
          return;
        }
      }

      if (PlayerState().activeSkipInterval != matchingInterval) {
        PlayerState().setActiveSkipInterval(matchingInterval);
        PlayerState().setShowSkipButton(true);
      }
    } else {
      if (PlayerState().showSkipButton) {
        PlayerState().setShowSkipButton(false);
        PlayerState().setActiveSkipInterval(null);
      }
    }
  }

  void _performSkip() {
    final active = PlayerState().activeSkipInterval;
    if (active == null) return;
    final target = active.endTime.toInt();
    player.seek(Duration(seconds: target));
    PlayerState().setShowSkipButton(false);
    PlayerState().setActiveSkipInterval(null);
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() {
        _isMaximized = true;
      });
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() {
        _isMaximized = false;
      });
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus.context != null) {
      final w = primaryFocus.context!.widget;
      if (w is EditableText) {
        return KeyEventResult.ignored;
      }
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _performSeekOffset(-10);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _performSeekOffset(10);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.space) {
      player.playOrPause();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      final vol = (player.state.volume + 5.0).clamp(0.0, 100.0);
      player.setVolume(vol);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      final vol = (player.state.volume - 5.0).clamp(0.0, 100.0);
      player.setVolume(vol);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyC) {
      _toggleSubtitles();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyE) {
      _toggleQualityEnhancement();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _toggleSettingsMenu() {
    final now = DateTime.now();
    if (_overlayEntry != null) {
      if (_lastOpenedTime != null &&
          now.difference(_lastOpenedTime!) < const Duration(milliseconds: 200)) {
        return;
      }
      _hideSettingsMenu();
    } else {
      if (_lastClosedTime != null &&
          now.difference(_lastClosedTime!) < const Duration(milliseconds: 200)) {
        return;
      }
      _showSettingsMenu();
    }
  }

  void _hideSettingsMenu() {
    if (_overlayEntry == null) return;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _lastClosedTime = DateTime.now();
    setState(() {
      _controlsHoverDuration = const Duration(seconds: 3);
    });
  }

  void _showSettingsMenu() {
    _lastOpenedTime = DateTime.now();
    setState(() {
      _controlsHoverDuration = const Duration(days: 1);
    });
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Tap outside to close
            ModalBarrier(
              dismissible: true,
              onDismiss: _hideSettingsMenu,
              color: Colors.transparent,
            ),
            Positioned(
              right: 24.0,
              bottom: 72.0,
              width: 280.0,
              child: Material(
                elevation: 8.0,
                color: const Color(0xFF0F0F11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: _SettingsOverlayCard(
                  player: player,
                  onClose: _hideSettingsMenu,
                  isQualityEnhancedNotifier: _isQualityEnhancedNotifier,
                  onToggleQualityEnhanced: _toggleQualityEnhancement,
                  anilistId: widget.anilistId,
                  titles: widget.titles,
                  episodeCount: widget.episodeCount,
                  episodeNumber: PlayerState().episodeNumber ?? widget.episodeNumber ?? 1,
                  isMovie: widget.isMovie,
                  media: widget.media,
                  onOpenTorrentPanel: () {
                    _hideSettingsMenu();
                    _openTorrentSelectorPanel();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  Future<void> _toggleQualityEnhancement() async {
    final settings = AppSettings();
    final bool newValue = !settings.videoEnhancementEnabled;
    await settings.setVideoEnhancementEnabled(newValue);
    _isQualityEnhancedNotifier.value = newValue;

    try {
      final nativePlayer = player.platform as NativePlayer;
      if (newValue) {
        // GPU-accelerated video enhancement parameters
        await nativePlayer.setProperty('deband', 'yes');
        
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

        await nativePlayer.setProperty('deband-iterations', iterations);
        await nativePlayer.setProperty('deband-threshold', threshold);
        await nativePlayer.setProperty('deband-range', range);
        await nativePlayer.setProperty('brightness', brightness);
        await nativePlayer.setProperty('contrast', contrast);
        await nativePlayer.setProperty('saturation', saturation);
        await nativePlayer.setProperty('sharpen', '1.0');
        await nativePlayer.setProperty('scale', 'spline36');
        await nativePlayer.setProperty('cscale', 'spline36');
      } else {
        await nativePlayer.setProperty('deband', 'no');
        await nativePlayer.setProperty('sharpen', '0.0');
        await nativePlayer.setProperty('contrast', '0');
        await nativePlayer.setProperty('saturation', '0');
        await nativePlayer.setProperty('brightness', '0');
        await nativePlayer.setProperty('scale', 'bilinear');
        await nativePlayer.setProperty('cscale', 'bilinear');
      }
    } catch (_) {}
  }

  bool get _isHentai =>
      (widget.media?['genres'] as List<dynamic>? ?? []).contains('Hentai');

  void _playNextEpisode() async {
    final playerState = PlayerState();
    final currentEp = playerState.episodeNumber ?? widget.episodeNumber ?? 1;
    final totalEps = playerState.episodeCount ?? widget.episodeCount ?? 0;
    
    if (widget.isMovie == true || (totalEps > 0 && currentEp >= totalEps)) {
      return;
    }
    
    int nextEp = currentEp + 1;
    if (widget.anilistId != null && AppSettings().autoSkipFiller) {
      while (nextEp <= totalEps && FillerService().isFiller(widget.anilistId!, nextEp)) {
        debugPrint('[PlayerScreen] Auto-skipping filler episode $nextEp');
        nextEp++;
      }
      if (nextEp > totalEps) {
        if (mounted) {
          NotificationService().show(context, 'Remaining episodes are all filler.');
        }
        return;
      }
    }

    // If we're watching via HStream or this is a Hentai show, switch episode directly without opening a panel
    if ((playerState.hstreamSources != null && playerState.hstreamSources!.isNotEmpty) || _isHentai) {
      _playHstreamEpisode(nextEp);
      return;
    }
    
    final String? mediaId = widget.anilistId?.toString() ?? playerState.movieId;
    Map<String, dynamic>? mapping;
    if (mediaId != null) {
      mapping = BatchMappingService().getMapping(mediaId, nextEp);
    }

    if (mapping != null) {
      final hash = mapping['torrentHash'] as String;
      final fileIndex = mapping['fileIndex'] as int;
      final torrentTitle = mapping['torrentTitle'] as String;
      
      final streamUrl = _torrServerService.getStreamUrl(hash, fileIndex);
      final displayName = 'Episode $nextEp ($torrentTitle)';
      
      try {
        await _torrServerService.preloadTorrentFile(hash, fileIndex);
      } catch (_) {}
      
      playerState.updateActiveEpisode(
        streamUrl: streamUrl,
        title: displayName,
        episodeNumber: nextEp,
      );
    } else if (widget.anilistId != null) {
      _openTorrentSelectorPanel(epNum: nextEp);
    } else {
      _changeStremioEpisode(nextEp);
    }
  }

  /// Fetch and play a specific HStream episode number directly without
  /// opening the torrent panel. Used for episode list taps and auto-next.
  Future<void> _playHstreamEpisode(int epNum) async {
    final titles = widget.titles ?? [];
    if (titles.isEmpty || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        backgroundColor: Color(0xFF1A1A2E),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(width: 16),
            Text('Loading episode...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      final service = HstreamService();

      final searchTerms = service.generateSearchTerms(titles);
      List<HstreamResult> results = [];
      for (final term in searchTerms) {
        results = await service.search(term);
        if (results.isNotEmpty) break;
      }

      if (!mounted) return;

      if (results.isEmpty) {
        Navigator.pop(context);
        return;
      }

      // Pick best result matching the episode number
      HstreamResult? best;
      for (final r in results) {
        final path = Uri.tryParse(r.url)?.pathSegments.lastOrNull ?? '';
        final lastPart = path.split('-').lastOrNull;
        if (lastPart != null && int.tryParse(lastPart) == epNum) {
          best = r;
          break;
        }
      }

      if (best == null) {
        for (final r in results) {
          final title = r.title.toLowerCase();
          final regex = RegExp(
            r'(?:^|\b|[-_])' + epNum.toString() + r'(?:\b|$)',
            caseSensitive: false,
          );
          if (regex.hasMatch(title)) {
            best = r;
            break;
          }
        }
      }

      best ??= results.first;
      final streams = await service.getStreams(best.url);

      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (streams == null || streams.sources.isEmpty) return;

      // Prefer MP4 for compatibility; fall back to first available source
      final preferred = streams.sources.firstWhere(
        (s) => s.type == 'video/mp4',
        orElse: () => streams.sources.first,
      );

      final episodeTitle = streams.title.isNotEmpty
          ? streams.title
          : (titles.isNotEmpty ? '${titles.first} — Episode $epNum' : 'Episode $epNum');

      PlayerState().updateActiveEpisode(
        streamUrl: preferred.url,
        title: episodeTitle,
        episodeNumber: epNum,
        hstreamSources: streams.sources,
        hstreamSubtitleTracks: streams.tracks,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
          'Referer': 'https://hstream.moe/',
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  void _openTorrentSelectorPanel({int? epNum}) {
    if (widget.anilistId == null) {
      _openMovieStreamSelectorPanel(epNum: epNum);
      return;
    }
    final targetEpNum = epNum ?? PlayerState().episodeNumber ?? widget.episodeNumber ?? 1;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobileSheet = screenWidth < 650;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: isMobileSheet ? double.infinity : 800.0,
            height: MediaQuery.of(context).size.height * (isMobileSheet ? 0.8 : 0.65),
            margin: isMobileSheet
                ? EdgeInsets.zero
                : const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C0E),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
              border: Border.all(color: Colors.white10, width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black87,
                  blurRadius: 30,
                  spreadRadius: 2,
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15.0)),
              child: TorrentSelectorPanel(
                isFromPlayer: true,
                anilistId: widget.anilistId,
                titles: widget.titles ?? [],
                episodeCount: widget.episodeCount ?? 0,
                episodeNumber: targetEpNum,
                isMovie: widget.isMovie ?? false,
                media: widget.media,
                episodes: widget.episodes,
                onStreamSelected: (String streamUrl, String title) {
                  PlayerState().updateActiveEpisode(
                    streamUrl: streamUrl,
                    title: title,
                    episodeNumber: targetEpNum,
                  );
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _openMovieStreamSelectorPanel({int? epNum}) async {
    final String? movieId = PlayerState().movieId;
    if (movieId == null) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    final addonService = StremioAddonService();
    await addonService.init();

    final parts = movieId.split(':');
    final String type = parts.length > 1 ? parts[0] : (widget.isMovie == true ? 'movie' : 'series');
    final String realId = parts.last;
    final targetEpNum = epNum ?? PlayerState().episodeNumber ?? widget.episodeNumber ?? 1;

    final targetId = type == 'series' ? '$realId:$targetEpNum' : realId;

    final streamAddons = addonService.streamAddons
        .where((a) => a.matchesId(targetId))
        .where((a) => a.supportsType(type) || a.types.isEmpty)
        .toList();

    final streamFutures = <Future<List<dynamic>>>[];
    for (final addon in streamAddons) {
      streamFutures.add(() async {
        try {
          final url = '${addon.baseUrl}/stream/$type/$targetId.json';
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            final List streams = body['streams'] ?? [];
            return streams
                .map((s) => Map<String, dynamic>.from(s as Map)..['addonName'] = addon.name)
                .toList();
          }
        } catch (e) {
          debugPrint('[stream] Error from ${addon.name}: $e');
        }
        return [];
      }());
    }

    final allStreams = <dynamic>[];
    if (streamFutures.isNotEmpty) {
      final results = await Future.wait(streamFutures);
      for (final r in results) {
        allStreams.addAll(r);
      }
    }

    if (mounted) Navigator.pop(context);

    if (allStreams.isEmpty) {
      if (mounted) {
        NotificationService().show(context, 'No stream links found for this title.');
      }
      return;
    }

    if (!mounted) return;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobileSheet = screenWidth < 650;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: isMobileSheet ? double.infinity : 800.0,
            height: MediaQuery.of(context).size.height * (isMobileSheet ? 0.8 : 0.65),
            margin: isMobileSheet
                ? EdgeInsets.zero
                : const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C0E),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
              border: Border.all(color: Colors.white10, width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black87,
                  blurRadius: 30,
                  spreadRadius: 2,
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15.0)),
              child: MovieStreamSelectorPanel(
                isFromPlayer: true,
                streams: allStreams,
                title: widget.title,
                onStreamSelected: (stream, {isDownload = false}) {
                  Navigator.pop(context);
                  if (stream['infoHash'] != null) {
                    final String hash = stream['infoHash'].toString();
                    final String streamTitle = stream['title']?.toString() ?? stream['name']?.toString() ?? '';
                    final int seeders = _getStreamSeeders(stream);
                    final int sizeBytes = stream['size'] != null ? (int.tryParse(stream['size'].toString()) ?? 0) : 0;

                    final List<dynamic>? sources = stream['sources'] as List?;
                    String magnetLink = 'magnet:?xt=urn:btih:$hash';
                    final List<String> trackers = [];
                    if (sources != null && sources.isNotEmpty) {
                      for (final src in sources) {
                        final s = src.toString();
                        if (s.startsWith('tracker:')) {
                          trackers.add(s.replaceFirst('tracker:', ''));
                        } else if (!s.startsWith('dht:')) {
                          trackers.add(s);
                        }
                      }
                    }
                    if (trackers.isEmpty) {
                      trackers.addAll([
                        'udp://tracker.coppersurfer.tk:6969/announce',
                        'udp://tracker.openittracker.com:80/announce',
                        'udp://tracker.opentrackr.org:1337/announce',
                        'udp://explodie.org:6969/announce',
                        'udp://9.rarbg.to:2710/announce',
                        'udp://9.rarbg.me:2780/announce',
                        'udp://open.stealth.si:80/announce',
                        'udp://tracker.torrent.eu.org:451/announce',
                        'udp://opentracker.i2p.rocks:6969/announce',
                      ]);
                    }
                    for (final tr in trackers) {
                      magnetLink += '&tr=${Uri.encodeComponent(tr)}';
                    }

                    final torrentStream = TorrentStream(
                      title: streamTitle.isNotEmpty ? streamTitle : widget.title,
                      link: magnetLink,
                      seeders: seeders,
                      leechers: 0,
                      downloads: 0,
                      hash: hash,
                      size: sizeBytes,
                      accuracy: 'high',
                      type: PlayerState().isMovie == true ? 'movie' : 'series',
                      extensionName: stream['addonName']?.toString() ?? 'Stremio Addon',
                    );

                    int? activeSeason;
                    if (widget.episodes != null && widget.episodes!.isNotEmpty) {
                      final epObj = widget.episodes!.firstWhere(
                        (v) => v is Map && (v['episode'] as num?)?.toInt() == targetEpNum,
                        orElse: () => null,
                      );
                      if (epObj != null && epObj['season'] != null) {
                        activeSeason = (epObj['season'] as num).toInt();
                      }
                    }

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (dialogCtx) => PlaybackProgressDialog(
                        stream: torrentStream,
                        parentContext: context,
                        anilistId: null,
                        movieId: PlayerState().movieId ?? '',
                        episodeNumber: targetEpNum,
                        titles: [widget.title],
                        episodeCount: widget.episodes?.length ?? 1,
                        isMovie: PlayerState().isMovie == true,
                        media: widget.media ?? {},
                        episodes: widget.episodes,
                        isDownload: isDownload,
                        season: activeSeason,
                      ),
                    );
                  } else {
                    final String streamUrl = stream['url']?.toString() ?? '';
                    final String streamTitle = stream['title']?.toString() ?? 'Stream';
                    
                    Map<String, String>? headers;
                    if (stream['behaviorHints'] is Map) {
                      final bh = stream['behaviorHints'] as Map;
                      if (bh['proxyHeaders'] is Map && bh['proxyHeaders']['request'] is Map) {
                        headers = (bh['proxyHeaders']['request'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
                      } else if (bh['headers'] is Map) {
                        headers = (bh['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
                      }
                    }
                    if (headers == null && stream['headers'] is Map) {
                      headers = (stream['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
                    }

                    PlayerState().updateActiveEpisode(
                      streamUrl: streamUrl,
                      title: streamTitle,
                      episodeNumber: targetEpNum,
                      headers: headers,
                    );
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  int _extractEpNum(String title, int fallback) {
    final match = RegExp(r"(?:Episode|Ep\.?)\s*(\d+)", caseSensitive: false).firstMatch(title) ??
                  RegExp(r"^(\d+)\s*[-.]").firstMatch(title);
    return match != null ? int.parse(match.group(1)!) : fallback;
  }

  String _cleanEpTitle(String title) {
    final cleaned = title.replaceAll(RegExp(r"^Episode\s*\d+\s*[-–—:·]?\s*", caseSensitive: false), '').trim();
    return cleaned.isNotEmpty ? cleaned : title;
  }  void _openEpisodesPanel() {
    _hideSettingsMenu();
    if (widget.episodes == null || widget.episodes!.isEmpty) return;
    
    final int itemsPerPage = 50;
    final int totalEpisodes = widget.episodes!.length;
    final int totalPages = (totalEpisodes / itemsPerPage).ceil();

    final int currentEp = PlayerState().episodeNumber ?? widget.episodeNumber ?? 1;
    int currentEpIndex = 0;
    for (int i = 0; i < widget.episodes!.length; i++) {
      final ep = widget.episodes![i];
      final String epTitle = ep['title'] ?? '';
      final int epNum = ep['isPlaceholder'] == true ? (i + 1) : _extractEpNum(epTitle, i + 1);
      if (epNum == currentEp) {
        currentEpIndex = i;
        break;
      }
    }
    int currentPage = (currentEpIndex / itemsPerPage).floor().clamp(0, totalPages - 1);

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobileSheet = screenWidth < 650;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final startIdx = currentPage * itemsPerPage;
            final endIdx = min(startIdx + itemsPerPage, totalEpisodes);
            final pagedList = widget.episodes!.sublist(startIdx, endIdx);

            return Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: isMobileSheet ? double.infinity : 800.0,
                height: MediaQuery.of(context).size.height * (isMobileSheet ? 0.7 : 0.55),
                margin: isMobileSheet
                    ? EdgeInsets.zero
                    : const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C0C0E),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
                  border: Border.all(color: Colors.white10, width: 1.0),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black87,
                      blurRadius: 30,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Episodes List (${widget.episodes!.length} total)",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 8.0),
                    
                    // Render paginator if more than 1 page
                    if (totalPages > 1) ...[
                      SizedBox(
                        height: 36.0,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: totalPages,
                          itemBuilder: (context, index) {
                            final int pageStart = index * itemsPerPage + 1;
                            final int pageEnd = min((index + 1) * itemsPerPage, totalEpisodes);
                            final isSelected = currentPage == index;

                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: InkWell(
                                onTap: () {
                                  setSheetState(() {
                                    currentPage = index;
                                  });
                                },
                                borderRadius: BorderRadius.circular(4.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(4.0),
                                    border: Border.all(
                                      color: isSelected ? Colors.white : Colors.white10,
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$pageStart-$pageEnd',
                                      style: TextStyle(
                                        color: isSelected ? Colors.black : Colors.white70,
                                        fontSize: 11.0,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        fontFamily: 'Outfit',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      const Divider(color: Colors.white10, height: 1),
                    ],

                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isMobileSheet ? 2 : 4,
                            crossAxisSpacing: 12.0,
                            mainAxisSpacing: 12.0,
                            childAspectRatio: 1.45,
                          ),
                          itemCount: pagedList.length,
                          itemBuilder: (context, index) {
                            final ep = pagedList[index];
                            final String epTitle = ep['title'] ?? '';
                            final String thumbnail = ep['thumbnail'] ?? '';
                            final int epNum = ep['isPlaceholder'] == true
                                ? (startIdx + index + 1)
                                : _extractEpNum(epTitle, startIdx + index + 1);
                            final String cleanTitle = ep['isPlaceholder'] == true ? epTitle : _cleanEpTitle(epTitle);
                            
                            final String finalTitle = cleanTitle;
                            final String finalThumbnail = thumbnail;
                            final isPlaying = (PlayerState().episodeNumber ?? widget.episodeNumber ?? 1) == epNum;
                            
                            return GestureDetector(
                              onTap: () async {
                                Navigator.of(context).pop(); // Close bottom sheet
                                if (!isPlaying) {
                                  DownloadTask? downloadedTask;
                                  try {
                                    downloadedTask = DownloadService().tasks.firstWhere(
                                      (t) => t.anilistId == widget.anilistId &&
                                             t.episodeNumber == epNum &&
                                             t.status == DownloadStatus.completed,
                                    );
                                  } catch (_) {}

                                  if (downloadedTask != null) {
                                    PlayerState().updateActiveEpisode(
                                      streamUrl: downloadedTask.savePath,
                                      title: downloadedTask.title,
                                      episodeNumber: epNum,
                                    );
                                  } else {
                                    final String? mediaId = widget.anilistId?.toString() ?? PlayerState().movieId;
                                    Map<String, dynamic>? mapping;
                                    if (mediaId != null) {
                                      mapping = BatchMappingService().getMapping(mediaId, epNum);
                                    }

                                    if (mapping != null) {
                                      final hash = mapping['torrentHash'] as String;
                                      final fileIndex = mapping['fileIndex'] as int;
                                      final torrentTitle = mapping['torrentTitle'] as String;
                                      
                                      final streamUrl = _torrServerService.getStreamUrl(hash, fileIndex);
                                      final displayName = 'Episode $epNum ($torrentTitle)';
                                      
                                      try {
                                        await _torrServerService.preloadTorrentFile(hash, fileIndex);
                                      } catch (_) {}
                                      
                                      PlayerState().updateActiveEpisode(
                                        streamUrl: streamUrl,
                                        title: displayName,
                                        episodeNumber: epNum,
                                      );
                                    } else if ((PlayerState().hstreamSources != null &&
                                        PlayerState().hstreamSources!.isNotEmpty) || _isHentai) {
                                      _playHstreamEpisode(epNum);
                                    } else if (widget.anilistId != null) {
                                      _openTorrentSelectorPanel(epNum: epNum);
                                    } else {
                                      _changeStremioEpisode(epNum);
                                    }
                                  }
                                }
                              },
                              child: _PlayerEpisodeCard(
                                epNum: epNum,
                                title: finalTitle,
                                thumbnail: finalThumbnail,
                                isPlaying: isPlaying,
                                anilistId: widget.anilistId,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    return ListenableBuilder(
      listenable: PlayerState(),
      builder: (context, _) {
        final playerState = PlayerState();
        final currentTitle = playerState.title ?? widget.title;

        // 1. Desktop custom controls theme configuration
    final desktopTheme = MaterialDesktopVideoControlsTheme(
      normal: MaterialDesktopVideoControlsThemeData(
        toggleFullscreenOnDoublePress: true,
        keyboardShortcuts: const {},
        displaySeekBar: false,
        buttonBarHeight: 88.0,
        controlsHoverDuration: _controlsHoverDuration,
        seekBarBufferColor: Colors.white24,
        seekBarPositionColor: Colors.amber,
        seekBarColor: Colors.white12,
        seekBarThumbColor: Colors.amber,
        bottomButtonBar: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: HoverSeekBar(player: player),
                ),
                const SizedBox(height: 4.0),
                Row(
                  children: [
                    // Seek Back 10 Button
                    MaterialDesktopCustomButton(
                      onPressed: () => _performSeekOffset(-10),
                      icon: const Icon(Icons.replay_10, color: Colors.white),
                    ),
                    const MaterialDesktopPlayOrPauseButton(),
                    // Seek Forward 10 Button
                    MaterialDesktopCustomButton(
                      onPressed: () => _performSeekOffset(10),
                      icon: const Icon(Icons.forward_10, color: Colors.white),
                    ),
                    if (widget.isMovie != true)
                      MaterialDesktopCustomButton(
                        onPressed: _playNextEpisode,
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                      ),
                    const MaterialDesktopVolumeButton(),
                    const MaterialDesktopPositionIndicator(),
                    const Spacer(),
                    if (widget.episodes != null && widget.episodes!.isNotEmpty)
                      MaterialDesktopCustomButton(
                        onPressed: _openEpisodesPanel,
                        icon: const Icon(
                          Icons.keyboard_arrow_up,
                          color: Colors.white,
                        ),
                      ),
                    if (widget.episodes != null && widget.episodes!.isNotEmpty)
                      const Spacer(),
                    // Quality Enhancement Button
                    ListenableBuilder(
                      listenable: AppSettings(),
                      builder: (context, _) {
                        final isEnhanced = AppSettings().videoEnhancementEnabled;
                        return MaterialDesktopCustomButton(
                          onPressed: _toggleQualityEnhancement,
                          icon: Icon(
                            Icons.auto_awesome,
                            color: isEnhanced ? Colors.amber : Colors.white38,
                          ),
                        );
                      },
                    ),
                    // Subtitles On/Off Button (CC)
                    MaterialDesktopCustomButton(
                      onPressed: () {
                        final isOff = player.state.track.subtitle.id == 'no';
                        if (isOff) {
                          final firstTrack = player.state.tracks.subtitle.firstWhere(
                            (t) => t.id != 'no' && t.id != 'auto',
                            orElse: () => player.state.tracks.subtitle.first,
                          );
                          player.setSubtitleTrack(firstTrack);
                        } else {
                          player.setSubtitleTrack(SubtitleTrack.no());
                        }
                        setState(() {});
                      },
                      icon: StreamBuilder(
                        stream: player.stream.track,
                        builder: (context, _) {
                          final isOff = player.state.track.subtitle.id == 'no';
                          return Icon(
                            isOff ? Icons.closed_caption_disabled : Icons.closed_caption,
                            color: isOff ? Colors.white38 : Colors.white,
                          );
                        },
                      ),
                    ),
                     // Video Fit/Resize Button
                     Builder(
                       builder: (controlsContext) => MaterialDesktopCustomButton(
                         onPressed: () => PlayerState().cycleVideoFit(controlsContext),
                         icon: const Icon(
                           Icons.aspect_ratio,
                           color: Colors.white,
                         ),
                       ),
                     ),
                    // Diagnostics Dashboard Button
                    ListenableBuilder(
                      listenable: PlayerState(),
                      builder: (context, _) => MaterialDesktopCustomButton(
                        onPressed: () {
                          final ps = PlayerState();
                          ps.setShowTorrentDashboard(!ps.showTorrentDashboard);
                        },
                        icon: Icon(
                          Icons.analytics_outlined,
                          color: PlayerState().showTorrentDashboard ? Colors.cyanAccent : Colors.white,
                        ),
                      ),
                    ),
                    // Change Stream Button
                    if (widget.anilistId != null || PlayerState().movieId != null)
                      MaterialDesktopCustomButton(
                        onPressed: () {
                          _hideSettingsMenu();
                          _openTorrentSelectorPanel();
                        },
                        icon: const Icon(Icons.swap_horizontal_circle, color: Colors.white),
                      ),
                    // Settings Button with Target Link
                    CompositedTransformTarget(
                      link: _layerLink,
                      child: MaterialDesktopCustomButton(
                        onPressed: _toggleSettingsMenu,
                        icon: const Icon(Icons.settings, color: Colors.white),
                      ),
                    ),
                    const MaterialDesktopFullscreenButton(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      fullscreen: MaterialDesktopVideoControlsThemeData(
        toggleFullscreenOnDoublePress: true,
        keyboardShortcuts: const {},
        displaySeekBar: false,
        buttonBarHeight: 88.0,
        controlsHoverDuration: _controlsHoverDuration,
        seekBarBufferColor: Colors.white24,
        seekBarPositionColor: Colors.amber,
        seekBarColor: Colors.white12,
        seekBarThumbColor: Colors.amber,
        bottomButtonBar: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: HoverSeekBar(player: player),
                ),
                const SizedBox(height: 4.0),
                Row(
                  children: [
                    // Seek Back 10 Button
                    MaterialDesktopCustomButton(
                      onPressed: () => _performSeekOffset(-10),
                      icon: const Icon(Icons.replay_10, color: Colors.white),
                    ),
                    const MaterialDesktopPlayOrPauseButton(),
                    // Seek Forward 10 Button
                    MaterialDesktopCustomButton(
                      onPressed: () => _performSeekOffset(10),
                      icon: const Icon(Icons.forward_10, color: Colors.white),
                    ),
                    if (widget.isMovie != true)
                      MaterialDesktopCustomButton(
                        onPressed: _playNextEpisode,
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                      ),
                    const MaterialDesktopVolumeButton(),
                    const MaterialDesktopPositionIndicator(),
                    const Spacer(),
                    if (widget.episodes != null && widget.episodes!.isNotEmpty)
                      MaterialDesktopCustomButton(
                        onPressed: _openEpisodesPanel,
                        icon: const Icon(
                          Icons.keyboard_arrow_up,
                          color: Colors.white,
                        ),
                      ),
                    if (widget.episodes != null && widget.episodes!.isNotEmpty)
                      const Spacer(),
                    // Quality Enhancement Button
                    ListenableBuilder(
                      listenable: AppSettings(),
                      builder: (context, _) {
                        final isEnhanced = AppSettings().videoEnhancementEnabled;
                        return MaterialDesktopCustomButton(
                          onPressed: _toggleQualityEnhancement,
                          icon: Icon(
                            Icons.auto_awesome,
                            color: isEnhanced ? Colors.amber : Colors.white38,
                          ),
                        );
                      },
                    ),
                    // Subtitles On/Off Button (CC)
                    MaterialDesktopCustomButton(
                      onPressed: () {
                        final isOff = player.state.track.subtitle.id == 'no';
                        if (isOff) {
                          final firstTrack = player.state.tracks.subtitle.firstWhere(
                            (t) => t.id != 'no' && t.id != 'auto',
                            orElse: () => player.state.tracks.subtitle.first,
                          );
                          player.setSubtitleTrack(firstTrack);
                        } else {
                          player.setSubtitleTrack(SubtitleTrack.no());
                        }
                        setState(() {});
                      },
                      icon: StreamBuilder(
                        stream: player.stream.track,
                        builder: (context, _) {
                          final isOff = player.state.track.subtitle.id == 'no';
                          return Icon(
                            isOff ? Icons.closed_caption_disabled : Icons.closed_caption,
                            color: isOff ? Colors.white38 : Colors.white,
                          );
                        },
                      ),
                    ),
                     // Video Fit/Resize Button
                     Builder(
                       builder: (controlsContext) => MaterialDesktopCustomButton(
                         onPressed: () => PlayerState().cycleVideoFit(controlsContext),
                         icon: const Icon(
                           Icons.aspect_ratio,
                           color: Colors.white,
                         ),
                       ),
                     ),
                    // Diagnostics Dashboard Button
                    ListenableBuilder(
                      listenable: PlayerState(),
                      builder: (context, _) => MaterialDesktopCustomButton(
                        onPressed: () {
                          final ps = PlayerState();
                          ps.setShowTorrentDashboard(!ps.showTorrentDashboard);
                        },
                        icon: Icon(
                          Icons.analytics_outlined,
                          color: PlayerState().showTorrentDashboard ? Colors.cyanAccent : Colors.white,
                        ),
                      ),
                    ),
                    // Change Stream Button
                    if (widget.anilistId != null || PlayerState().movieId != null)
                      MaterialDesktopCustomButton(
                        onPressed: () {
                          _hideSettingsMenu();
                          _openTorrentSelectorPanel();
                        },
                        icon: const Icon(Icons.swap_horizontal_circle, color: Colors.white),
                      ),
                    // Settings Button with Target Link
                    CompositedTransformTarget(
                      link: _layerLink,
                      child: MaterialDesktopCustomButton(
                        onPressed: _toggleSettingsMenu,
                        icon: const Icon(Icons.settings, color: Colors.white),
                      ),
                    ),
                    const MaterialDesktopFullscreenButton(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double playerWidth = constraints.maxWidth;

          final videoWidth = player.state.width;
          final videoHeight = player.state.height;

          return ListenableBuilder(
            listenable: AppSettings(),
            builder: (context, _) {
              final settings = AppSettings();
              final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
              final double baseWidth = isMobile ? 380.0 : 720.0;
              final double scale = (playerWidth / baseWidth).clamp(isMobile ? 1.0 : 0.85, 3.0);
              final double subtitleFontSize = (scale * settings.subtitlesFontSize).clamp(14.0, 72.0);

              final subtitleConfig = !settings.subtitlesCustomStylesEnabled
                  ? const SubtitleViewConfiguration()
                  : SubtitleViewConfiguration(
                style: TextStyle(
                  height: 1.4,
                  fontSize: subtitleFontSize,
                  letterSpacing: 0.0,
                  wordSpacing: 0.0,
                  color: Color(settings.subtitlesTextColor),
                  backgroundColor: settings.subtitlesBgEnabled
                      ? Color(settings.subtitlesBgColor).withValues(alpha: settings.subtitlesBgOpacity)
                      : null,
                  fontWeight: settings.subtitlesBold ? FontWeight.bold : FontWeight.normal,
                  fontStyle: settings.subtitlesItalic ? FontStyle.italic : FontStyle.normal,
                  fontFamily: settings.subtitlesFontFamily,
                  shadows: settings.subtitlesShadowEnabled
                      ? [
                          Shadow(
                            offset: Offset(-settings.subtitlesShadowOffset, -settings.subtitlesShadowOffset),
                            color: Color(settings.subtitlesShadowColor).withValues(alpha: settings.subtitlesShadowOpacity),
                            blurRadius: settings.subtitlesShadowBlurRadius,
                          ),
                          Shadow(
                            offset: Offset(settings.subtitlesShadowOffset, -settings.subtitlesShadowOffset),
                            color: Color(settings.subtitlesShadowColor).withValues(alpha: settings.subtitlesShadowOpacity),
                            blurRadius: settings.subtitlesShadowBlurRadius,
                          ),
                          Shadow(
                            offset: Offset(settings.subtitlesShadowOffset, settings.subtitlesShadowOffset),
                            color: Color(settings.subtitlesShadowColor).withValues(alpha: settings.subtitlesShadowOpacity),
                            blurRadius: settings.subtitlesShadowBlurRadius,
                          ),
                          Shadow(
                            offset: Offset(-settings.subtitlesShadowOffset, settings.subtitlesShadowOffset),
                            color: Color(settings.subtitlesShadowColor).withValues(alpha: settings.subtitlesShadowOpacity),
                            blurRadius: settings.subtitlesShadowBlurRadius,
                          ),
                          Shadow(
                            offset: Offset(-settings.subtitlesShadowOffset, 0),
                            color: Color(settings.subtitlesShadowColor).withValues(alpha: settings.subtitlesShadowOpacity),
                            blurRadius: settings.subtitlesShadowBlurRadius,
                          ),
                          Shadow(
                            offset: Offset(settings.subtitlesShadowOffset, 0),
                            color: Color(settings.subtitlesShadowColor).withValues(alpha: settings.subtitlesShadowOpacity),
                            blurRadius: settings.subtitlesShadowBlurRadius,
                          ),
                          Shadow(
                            offset: Offset(0, -settings.subtitlesShadowOffset),
                            color: Color(settings.subtitlesShadowColor).withValues(alpha: settings.subtitlesShadowOpacity),
                            blurRadius: settings.subtitlesShadowBlurRadius,
                          ),
                          Shadow(
                            offset: Offset(0, settings.subtitlesShadowOffset),
                            color: Color(settings.subtitlesShadowColor).withValues(alpha: settings.subtitlesShadowOpacity),
                            blurRadius: settings.subtitlesShadowBlurRadius,
                          ),
                        ]
                      : null,
                ),
                textAlign: TextAlign.center,
                padding: DynamicSubtitlePadding(
                  baseOffset: settings.subtitlesPositionOffset,
                  subtitlesXOffset: settings.subtitlesXOffset,
                  videoWidth: (videoWidth ?? 0).toDouble(),
                  videoHeight: (videoHeight ?? 0).toDouble(),
                ),
              );

              Widget videoWidget = Video(
                controller: controller,
                subtitleViewConfiguration: subtitleConfig,
                fit: PlayerState().videoFit,
                onEnterFullscreen: () async {
                  PlayerState().enterFullscreen();
                  if (isDesktop) {
                    try {
                      await windowManager.setFullScreen(true);
                    } catch (_) {}
                    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                  } else {
                    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                    await SystemChrome.setPreferredOrientations([
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]); // force landscape in fullscreen
                  }
                },
                onExitFullscreen: () async {
                  PlayerState().exitFullscreen();
                  if (isDesktop) {
                    try {
                      await windowManager.setFullScreen(false);
                    } catch (_) {}
                    await SystemChrome.setEnabledSystemUIMode(
                      SystemUiMode.manual,
                      overlays: SystemUiOverlay.values,
                    );
                  } else {
                    await SystemChrome.setEnabledSystemUIMode(
                      SystemUiMode.manual,
                      overlays: SystemUiOverlay.values,
                    );
                    await SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                      DeviceOrientation.portraitDown,
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]); // allow both vertical/horizontal on exit
                  }
                },
                controls: (state) {
                  final bool isDesktopPlatform = [
                    TargetPlatform.windows,
                    TargetPlatform.linux,
                    TargetPlatform.macOS,
                  ].contains(Theme.of(state.context).platform);
                  
                  final double width = MediaQuery.of(state.context).size.width;
                  final bool useMobileControls = !isDesktopPlatform || width < 600;

                  final Widget controlsWidget = KeyedSubtree(
                    key: ValueKey(_overlayEntry != null),
                    child: useMobileControls
                        ? MaterialVideoControls(state)
                        : MaterialDesktopVideoControls(state),
                  );

                  return Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) {
                      _resetHideControlsTimer();
                      Focus.of(state.context).requestFocus();
                    },
                    child: Focus(
                      autofocus: true,
                      onKeyEvent: (FocusNode node, KeyEvent event) {
                        _resetHideControlsTimer();
                        return _handleKeyEvent(event);
                      },
                      child: _PlayerGestureOverlay(
                        player: player,
                        resetControlsTimer: _resetHideControlsTimer,
                        controlsWidget: Stack(
                          fit: StackFit.expand,
                          children: [
                            controlsWidget,
                            ListenableBuilder(
                              listenable: PlayerState(),
                              builder: (context, _) {
                                final pState = PlayerState();
                                if (!pState.showFitToastFlag) return const SizedBox.shrink();
                                return Center(
                                  child: IgnorePointer(
                                    child: AnimatedOpacity(
                                      opacity: pState.showFitToastFlag ? 1.0 : 0.0,
                                      duration: const Duration(milliseconds: 200),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.8),
                                          borderRadius: BorderRadius.circular(20.0),
                                          border: Border.all(color: Colors.white24, width: 0.5),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.aspect_ratio, color: Colors.white, size: 18.0),
                                            const SizedBox(width: 8.0),
                                            Text(
                                              'Fit: ${pState.fitName}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14.0,
                                                fontWeight: FontWeight.w600,
                                                fontFamily: 'Outfit',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            ListenableBuilder(
                              listenable: PlayerState(),
                              builder: (context, _) {
                                final pState = PlayerState();
                                if (!pState.showTorrentDashboard) return const SizedBox.shrink();
                                return Positioned(
                                  top: 80.0,
                                  right: 24.0,
                                  width: 320.0,
                                  child: _buildTorrentDashboardOverlay(),
                                );
                              },
                            ),
                            ListenableBuilder(
                              listenable: PlayerState(),
                              builder: (context, _) {
                                final pState = PlayerState();
                                final activeSkip = pState.activeSkipInterval;
                                if (!pState.showSkipButton || activeSkip == null) return const SizedBox.shrink();
                                final skipSec = (activeSkip.endTime - activeSkip.startTime).round();
                                return Positioned(
                                  bottom: 96.0,
                                  right: 24.0,
                                  child: AnimatedOpacity(
                                    opacity: pState.showSkipButton ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 300),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: _performSkip,
                                        borderRadius: BorderRadius.circular(24.0),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(24.0),
                                          child: BackdropFilter(
                                            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                                              decoration: BoxDecoration(
                                                color: const Color(0xCC0F0F11),
                                                borderRadius: BorderRadius.circular(24.0),
                                                border: Border.all(color: const Color(0xFFFF9F1C).withValues(alpha: 0.6), width: 1.0),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFFFF9F1C).withValues(alpha: 0.3),
                                                    blurRadius: 10,
                                                  )
                                                ],
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    activeSkip.skipType == 'ed'
                                                        ? Icons.skip_next
                                                        : Icons.fast_forward,
                                                    color: const Color(0xFFFF9F1C),
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 6.0),
                                                  Text(
                                                    activeSkip.skipType == 'ed'
                                                        ? 'Skip Ending (${skipSec}s)'
                                                        : activeSkip.skipType == 'op'
                                                            ? 'Skip Opening (${skipSec}s)'
                                                            : 'Skip Recap (${skipSec}s)',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontFamily: 'Outfit',
                                                      fontSize: 12.5,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );

              final double loadedPercent = _duration.inMilliseconds > 0 
                  ? (_buffer.inMilliseconds / _duration.inMilliseconds * 100).clamp(0.0, 100.0) 
                  : 0.0;
              final Duration bufferAhead = _buffer > _position ? _buffer - _position : Duration.zero;
              final bool hasTorrent = _getTorrentHash(_currentStreamUrl) != null;

              Widget finalWidget = Stack(
                fit: StackFit.expand,
                children: [
                  videoWidget,
                  // Top-center Stats Overlay (Speed & Loaded progress)
                  Positioned(
                    top: isDesktop ? 60.0 : 64.0,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _showAppBar ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(20.0),
                              border: Border.all(color: Colors.white12, width: 1.0),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasTorrent) ...[
                                  const Icon(Icons.download, color: Colors.greenAccent, size: 14.0),
                                  const SizedBox(width: 4.0),
                                  Text(
                                    _formatSpeed(_torrentSpeedBytes),
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                  const SizedBox(width: 8.0),
                                  const Text('|', style: TextStyle(color: Colors.white24, fontSize: 11.5)),
                                  const SizedBox(width: 8.0),
                                  const Icon(Icons.people_outline, color: Colors.amber, size: 14.0),
                                  const SizedBox(width: 4.0),
                                  Text(
                                    '$_torrentActivePeers/$_torrentTotalPeers',
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                  const SizedBox(width: 8.0),
                                  const Text('|', style: TextStyle(color: Colors.white24, fontSize: 11.5)),
                                  const SizedBox(width: 8.0),
                                ],
                                const Icon(Icons.cloud_download_outlined, color: Colors.blueAccent, size: 14.0),
                                const SizedBox(width: 4.0),
                                Text(
                                  'Loaded: ${loadedPercent.toStringAsFixed(1)}% (+${_formatDuration(bufferAhead)})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isDesktop)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedSlide(
                        offset: _showAppBar ? Offset.zero : const Offset(0, -1),
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: AnimatedOpacity(
                          opacity: _showAppBar ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: Container(
                            height: 40.0,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.8),
                                  Colors.black.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 8.0),
                                SizedBox(
                                  width: 32.0,
                                  height: 32.0,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16.0),
                                    onPressed: () async {
                                      try {
                                        final isFullScreen = await windowManager.isFullScreen();
                                        if (isFullScreen) {
                                          await windowManager.setFullScreen(false);
                                        }
                                      } catch (_) {}
                                      PlayerState().minimize();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8.0),
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onPanStart: (details) {
                                      windowManager.startDragging();
                                    },
                                    onDoubleTap: () async {
                                      final isMax = await windowManager.isMaximized();
                                      if (isMax) {
                                        await windowManager.unmaximize();
                                      } else {
                                        await windowManager.maximize();
                                      }
                                      _checkMaximizedState();
                                    },
                                    child: Container(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        currentTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14.0,
                                          fontFamily: 'Outfit',
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Minimize
                                _PlayerTitleBarButton(
                                  icon: Icons.remove,
                                  onPressed: () async {
                                    await windowManager.minimize();
                                  },
                                  hoverColor: Colors.white10,
                                  iconSize: 16.0,
                                ),
                                // Maximize / Restore
                                _PlayerTitleBarButton(
                                  icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                                  onPressed: () async {
                                    final isMax = await windowManager.isMaximized();
                                    if (isMax) {
                                      await windowManager.unmaximize();
                                    } else {
                                      await windowManager.maximize();
                                    }
                                    _checkMaximizedState();
                                  },
                                  hoverColor: Colors.white10,
                                  iconSize: 12.0,
                                ),
                                // Close
                                _PlayerTitleBarButton(
                                  icon: Icons.close,
                                  onPressed: () async {
                                    await windowManager.close();
                                  },
                                  hoverColor: Colors.red.withValues(alpha: 0.8),
                                  hoverIconColor: Colors.white,
                                  iconSize: 16.0,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );

              return finalWidget;
            },
          );
        },
      ),
    );

    // 2. Mobile custom controls theme configuration (just in case)
    final mobileTheme = MaterialVideoControlsTheme(
      normal: MaterialVideoControlsThemeData(
        displaySeekBar: false,
        buttonBarHeight: 88.0,
        controlsHoverDuration: _controlsHoverDuration,
        seekBarBufferColor: Colors.white24,
        seekBarPositionColor: Colors.amber,
        seekBarColor: Colors.white12,
        seekBarThumbColor: Colors.amber,
        topButtonBar: [
          if (!isDesktop) ...[
            MaterialCustomButton(
              onPressed: () {
                PlayerState().minimize();
              },
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                currentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
          ] else
            const Spacer(),
          if (widget.episodes != null && widget.episodes!.isNotEmpty)
            MaterialCustomButton(
              onPressed: _openEpisodesPanel,
              icon: const Icon(Icons.playlist_play, color: Colors.white),
            ),
          if (widget.anilistId != null || PlayerState().movieId != null)
            MaterialCustomButton(
              onPressed: () {
                _hideSettingsMenu();
                _openTorrentSelectorPanel();
              },
              icon: const Icon(Icons.swap_horizontal_circle, color: Colors.white),
            ),
          ListenableBuilder(
            listenable: AppSettings(),
            builder: (context, _) {
              final isEnhanced = AppSettings().videoEnhancementEnabled;
              return MaterialCustomButton(
                onPressed: _toggleQualityEnhancement,
                icon: Icon(
                  Icons.auto_awesome,
                  color: isEnhanced ? Colors.amber : Colors.white38,
                ),
              );
            },
          ),
          MaterialCustomButton(
            onPressed: _toggleSettingsMenu,
            icon: const Icon(Icons.settings, color: Colors.white),
          ),
        ],
        primaryButtonBar: [
          const Spacer(flex: 3),
          MaterialCustomButton(
            onPressed: () => _performSeekOffset(-10),
            icon: const Icon(Icons.replay_10, color: Colors.white, size: 48.0),
          ),
          const Spacer(),
          const MaterialPlayOrPauseButton(iconSize: 56.0),
          const Spacer(),
          MaterialCustomButton(
            onPressed: () => _performSeekOffset(10),
            icon: const Icon(Icons.forward_10, color: Colors.white, size: 48.0),
          ),
          const Spacer(flex: 3),
        ],
        bottomButtonBar: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: HoverSeekBar(player: player),
                ),
                const SizedBox(height: 4.0),
                Row(
                  children: [
                    const MaterialPositionIndicator(),
                    if (widget.isMovie != true) ...[
                      const SizedBox(width: 8.0),
                      MaterialCustomButton(
                        onPressed: _playNextEpisode,
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                      ),
                    ],
                    const Spacer(),
                     // Video Fit/Resize Button
                     Builder(
                       builder: (controlsContext) => MaterialCustomButton(
                         onPressed: () => PlayerState().cycleVideoFit(controlsContext),
                         icon: const Icon(
                           Icons.aspect_ratio,
                           color: Colors.white,
                         ),
                       ),
                     ),
                    // Subtitles On/Off Button (CC)
                    MaterialCustomButton(
                      onPressed: () {
                        final isOff = player.state.track.subtitle.id == 'no';
                        if (isOff) {
                          final firstTrack = player.state.tracks.subtitle.firstWhere(
                            (t) => t.id != 'no' && t.id != 'auto',
                            orElse: () => player.state.tracks.subtitle.first,
                          );
                          player.setSubtitleTrack(firstTrack);
                        } else {
                          player.setSubtitleTrack(SubtitleTrack.no());
                        }
                        setState(() {});
                      },
                      icon: StreamBuilder(
                        stream: player.stream.track,
                        builder: (context, _) {
                          final isOff = player.state.track.subtitle.id == 'no';
                          return Icon(
                            isOff ? Icons.closed_caption_disabled : Icons.closed_caption,
                            color: isOff ? Colors.white38 : Colors.white,
                          );
                        },
                      ),
                    ),
                    const MaterialFullscreenButton(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      fullscreen: MaterialVideoControlsThemeData(
        displaySeekBar: false,
        buttonBarHeight: 88.0,
        controlsHoverDuration: _controlsHoverDuration,
        seekBarBufferColor: Colors.white24,
        seekBarPositionColor: Colors.amber,
        seekBarColor: Colors.white12,
        seekBarThumbColor: Colors.amber,
        topButtonBar: [
          MaterialCustomButton(
            onPressed: () {
              PlayerState().minimize();
            },
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              currentTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.episodes != null && widget.episodes!.isNotEmpty)
            MaterialCustomButton(
              onPressed: _openEpisodesPanel,
              icon: const Icon(Icons.playlist_play, color: Colors.white),
            ),
          if (widget.anilistId != null || PlayerState().movieId != null)
            MaterialCustomButton(
              onPressed: () {
                _hideSettingsMenu();
                _openTorrentSelectorPanel();
              },
              icon: const Icon(Icons.swap_horizontal_circle, color: Colors.white),
            ),
          ListenableBuilder(
            listenable: AppSettings(),
            builder: (context, _) {
              final isEnhanced = AppSettings().videoEnhancementEnabled;
              return MaterialCustomButton(
                onPressed: _toggleQualityEnhancement,
                icon: Icon(
                  Icons.auto_awesome,
                  color: isEnhanced ? Colors.amber : Colors.white38,
                ),
              );
            },
          ),
          MaterialCustomButton(
            onPressed: _toggleSettingsMenu,
            icon: const Icon(Icons.settings, color: Colors.white),
          ),
        ],
        primaryButtonBar: [
          const Spacer(flex: 3),
          MaterialCustomButton(
            onPressed: () => _performSeekOffset(-10),
            icon: const Icon(Icons.replay_10, color: Colors.white, size: 48.0),
          ),
          const Spacer(),
          const MaterialPlayOrPauseButton(iconSize: 56.0),
          const Spacer(),
          MaterialCustomButton(
            onPressed: () => _performSeekOffset(10),
            icon: const Icon(Icons.forward_10, color: Colors.white, size: 48.0),
          ),
          const Spacer(flex: 3),
        ],
        bottomButtonBar: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: HoverSeekBar(player: player),
                ),
                const SizedBox(height: 4.0),
                Row(
                  children: [
                    const MaterialPositionIndicator(),
                    if (widget.isMovie != true) ...[
                      const SizedBox(width: 8.0),
                      MaterialCustomButton(
                        onPressed: _playNextEpisode,
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                      ),
                    ],
                    const Spacer(),
                     // Video Fit/Resize Button
                     Builder(
                       builder: (controlsContext) => MaterialCustomButton(
                         onPressed: () => PlayerState().cycleVideoFit(controlsContext),
                         icon: const Icon(
                           Icons.aspect_ratio,
                           color: Colors.white,
                         ),
                       ),
                     ),
                    // Subtitles On/Off Button (CC)
                    MaterialCustomButton(
                      onPressed: () {
                        final isOff = player.state.track.subtitle.id == 'no';
                        if (isOff) {
                          final firstTrack = player.state.tracks.subtitle.firstWhere(
                            (t) => t.id != 'no' && t.id != 'auto',
                            orElse: () => player.state.tracks.subtitle.first,
                          );
                          player.setSubtitleTrack(firstTrack);
                        } else {
                          player.setSubtitleTrack(SubtitleTrack.no());
                        }
                        setState(() {});
                      },
                      icon: StreamBuilder(
                        stream: player.stream.track,
                        builder: (context, _) {
                          final isOff = player.state.track.subtitle.id == 'no';
                          return Icon(
                            isOff ? Icons.closed_caption_disabled : Icons.closed_caption,
                            color: isOff ? Colors.white38 : Colors.white,
                          );
                        },
                      ),
                    ),
                    const MaterialFullscreenButton(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      child: desktopTheme,
    );

    return MouseRegion(
      cursor: _hideCursor ? SystemMouseCursors.none : MouseCursor.defer,
      onHover: (_) => _resetHideControlsTimer(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          _resetHideControlsTimer();
          if (!_playerFocusNode.hasFocus) {
            _playerFocusNode.requestFocus();
          }
        },
        onPointerMove: (_) => _resetHideControlsTimer(),
        child: Focus(
          focusNode: _playerFocusNode,
          autofocus: true,
          onKeyEvent: (FocusNode node, KeyEvent event) {
            _resetHideControlsTimer();
            return _handleKeyEvent(event);
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: null,
            body: mobileTheme,
          ),
        ),
      ),
    );
      },
    );
  }

  void _changeStremioEpisode(int epNum) {
    final List videos = widget.episodes ?? [];
    final epObj = videos.firstWhere(
      (v) => v is Map && v['episode'] == epNum,
      orElse: () => null,
    );

    String targetId = '';
    if (epObj != null && epObj['id'] != null && epObj['id'].toString().isNotEmpty) {
      targetId = epObj['id'].toString();
    } else {
      final String rawMovieId = PlayerState().movieId ?? '';
      final String cleanId = rawMovieId.replaceAll('series:', '').replaceAll('movie:', '');
      
      if (cleanId.startsWith('tt')) {
        int season = 1;
        if (epObj != null && epObj['season'] != null) {
          season = (epObj['season'] as num).toInt();
        } else if (videos.isNotEmpty && videos.first is Map && videos.first['season'] != null) {
          season = (videos.first['season'] as num).toInt();
        }
        targetId = '$cleanId:$season:$epNum';
      } else {
        targetId = '$cleanId:$epNum';
      }
    }
    
    targetId = targetId.replaceAll('series:', '').replaceAll('movie:', '');
    
    _fetchStremioStreamsAndPlay(epNum, targetId);
  }

  Future<void> _fetchStremioStreamsAndPlay(int epNum, String targetId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    final addonService = StremioAddonService();
    final enabledStreamAddons = addonService.streamAddons;

    List<dynamic> allStreams = [];
    final String type = PlayerState().isMovie == true ? 'movie' : 'series';

    final List<Future<List<dynamic>>> streamFutures = [];
    for (final addon in enabledStreamAddons) {
      if (!addon.supportsType(type) && addon.types.isNotEmpty) continue;
      if (!addon.matchesId(targetId)) continue;

      streamFutures.add(() async {
        try {
          final url = '${addon.baseUrl}/stream/$type/$targetId.json';
          final response =
              await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final List streams = data['streams'] ?? [];
            return streams
                .map((s) => Map<String, dynamic>.from(s as Map)
                  ..['addonName'] = addon.name)
                .toList();
          }
        } catch (e) {
          debugPrint('[stream/player] Error from ${addon.name}: $e');
        }
        return <dynamic>[];
      }());
    }

    final streamResults = await Future.wait(streamFutures);
    for (final res in streamResults) {
      allStreams.addAll(res);
    }

    if (mounted) {
      Navigator.pop(context); // close progress dialog
    }

    if (allStreams.isEmpty) {
      if (mounted) {
        NotificationService().show(context, 'No streams found for this episode.');
      }
      return;
    }

    if (mounted) {
      _showStremioStreamSelectorInPlayer(allStreams, epNum);
    }
  }

  void _showStremioStreamSelectorInPlayer(List<dynamic> streams, int epNum) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F11),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Stream - Episode $epNum',
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Outfit',
                            fontSize: 16.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${streams.length} links found',
                          style: const TextStyle(color: Colors.white38, fontSize: 12.0),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16.0),
                      itemCount: streams.length,
                      itemBuilder: (context, index) {
                        final stream = streams[index];
                        final String name = stream['name'] ?? stream['addonName'] ?? 'Stremio Addon';
                        final String rawTitle = stream['title'] ?? 'No details.';
                        final String cleanTitle = _cleanStreamTitle(rawTitle);
                        final tags = _getStreamTags(rawTitle);
                        final size = _getStreamSize(stream);
                        final seeders = _getStreamSeeders(stream);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10.0),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            title: Text(
                              cleanTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.0,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Wrap(
                                spacing: 8.0,
                                runSpacing: 4.0,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(4.0),
                                    ),
                                    child: Text(
                                      name.split('\n').first.toUpperCase(),
                                      style: const TextStyle(color: Colors.white60, fontSize: 8.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (size.isNotEmpty)
                                    Text(
                                      size,
                                      style: const TextStyle(color: Colors.white54, fontSize: 11.0),
                                    ),
                                  if (seeders > 0)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.arrow_upward, color: Colors.green, size: 13.0),
                                        const SizedBox(width: 2.0),
                                        Text(
                                          '$seeders',
                                          style: const TextStyle(color: Colors.green, fontSize: 11.0, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ...tags.map((tag) {
                                    final is4K = tag == '4K';
                                    final isFHD = tag == '1080p';
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                      decoration: BoxDecoration(
                                        color: is4K
                                            ? Colors.amber.withValues(alpha: 0.15)
                                            : isFHD
                                                ? Colors.blue.withValues(alpha: 0.15)
                                                : Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4.0),
                                      ),
                                      child: Text(
                                        tag,
                                        style: TextStyle(
                                          color: is4K
                                              ? Colors.amber[400]
                                              : isFHD
                                                  ? Colors.blue[400]
                                                  : Colors.white70,
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                _playStremioStream(stream, epNum);
                              },
                              child: const Text('Play', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _playStremioStream(dynamic rawStream, int epNum) {
    var stream = rawStream;
    if (stream is Map) {
      final map = Map<String, dynamic>.from(stream);
      final String? url = map['url']?.toString();
      if (map['infoHash'] == null && url != null && url.startsWith('magnet:')) {
        final match = RegExp(r'urn:btih:([a-zA-Z0-9]+)', caseSensitive: false).firstMatch(url);
        if (match != null) {
          map['infoHash'] = match.group(1);
        }
      }
      stream = map;
    }

    final mediaTitle = PlayerState().media?['title'] ?? 'Media';

    if (stream['infoHash'] != null) {
      final String hash = stream['infoHash'];
      final String name = stream['name'] ?? stream['addonName'] ?? 'Torrent Stream';
      final String title = stream['title'] ?? name;

      final torrentStream = TorrentStream(
        title: title,
        link: 'magnet:?xt=urn:btih:$hash',
        seeders: _getStreamSeeders(stream),
        leechers: 0,
        downloads: 0,
        hash: hash,
        size: stream['size'] != null ? (int.tryParse(stream['size'].toString()) ?? 0) : 0,
        accuracy: 'high',
        type: PlayerState().isMovie == true ? 'movie' : 'series',
        extensionName: stream['addonName'] ?? 'Stremio Addon',
      );

      final String? movieId = PlayerState().movieId;
      final int parsedIntId = movieId != null ? (_parseImdbIdToInt(movieId)) : 0;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return PlaybackProgressDialog(
            stream: torrentStream,
            parentContext: context,
            anilistId: parsedIntId,
            movieId: movieId,
            episodeNumber: epNum,
            titles: [mediaTitle],
            episodeCount: widget.episodeCount ?? 1,
            isMovie: widget.isMovie ?? false,
            media: widget.media,
            episodes: widget.episodes,
            onStreamSelected: (String streamUrl, String title) {
              PlayerState().updateActiveEpisode(
                streamUrl: streamUrl,
                title: title,
                episodeNumber: epNum,
              );
            },
          );
        },
      );
      return;
    }

    String streamUrl = stream['url'] ?? '';
    if (streamUrl.isNotEmpty) {
      Map<String, String>? headers;
      if (stream['behaviorHints'] is Map) {
        final bh = stream['behaviorHints'] as Map;
        if (bh['proxyHeaders'] is Map && bh['proxyHeaders']['request'] is Map) {
          headers = (bh['proxyHeaders']['request'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
        } else if (bh['headers'] is Map) {
          headers = (bh['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
      if (headers == null && stream['headers'] is Map) {
        headers = (stream['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
      }

      PlayerState().updateActiveEpisode(
        streamUrl: streamUrl,
        title: '$mediaTitle - Episode $epNum',
        episodeNumber: epNum,
        headers: headers,
      );
    }
  }

  String _cleanStreamTitle(String title) {
    final lines = title.split('\n');
    if (lines.isNotEmpty) {
      return lines[0].trim();
    }
    return title;
  }

  List<String> _getStreamTags(String title) {
    final List<String> tags = [];
    final t = title.toLowerCase();
    if (t.contains('2160p') || t.contains('4k') || t.contains('uhd')) tags.add('4K');
    else if (t.contains('1080p') || t.contains('fhd')) tags.add('1080p');
    else if (t.contains('720p') || t.contains('hd')) tags.add('720p');
    else if (t.contains('480p') || t.contains('sd')) tags.add('480p');

    if (t.contains('hdr')) tags.add('HDR');
    if (t.contains('dv') || t.contains('dolby vision')) tags.add('DV');
    if (t.contains('dual') || t.contains('dual-audio') || t.contains('multi')) tags.add('Dual Audio');
    return tags;
  }

  String _getStreamSize(dynamic stream) {
    if (stream['size'] != null) {
      final sizeBytes = int.tryParse(stream['size'].toString()) ?? 0;
      if (sizeBytes > 0) {
        final gb = sizeBytes / (1024 * 1024 * 1024);
        if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
        final mb = sizeBytes / (1024 * 1024);
        return '${mb.toStringAsFixed(0)} MB';
      }
    }
    final title = stream['title']?.toString() ?? '';
    final match = RegExp(r'\b(\d+(?:\.\d+)?\s*(?:GB|MB))\b', caseSensitive: false).firstMatch(title);
    return match?.group(1) ?? '';
  }

  int _getStreamSeeders(dynamic stream) {
    if (stream['seeders'] != null) {
      return int.tryParse(stream['seeders'].toString()) ?? 0;
    }
    final title = stream['title']?.toString() ?? '';
    final match = RegExp(r'(?:👤|seeders:?)\s*(\d+)\b', caseSensitive: false).firstMatch(title);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  int _parseImdbIdToInt(String imdbId) {
    final digits = imdbId.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digits) ?? 0;
  }

  Widget _buildTorrentDashboardOverlay() {
    final ps = PlayerState();
    double maxSpeed = 1.0; 
    for (final s in ps.torrentSpeedHistory) {
      if (s > maxSpeed) maxSpeed = s;
    }
    maxSpeed = maxSpeed.ceilToDouble();

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.08),
            blurRadius: 16.0,
            spreadRadius: 2.0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.analytics_outlined, color: Colors.cyanAccent, size: 16.0),
                  SizedBox(width: 8.0),
                  Text(
                    'STREAM DIAGNOSTICS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  ps.setShowTorrentDashboard(false);
                },
                child: const Icon(Icons.close, color: Colors.white54, size: 16.0),
              ),
            ],
          ),
          const SizedBox(height: 12.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Speed', style: TextStyle(color: Colors.white38, fontSize: 10.0, fontFamily: 'Outfit')),
                  const SizedBox(height: 2.0),
                  Text(
                    _formatSpeed(ps.torrentSpeedBytes),
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 14.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Active / Total Peers', style: TextStyle(color: Colors.white38, fontSize: 10.0, fontFamily: 'Outfit')),
                  const SizedBox(height: 2.0),
                  Text(
                    '${ps.torrentActivePeers} / ${ps.torrentTotalPeers}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          SizedBox(
            height: 100.0,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(height: 1.0, color: Colors.white10),
                      Container(height: 1.0, color: Colors.white10),
                      Container(height: 1.0, color: Colors.white10),
                    ],
                  ),
                ),
                Positioned(
                  top: 2.0,
                  left: 2.0,
                  child: Text('${maxSpeed.toStringAsFixed(0)} MB/s', style: const TextStyle(color: Colors.white30, fontSize: 8.0, fontFamily: 'Outfit')),
                ),
                Positioned(
                  bottom: 2.0,
                  left: 2.0,
                  child: const Text('0 MB/s', style: TextStyle(color: Colors.white30, fontSize: 8.0, fontFamily: 'Outfit')),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SpeedGraphPainter(ps.torrentSpeedHistory, maxSpeed),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


}

class _SpeedGraphPainter extends CustomPainter {
  final List<double> history;
  final double maxSpeed;

  _SpeedGraphPainter(this.history, this.maxSpeed);

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final paint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.85)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.cyanAccent.withOpacity(0.25),
          Colors.cyanAccent.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();

    final double dx = size.width / 30.0; 
    final double scaleY = maxSpeed > 0 ? size.height / maxSpeed : 1.0;

    final int historyLength = history.length;
    final double startX = size.width - (historyLength - 1) * dx;

    for (int i = 0; i < historyLength; i++) {
      final double x = startX + i * dx;
      final double y = size.height - (history[i] * scaleY).clamp(0.0, size.height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = startX + (i - 1) * dx;
        final prevY = size.height - (history[i - 1] * scaleY).clamp(0.0, size.height);
        final controlX1 = prevX + dx / 2;
        final controlY1 = prevY;
        final controlX2 = prevX + dx / 2;
        final controlY2 = y;
        
        path.cubicTo(controlX1, controlY1, controlX2, controlY2, x, y);
        fillPath.cubicTo(controlX1, controlY1, controlX2, controlY2, x, y);
      }
    }

    if (historyLength > 0) {
      fillPath.lineTo(size.width, size.height);
      fillPath.close();
      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedGraphPainter oldDelegate) => true;
}

class _SettingsOverlayCard extends StatefulWidget {
  final Player player;
  final VoidCallback onClose;
  final ValueNotifier<bool> isQualityEnhancedNotifier;
  final VoidCallback onToggleQualityEnhanced;
  final int? anilistId;
  final List<String>? titles;
  final int? episodeCount;
  final int? episodeNumber;
  final bool? isMovie;
  final dynamic media;
  final VoidCallback? onOpenTorrentPanel;

  const _SettingsOverlayCard({
    required this.player,
    required this.onClose,
    required this.isQualityEnhancedNotifier,
    required this.onToggleQualityEnhanced,
    this.anilistId,
    this.titles,
    this.episodeCount,
    this.episodeNumber,
    this.isMovie,
    this.media,
    this.onOpenTorrentPanel,
  });

  @override
  State<_SettingsOverlayCard> createState() => _SettingsOverlayCardState();
}

class _SettingsOverlayCardState extends State<_SettingsOverlayCard> {
  int _pageIndex = 0; // 0: main, 1: speed, 2: audio, 3: subs
  late final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _subscriptions.add(widget.player.stream.track.listen((_) {
      if (mounted) setState(() {});
    }));
    _subscriptions.add(widget.player.stream.rate.listen((_) {
      if (mounted) setState(() {});
    }));
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  String _getAudioTrackLabel(AudioTrack track) {
    if (track.id == 'auto') {
      final actualTracks = widget.player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
      if (actualTracks.isNotEmpty) {
        return 'Auto (${_getAudioTrackLabel(actualTracks.first)})';
      }
      return 'Auto';
    }
    if (track.id == 'no') return 'Off';
    final parts = [
      track.title,
      track.language,
    ].where((s) => s != null && s.isNotEmpty).toList();
    if (parts.isEmpty) return 'Track ${track.id}';
    return parts.join(' - ');
  }

  String _getSubtitleTrackLabel(SubtitleTrack track) {
    if (track.id == 'auto') {
      final actualTracks = widget.player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
      if (actualTracks.isNotEmpty) {
        return 'Auto (${_getSubtitleTrackLabel(actualTracks.first)})';
      }
      return 'Auto';
    }
    if (track.id == 'no') return 'Off';
    final parts = [
      track.title,
      track.language,
    ].where((s) => s != null && s.isNotEmpty).toList();
    if (parts.isEmpty) return 'Track ${track.id}';
    return parts.join(' - ');
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    switch (_pageIndex) {
      case 1:
        child = _buildSpeedMenu();
        break;
      case 2:
        child = _buildAudioMenu();
        break;
      case 3:
        child = _buildSubtitlesMenu();
        break;
      case 4:
        child = _buildHstreamQualityMenu();
        break;
      default:
        child = _buildMainMenu();
        break;
    }

    final mediaQuery = MediaQuery.of(context);
    final isMobileLandscape = mediaQuery.size.height < 500.0;
    final maxOverlayHeight = isMobileLandscape
        ? (mediaQuery.size.height - 60.0)
        : 380.0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxOverlayHeight),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        child: child,
      ),
    );
  }

  Widget _buildMainMenu() {
    final rate = widget.player.state.rate;
    final currentAudio = widget.player.state.track.audio;
    final currentSubtitle = widget.player.state.track.subtitle;

    final audioLabel = _getAudioTrackLabel(currentAudio);
    final subtitleLabel = _getSubtitleTrackLabel(currentSubtitle);

    // Hstream quality label
    final hstreamSources = PlayerState().hstreamSources ?? [];
    final currentHstreamUrl = PlayerState().streamUrl;
    final activeHstreamSource = hstreamSources.firstWhere(
      (s) => s.url == currentHstreamUrl,
      orElse: () => hstreamSources.isNotEmpty ? hstreamSources.first : const HstreamSource(name: '', quality: '', url: '', type: ''),
    );
    final hstreamQualityLabel = activeHstreamSource.quality;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Settings",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.0, fontFamily: 'Outfit'),
            ),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        ListTile(
          dense: true,
          leading: const Icon(Icons.speed, color: Colors.white70, size: 18),
          title: const Text("Playback Speed", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${rate}x", style: const TextStyle(color: Colors.white38, fontSize: 12.0)),
              const Icon(Icons.chevron_right, color: Colors.white30, size: 16),
            ],
          ),
          onTap: () => setState(() => _pageIndex = 1),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.audiotrack, color: Colors.white70, size: 18),
          title: const Text("Audio Track", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  audioLabel,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 12.0),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white30, size: 16),
            ],
          ),
          onTap: () => setState(() => _pageIndex = 2),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.subtitles, color: Colors.white70, size: 18),
          title: const Text("Subtitles", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  subtitleLabel,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 12.0),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white30, size: 16),
            ],
          ),
          onTap: () => setState(() => _pageIndex = 3),
        ),
        if (hstreamSources.isNotEmpty)
          ListTile(
            dense: true,
            leading: const Icon(Icons.video_settings, color: Colors.white70, size: 18),
            title: const Text("Video Quality", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hstreamQualityLabel, style: const TextStyle(color: Colors.white38, fontSize: 12.0)),
                const Icon(Icons.chevron_right, color: Colors.white30, size: 16),
              ],
            ),
            onTap: () => setState(() => _pageIndex = 4),
          ),

        ListTile(
          dense: true,
          leading: const Icon(Icons.play_circle_outline, color: Colors.white70, size: 18),
          title: const Text("Auto Play Streams", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
          trailing: SizedBox(
            height: 24,
            child: ListenableBuilder(
              listenable: AppSettings(),
              builder: (context, _) {
                return Switch(
                  value: AppSettings().autoPlay,
                  activeColor: Colors.amber,
                  onChanged: (val) {
                    AppSettings().setAutoPlay(val);
                  },
                );
              },
            ),
          ),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.skip_next, color: Colors.white70, size: 18),
          title: const Text("Auto Play Next Episode", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
          trailing: SizedBox(
            height: 24,
            child: ListenableBuilder(
              listenable: AppSettings(),
              builder: (context, _) {
                return Switch(
                  value: AppSettings().autoNext,
                  activeColor: Colors.amber,
                  onChanged: (val) {
                    AppSettings().setAutoNext(val);
                  },
                );
              },
            ),
          ),
        ),
        if (widget.anilistId != null) ...[
          ListTile(
            dense: true,
            leading: const Icon(Icons.skip_next_outlined, color: Colors.white70, size: 18),
            title: const Text("Auto Skip Intro/Outro", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
            trailing: SizedBox(
              height: 24,
              child: ListenableBuilder(
                listenable: AppSettings(),
                builder: (context, _) {
                  return Switch(
                    value: AppSettings().autoSkipIntro,
                    activeColor: Colors.amber,
                    onChanged: (val) {
                      AppSettings().setAutoSkipIntro(val);
                    },
                  );
                },
              ),
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.block, color: Colors.white70, size: 18),
            title: const Text("Auto Skip Filler Episodes", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
            trailing: SizedBox(
              height: 24,
              child: ListenableBuilder(
                listenable: AppSettings(),
                builder: (context, _) {
                  return Switch(
                    value: AppSettings().autoSkipFiller,
                    activeColor: Colors.amber,
                    onChanged: (val) {
                      AppSettings().setAutoSkipFiller(val);
                    },
                  );
                },
              ),
            ),
          ),
        ],
        if (widget.anilistId != null || PlayerState().movieId != null) ...[
          const Divider(color: Colors.white10, height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.swap_horizontal_circle, color: Colors.white70, size: 18),
            title: const Text("Change Stream", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
            trailing: const Icon(Icons.chevron_right, color: Colors.white30, size: 16),
            onTap: widget.onOpenTorrentPanel,
          ),
        ],
        if (PlayerState().streamUrl != null &&
            (RegExp(r'link=([a-fA-F0-9]+)').hasMatch(PlayerState().streamUrl!) ||
             PlayerState().streamUrl!.startsWith('magnet:?xt=urn:btih:'))) ...[
          const Divider(color: Colors.white10, height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.analytics_outlined, color: Colors.white70, size: 18),
            title: const Text("Show Stats Dashboard", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
            trailing: SizedBox(
              height: 24,
              child: ListenableBuilder(
                listenable: PlayerState(),
                builder: (context, _) {
                  return Switch(
                    value: PlayerState().showTorrentDashboard,
                    activeColor: Colors.amber,
                    onChanged: (val) {
                      PlayerState().setShowTorrentDashboard(val);
                    },
                  );
                },
              ),
            ),
          ),
        ],
        const Divider(color: Colors.white10, height: 1),
        ListTile(
          dense: true,
          leading: const Icon(Icons.speed, color: Colors.white70, size: 18),
          title: const Text("Hardware Acceleration", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
          trailing: SizedBox(
            height: 24,
            child: ListenableBuilder(
              listenable: AppSettings(),
              builder: (context, _) {
                return Switch(
                  value: AppSettings().hardwareAccelerationEnabled,
                  activeColor: Colors.amber,
                  onChanged: (val) {
                    widget.onClose();
                    PlayerState().toggleHardwareAcceleration(val);
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildHstreamQualityMenu() {
    final sources = PlayerState().hstreamSources ?? [];
    final currentUrl = PlayerState().streamUrl;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMenuHeader("Video Quality"),
        const Divider(color: Colors.white10, height: 1),
        ...sources.map((source) {
          final isSelected = source.url == currentUrl;
          return ListTile(
            dense: true,
            title: Text(
              source.name,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFF9F1C) : Colors.white,
                fontSize: 13.0,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontFamily: 'Outfit',
              ),
            ),
            trailing: isSelected ? const Icon(Icons.check, color: Color(0xFFFF9F1C), size: 16) : null,
            onTap: () async {
              widget.onClose(); // Hide overlay
              try {
                await PlayerState().switchHstreamQuality(source.url);
              } catch (_) {}
            },
          );
        }).toList(),
        const SizedBox(height: 6),
      ],
    );
  }


  Widget _buildSpeedMenu() {
    final rate = widget.player.state.rate;
    final speeds = [0.5, 1.0, 1.25, 1.5, 2.0];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMenuHeader("Playback Speed"),
        const Divider(color: Colors.white10, height: 1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250.0),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            children: speeds.map((speed) {
              final isSelected = rate == speed;
              return ListTile(
                dense: true,
                title: Text("${speed}x", style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
                trailing: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                onTap: () async {
                  await widget.player.setRate(speed);
                  if (mounted) setState(() {});
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioMenu() {
    final currentAudio = widget.player.state.track.audio;
    final audioTracks = widget.player.state.tracks.audio.where((t) => t.id != 'auto').toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMenuHeader("Audio Track"),
        const Divider(color: Colors.white10, height: 1),
        if (audioTracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Text("No audio tracks found", style: TextStyle(color: Colors.white38, fontSize: 12.0)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: audioTracks.length,
            itemBuilder: (context, index) {
              final track = audioTracks[index];
              final isSelected = currentAudio == track;
              return ListTile(
                dense: true,
                title: Text(_getAudioTrackLabel(track), style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
                trailing: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                onTap: () async {
                  await widget.player.setAudioTrack(track);
                  if (mounted) setState(() {});
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildSubtitlesMenu() {
    final currentSubtitle = widget.player.state.track.subtitle;
    final subtitleTracks = widget.player.state.tracks.subtitle.where((t) => t.id != 'auto').toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMenuHeader("Subtitles"),
        const Divider(color: Colors.white10, height: 1),
        
        // Buttons for Subtitles ON/OFF
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    if (currentSubtitle.id == 'no') {
                      final firstTrack = widget.player.state.tracks.subtitle.firstWhere(
                        (t) => t.id != 'no' && t.id != 'auto',
                        orElse: () => widget.player.state.tracks.subtitle.first,
                      );
                      await widget.player.setSubtitleTrack(firstTrack);
                      if (mounted) setState(() {});
                    }
                  },
                  borderRadius: BorderRadius.circular(6.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    decoration: BoxDecoration(
                      color: currentSubtitle.id != 'no' ? Colors.white : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6.0),
                      border: Border.all(color: currentSubtitle.id != 'no' ? Colors.white : Colors.white10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "ON",
                      style: TextStyle(
                        color: currentSubtitle.id != 'no' ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.0,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    if (currentSubtitle.id != 'no') {
                      await widget.player.setSubtitleTrack(SubtitleTrack.no());
                      if (mounted) setState(() {});
                    }
                  },
                  borderRadius: BorderRadius.circular(6.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    decoration: BoxDecoration(
                      color: currentSubtitle.id == 'no' ? Colors.white : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6.0),
                      border: Border.all(color: currentSubtitle.id == 'no' ? Colors.white : Colors.white10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "OFF",
                      style: TextStyle(
                        color: currentSubtitle.id == 'no' ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.0,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Subtitle Style Customizer Button
        Padding(
          padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0),
          child: InkWell(
            onTap: () {
              widget.onClose(); // Hide the settings overlay menu first
              _showSubtitleCustomizationDialog();
            },
            borderRadius: BorderRadius.circular(6.0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tune, color: Colors.white, size: 14.0),
                  SizedBox(width: 8.0),
                  Text(
                    "Customize Style",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.0,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        if (subtitleTracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Text("No subtitle tracks found", style: TextStyle(color: Colors.white38, fontSize: 12.0)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: subtitleTracks.length,
            itemBuilder: (context, index) {
              final track = subtitleTracks[index];
              final isSelected = currentSubtitle == track;
              return ListTile(
                dense: true,
                title: Text(_getSubtitleTrackLabel(track), style: const TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
                trailing: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                onTap: () async {
                  await widget.player.setSubtitleTrack(track);
                  if (mounted) setState(() {});
                },
              );
            },
          ),
      ],
    );
  }

  void _showSubtitleCustomizationDialog() {
    final settings = AppSettings();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Re-read current values from AppSettings
            final bool bgEnabled = settings.subtitlesBgEnabled;
            final int bgColor = settings.subtitlesBgColor;
            final double bgOpacity = settings.subtitlesBgOpacity;
            final String fontFamily = settings.subtitlesFontFamily;
            final double fontSize = settings.subtitlesFontSize;
            final bool isBold = settings.subtitlesBold;
            final bool isItalic = settings.subtitlesItalic;
            final int textColor = settings.subtitlesTextColor;
            final bool shadowEnabled = settings.subtitlesShadowEnabled;
            final int shadowColor = settings.subtitlesShadowColor;
            final double shadowOpacity = settings.subtitlesShadowOpacity;
            final double shadowBlurRadius = settings.subtitlesShadowBlurRadius;
            final double shadowOffset = settings.subtitlesShadowOffset;

            final subtitlePreviewStyle = TextStyle(
              height: 1.4,
              fontSize: (fontSize * 0.9).clamp(10.0, 32.0),
              color: Color(textColor),
              backgroundColor: bgEnabled ? Color(bgColor).withValues(alpha: bgOpacity) : null,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
              fontFamily: fontFamily,
              shadows: shadowEnabled
                  ? [
                      Shadow(
                        offset: Offset(-shadowOffset, -shadowOffset),
                        color: Color(shadowColor).withValues(alpha: shadowOpacity),
                        blurRadius: shadowBlurRadius,
                      ),
                      Shadow(
                        offset: Offset(shadowOffset, -shadowOffset),
                        color: Color(shadowColor).withValues(alpha: shadowOpacity),
                        blurRadius: shadowBlurRadius,
                      ),
                      Shadow(
                        offset: Offset(shadowOffset, shadowOffset),
                        color: Color(shadowColor).withValues(alpha: shadowOpacity),
                        blurRadius: shadowBlurRadius,
                      ),
                      Shadow(
                        offset: Offset(-shadowOffset, shadowOffset),
                        color: Color(shadowColor).withValues(alpha: shadowOpacity),
                        blurRadius: shadowBlurRadius,
                      ),
                    ]
                  : null,
            );

            return AlertDialog(
              backgroundColor: const Color(0xFF0F0F11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              titlePadding: const EdgeInsets.all(20.0),
              contentPadding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 20.0),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Subtitle Quick Tuning",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20.0),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440.0,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Drag & Drop Screen Position Panel
                      const Text(
                        "Drag text inside panel to adjust position:",
                        style: TextStyle(color: Colors.white38, fontSize: 11.5, fontFamily: 'Outfit'),
                      ),
                      const SizedBox(height: 8.0),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final boxWidth = constraints.maxWidth;
                          const boxHeight = 180.0;

                          const minY = 10.0;
                          const maxY = boxHeight - 45.0;
                          const minOffset = 10.0;
                          const maxOffset = 500.0;

                          const minOffsetX = -400.0;
                          const maxOffsetX = 400.0;
                          final maxX = boxWidth / 2.0 - 80.0;

                          final double currentBottom = minY + ((settings.subtitlesPositionOffset - minOffset) / (maxOffset - minOffset)) * (maxY - minY);
                          final double currentX = (settings.subtitlesXOffset / maxOffsetX) * maxX;

                          return GestureDetector(
                            onPanUpdate: (details) {
                              final double dy = details.delta.dy;
                              final double dx = details.delta.dx;

                              final double newOffset = (settings.subtitlesPositionOffset - (dy * (maxOffset - minOffset) / (maxY - minY)))
                                  .clamp(minOffset, maxOffset);
                              final double newXOffset = (settings.subtitlesXOffset + (dx * maxOffsetX / maxX))
                                  .clamp(minOffsetX, maxOffsetX);

                              settings.setSubtitlesXOffset(newXOffset, save: false);
                              settings.setSubtitlesPositionOffset(newOffset, save: false);
                              setDialogState(() {});
                            },
                            onPanEnd: (_) => settings.saveSubtitlesPosition(),
                            onPanCancel: () => settings.saveSubtitlesPosition(),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Container(
                                height: boxHeight,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12.0),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0xFF1E2026), Color(0xFF0F1013)],
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    // Playback preview background mockup lines
                                    Positioned(
                                      top: 40,
                                      child: Icon(
                                        Icons.movie_outlined,
                                        color: Colors.white.withValues(alpha: 0.03),
                                        size: 100,
                                      ),
                                    ),
                                    Positioned(
                                      top: 20,
                                      left: 20,
                                      child: Container(
                                        width: 80,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 32,
                                      left: 20,
                                      child: Container(
                                        width: 50,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                    ),
                                    
                                    // Center line guide
                                    Positioned.fill(
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: Container(
                                          height: 0.5,
                                          color: Colors.white.withValues(alpha: 0.03),
                                        ),
                                      ),
                                    ),

                                    // Preview text block
                                    Positioned(
                                      bottom: currentBottom,
                                      left: 16.0 + currentX,
                                      right: 16.0 - currentX,
                                      child: Center(
                                        child: Text(
                                          "Subtitles look like this",
                                          style: subtitlePreviewStyle,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                      ),
                      const SizedBox(height: 16.0),

                      // 2. Font size slider
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Quick Font Size",
                                style: TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                              ),
                              Text(
                                "${fontSize.toInt()} px",
                                style: const TextStyle(color: Color(0xFF3A86FF), fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2.0,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                              activeTrackColor: const Color(0xFF3A86FF),
                              inactiveTrackColor: Colors.white10,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: fontSize,
                              min: 10.0,
                              max: 40.0,
                              onChanged: (val) {
                                settings.setSubtitlesFontSize(val);
                                setDialogState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12.0),

                      // 3. Navigation link to detailed settings page
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3A86FF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        onPressed: () {
                          // Close quick dialog
                          Navigator.pop(dialogContext);
                          
                          // Push main app settings with subtitles category pre-selected
                          final AppMode appMode = widget.anilistId != null ? AppMode.anime : AppMode.movies;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SettingsPage(
                                mode: appMode,
                                initialCategory: SettingsCategory.subtitles,
                              ),
                            ),
                          );
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.tune, size: 16.0),
                            SizedBox(width: 8.0),
                            Text(
                              "All Subtitle Settings...",
                              style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMenuHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 18),
            onPressed: () => setState(() => _pageIndex = 0),
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(8.0),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.0, fontFamily: 'Outfit'),
          ),
        ],
      ),
    );
  }
}

class _PlayerEpisodeCard extends StatefulWidget {
  final int epNum;
  final String title;
  final String thumbnail;
  final bool isPlaying;
  final int? anilistId;

  const _PlayerEpisodeCard({
    required this.epNum,
    required this.title,
    required this.thumbnail,
    required this.isPlaying,
    this.anilistId,
  });

  @override
  State<_PlayerEpisodeCard> createState() => _PlayerEpisodeCardState();
}

class _PlayerEpisodeCardState extends State<_PlayerEpisodeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: const Color(0xFF141416), // Solid dark grey card background
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(
                    color: widget.isPlaying 
                        ? Colors.amber.withValues(alpha: 0.6) 
                        : (widget.anilistId != null && FillerService().isFiller(widget.anilistId!, widget.epNum)
                            ? Colors.amber.withValues(alpha: 0.5)
                            : (_isHovered ? Colors.white30 : Colors.white10)),
                    width: widget.isPlaying ? 2.0 : (widget.anilistId != null && FillerService().isFiller(widget.anilistId!, widget.epNum) ? 1.5 : 1.0),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5.0),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: widget.thumbnail.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: widget.thumbnail,
                                fit: BoxFit.cover,
                                memCacheWidth: 640,
                                placeholder: (context, url) => _buildPlaceholder(),
                                errorWidget: (context, url, error) => _buildPlaceholder(),
                              )
                            : _buildPlaceholder(),
                      ),
                    if (widget.isPlaying)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.6),
                          child: const Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.play_circle_filled, color: Colors.amber, size: 24.0),
                                SizedBox(width: 4.0),
                                Text(
                                  "PLAYING",
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10.0,
                                    fontFamily: 'Outfit',
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      Positioned.fill(
                        child: AnimatedOpacity(
                          opacity: _isHovered ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.4),
                            child: const Center(
                              child: CircleAvatar(
                                radius: 16.0,
                                backgroundColor: Colors.white,
                                child: Icon(Icons.play_arrow, color: Colors.black, size: 18.0),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Filler Badge (Bottom-Left)
                    () {
                      if (widget.anilistId == null) return const SizedBox.shrink();
                      final fillerType = FillerService().getFillerType(widget.anilistId!, widget.epNum);
                      if (fillerType != null &&
                          (fillerType.toLowerCase() == 'filler' ||
                           fillerType.toLowerCase() == 'mixed canon/filler')) {
                        final isFillerType = fillerType.toLowerCase() == 'filler';
                        return Positioned(
                          bottom: 6.0,
                          left: 6.0,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isFillerType ? 3.0 : 4.0,
                              vertical: isFillerType ? 1.0 : 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: _getFillerColor(fillerType),
                              borderRadius: BorderRadius.circular(3.0),
                              border: isFillerType
                                  ? Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.0)
                                  : null,
                            ),
                            child: isFillerType
                                ? const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 9.0),
                                      SizedBox(width: 2.0),
                                      Text(
                                        'Filler',
                                        style: TextStyle(
                                          color: Colors.amber,
                                          fontSize: 7.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    _getFillerLabel(fillerType),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            "Episode ${widget.epNum}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: widget.isPlaying ? Colors.amber : Colors.white70,
              fontSize: 11.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'Outfit',
            ),
          ),
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10.0,
              fontFamily: 'Outfit',
            ),
          ),
        ],
      ),
    ),
    );
  }

  Color _getFillerColor(String type) {
    switch (type.toLowerCase()) {
      case 'filler':
        return Colors.amber.withValues(alpha: 0.15); // Transparent Yellow
      case 'anime canon':
        return const Color(0xFF8338EC); // Purple
      case 'mixed canon/filler':
        return const Color(0xFFF77F00); // Orange
      default:
        return Colors.blueGrey;
    }
  }

  String _getFillerLabel(String type) {
    if (type.toLowerCase() == 'mixed canon/filler') return 'Mixed';
    return type;
  }


  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF141416), // Solid dark grey background
      child: const Center(
        child: Icon(Icons.movie, color: Colors.white10, size: 32.0),
      ),
    );
  }
}

class _PlayerTitleBarButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color hoverColor;
  final Color? hoverIconColor;
  final double iconSize;

  const _PlayerTitleBarButton({
    required this.icon,
    required this.onPressed,
    required this.hoverColor,
    this.hoverIconColor,
    required this.iconSize,
  });

  @override
  State<_PlayerTitleBarButton> createState() => _PlayerTitleBarButtonState();
}

class _PlayerTitleBarButtonState extends State<_PlayerTitleBarButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 40.0,
          height: 30.0,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _isHovering ? widget.hoverColor : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _isHovering && widget.hoverIconColor != null
                ? widget.hoverIconColor
                : Colors.white60,
          ),
        ),
      ),
    );
  }
}

class DynamicSubtitlePadding extends EdgeInsets {
  final double baseOffset;
  final double subtitlesXOffset;
  final double videoWidth;
  final double videoHeight;

  const DynamicSubtitlePadding({
    required this.baseOffset,
    required this.subtitlesXOffset,
    required this.videoWidth,
    required this.videoHeight,
  }) : super.only();

  @override
  double get bottom {
    final view = ui.PlatformDispatcher.instance.implicitView;
    if (view == null) return baseOffset;

    final double screenWidth = view.physicalSize.width / view.devicePixelRatio;
    final double screenHeight = view.physicalSize.height / view.devicePixelRatio;

    final videoAspectRatio = videoWidth > 0 && videoHeight > 0
        ? (videoWidth / videoHeight)
        : 16 / 9;

    double bottomPadding = baseOffset;
    if (screenWidth > 0 && screenHeight > 0) {
      final double playerAspectRatio = screenWidth / screenHeight;
      if (playerAspectRatio < videoAspectRatio) {
        // Top and bottom black bars exist (portrait mode)
        final double videoRenderedHeight = screenWidth / videoAspectRatio;
        final double blackBarHeight = (screenHeight - videoRenderedHeight) / 2.0;
        bottomPadding += blackBarHeight;
      }
    }

    // Clamp bottomPadding dynamically to prevent shifting subtitles to the top in landscape or portrait
    final isLandscape = screenWidth > screenHeight;
    if (isLandscape) {
      bottomPadding = bottomPadding.clamp(0.0, screenHeight * 0.22);
    } else {
      bottomPadding = bottomPadding.clamp(0.0, screenHeight * 0.45);
    }

    return bottomPadding;
  }

  @override
  double get left => 16.0 + (subtitlesXOffset > 0 ? subtitlesXOffset : 0.0);

  @override
  double get right => 16.0 + (subtitlesXOffset < 0 ? -subtitlesXOffset : 0.0);

  @override
  double get top => 16.0;
}

class HoverSeekBar extends StatefulWidget {
  final Player player;
  const HoverSeekBar({super.key, required this.player});

  @override
  State<HoverSeekBar> createState() => _HoverSeekBarState();
}

class _HoverSeekBarState extends State<HoverSeekBar> {
  double? _hoverX;
  bool _isHovering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;

  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _buffer = widget.player.state.buffer;

    _subscriptions.add(widget.player.stream.position.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subscriptions.add(widget.player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subscriptions.add(widget.player.stream.buffer.listen((b) {
      if (mounted) setState(() => _buffer = b);
    }));
  }

  @override
  void dispose() {
    for (var s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final int hours = d.inHours;
    final int minutes = d.inMinutes.remainder(60);
    final int seconds = d.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_duration.inMilliseconds == 0) return const SizedBox(height: 24.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        
        final posMs = _position.inMilliseconds.toDouble();
        final durMs = _duration.inMilliseconds.toDouble();
        final bufMs = _buffer.inMilliseconds.toDouble();

        final double posPercent = (posMs / durMs).clamp(0.0, 1.0);
        final double bufPercent = (bufMs / durMs).clamp(0.0, 1.0);

        // Hover calculations
        Duration? hoverTime;
        if (_isHovering && _hoverX != null && width > 0) {
          final double percent = (_hoverX! / width).clamp(0.0, 1.0);
          hoverTime = Duration(milliseconds: (percent * durMs).toInt());
        }

        void seekToPercent(double percent) {
          final targetMs = (percent * durMs).toInt();
          widget.player.seek(Duration(milliseconds: targetMs));
        }

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          onHover: (event) {
            setState(() {
              _hoverX = event.localPosition.dx;
              _isHovering = true;
            });
          },
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              final box = context.findRenderObject() as RenderBox;
              final localPos = box.globalToLocal(details.globalPosition);
              final double percent = (localPos.dx / width).clamp(0.0, 1.0);
              seekToPercent(percent);
            },
            onTapDown: (details) {
              final double percent = (details.localPosition.dx / width).clamp(0.0, 1.0);
              seekToPercent(percent);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Track Container
                Container(
                  height: 24.0,
                  alignment: Alignment.center,
                  child: Stack(
                    children: [
                      // Base Track
                      Container(
                        height: 5.0,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      // Buffer Track
                      FractionallySizedBox(
                        widthFactor: bufPercent,
                        child: Container(
                          height: 5.0,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      ),
                      // Position Track
                      FractionallySizedBox(
                        widthFactor: posPercent,
                        child: Container(
                          height: 5.0,
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Hover / Seeking Indicator Tooltip (Float above seeking track)
                if (_isHovering && hoverTime != null && _hoverX != null)
                  Positioned(
                    left: (_hoverX! - 45.0).clamp(0.0, width - 90.0), // center tooltip and keep within bounds
                    top: -30.0, // float above
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A),
                        borderRadius: BorderRadius.circular(4.0),
                        border: Border.all(color: Colors.white24, width: 0.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 5.0,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        _formatDuration(hoverTime),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ),
                  ),

                // Thumb handle
                Positioned(
                  left: (posPercent * width) - 6.0,
                  top: 6.0,
                  child: Container(
                    width: 12.0,
                    height: 12.0,
                    decoration: const BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 3.0,
                          spreadRadius: 1.0,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayerGestureOverlay extends StatefulWidget {
  final Player player;
  final Widget controlsWidget;
  final VoidCallback resetControlsTimer;

  const _PlayerGestureOverlay({
    super.key,
    required this.player,
    required this.controlsWidget,
    required this.resetControlsTimer,
  });

  @override
  State<_PlayerGestureOverlay> createState() => _PlayerGestureOverlayState();
}

class _PlayerGestureOverlayState extends State<_PlayerGestureOverlay> with TickerProviderStateMixin {
  // Software brightness (1.0 = normal, 0.2 = dimmed)
  double _softwareBrightness = 1.0;
  bool _showBrightnessIndicator = false;
  Timer? _brightnessTimer;

  // Volume slider
  double _volume = 100.0;
  bool _showVolumeIndicator = false;
  Timer? _volumeTimer;

  // Double tap seeking state
  bool _showLeftRipple = false;
  bool _showRightRipple = false;
  int _leftSeekAccumulated = 0;
  int _rightSeekAccumulated = 0;
  Timer? _leftRippleTimer;
  Timer? _rightRippleTimer;

  // Last tap detection
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;

  late AnimationController _leftRippleAnim;
  late AnimationController _rightRippleAnim;

  @override
  void initState() {
    super.initState();
    _volume = widget.player.state.volume;
    _leftRippleAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _rightRippleAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _brightnessTimer?.cancel();
    _volumeTimer?.cancel();
    _leftRippleTimer?.cancel();
    _rightRippleTimer?.cancel();
    _leftRippleAnim.dispose();
    _rightRippleAnim.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details, BoxConstraints constraints) {
    final now = DateTime.now();
    final pos = details.localPosition;
    final width = constraints.maxWidth;

    if (_lastTapTime != null && _lastTapPosition != null) {
      final timeDiff = now.difference(_lastTapTime!).inMilliseconds;
      final dist = (pos - _lastTapPosition!).distance;

      if (timeDiff < 320 && dist < 55) {
        // Double tap confirmed!
        _onDoubleTap(pos, width);
        _lastTapTime = null;
        _lastTapPosition = null;
        return;
      }
    }

    _lastTapTime = now;
    _lastTapPosition = pos;
    widget.resetControlsTimer();
  }

  void _onDoubleTap(Offset pos, double width) {
    widget.resetControlsTimer();
    final xRatio = pos.dx / width;

    if (xRatio < 0.40) {
      // Seek Left (-10s)
      _leftSeekAccumulated += 10;
      final currentPos = widget.player.state.position;
      final newPos = currentPos - const Duration(seconds: 10);
      widget.player.seek(newPos < Duration.zero ? Duration.zero : newPos);

      setState(() {
        _showLeftRipple = true;
      });
      _leftRippleAnim.forward(from: 0.0);

      _leftRippleTimer?.cancel();
      _leftRippleTimer = Timer(const Duration(milliseconds: 750), () {
        if (mounted) {
          setState(() {
            _showLeftRipple = false;
            _leftSeekAccumulated = 0;
          });
        }
      });
    } else if (xRatio > 0.60) {
      // Seek Right (+10s)
      _rightSeekAccumulated += 10;
      final currentPos = widget.player.state.position;
      final maxDur = widget.player.state.duration;
      final newPos = currentPos + const Duration(seconds: 10);
      widget.player.seek(newPos > maxDur ? maxDur : newPos);

      setState(() {
        _showRightRipple = true;
      });
      _rightRippleAnim.forward(from: 0.0);

      _rightRippleTimer?.cancel();
      _rightRippleTimer = Timer(const Duration(milliseconds: 750), () {
        if (mounted) {
          setState(() {
            _showRightRipple = false;
            _rightSeekAccumulated = 0;
          });
        }
      });
    } else {
      // Center Double Tap: Play / Pause toggle
      if (widget.player.state.playing) {
        widget.player.pause();
      } else {
        widget.player.play();
      }
    }
  }

  bool _isDraggingLeft = false;

  void _onVerticalDragStart(DragStartDetails details, BoxConstraints constraints) {
    widget.resetControlsTimer();
    final xRatio = details.localPosition.dx / constraints.maxWidth;
    _isDraggingLeft = xRatio < 0.5;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    widget.resetControlsTimer();
    final deltaY = -details.primaryDelta! / constraints.maxHeight;

    if (_isDraggingLeft) {
      // Brightness update
      setState(() {
        _softwareBrightness = (_softwareBrightness + deltaY * 1.5).clamp(0.15, 1.0);
        _showBrightnessIndicator = true;
      });
      _brightnessTimer?.cancel();
      _brightnessTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _showBrightnessIndicator = false);
      });
    } else {
      // Volume update
      setState(() {
        _volume = (_volume + deltaY * 150.0).clamp(0.0, 100.0);
        _showVolumeIndicator = true;
      });
      widget.player.setVolume(_volume);
      _volumeTimer?.cancel();
      _volumeTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _showVolumeIndicator = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Base controls widget underneath
            widget.controlsWidget,

            // Software Brightness Dimming Tint Layer
            if (_softwareBrightness < 1.0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withOpacity(1.0 - _softwareBrightness),
                  ),
                ),
              ),

            // Transparent Gesture Interceptor Area
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) => _handleTapDown(details, constraints),
                onVerticalDragStart: (details) => _onVerticalDragStart(details, constraints),
                onVerticalDragUpdate: (details) => _onVerticalDragUpdate(details, constraints),
                child: Container(color: Colors.transparent),
              ),
            ),

            // Left Ripple Bubble Animation (-10s, -20s...)
            if (_showLeftRipple)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: constraints.maxWidth * 0.42,
                child: IgnorePointer(
                  child: _DoubleTapRippleOverlay(
                    isLeft: true,
                    seconds: _leftSeekAccumulated,
                    animation: _leftRippleAnim,
                  ),
                ),
              ),

            // Right Ripple Bubble Animation (+10s, +20s...)
            if (_showRightRipple)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: constraints.maxWidth * 0.42,
                child: IgnorePointer(
                  child: _DoubleTapRippleOverlay(
                    isLeft: false,
                    seconds: _rightSeekAccumulated,
                    animation: _rightRippleAnim,
                  ),
                ),
              ),

            // Left Vertical Glassmorphic Brightness Indicator
            if (_showBrightnessIndicator)
              Positioned(
                left: 28.0,
                top: 80.0,
                bottom: 100.0,
                child: IgnorePointer(
                  child: _GlassmorphicSliderIndicator(
                    icon: Icons.brightness_6,
                    percentage: _softwareBrightness,
                    label: 'Brightness',
                  ),
                ),
              ),

            // Right Vertical Glassmorphic Volume Indicator
            if (_showVolumeIndicator)
              Positioned(
                right: 28.0,
                top: 80.0,
                bottom: 100.0,
                child: IgnorePointer(
                  child: _GlassmorphicSliderIndicator(
                    icon: _volume == 0 ? Icons.volume_off : Icons.volume_up,
                    percentage: _volume / 100.0,
                    label: 'Volume',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DoubleTapRippleOverlay extends StatelessWidget {
  final bool isLeft;
  final int seconds;
  final Animation<double> animation;

  const _DoubleTapRippleOverlay({
    required this.isLeft,
    required this.seconds,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final double value = animation.value;
        final double opacity = (1.0 - value).clamp(0.0, 1.0);
        final double scale = 0.85 + (value * 0.35);

        return ClipRRect(
          borderRadius: BorderRadius.horizontal(
            left: isLeft ? Radius.zero : const Radius.circular(280),
            right: isLeft ? const Radius.circular(280) : Radius.zero,
          ),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFF9F1C).withOpacity(0.18 * opacity),
                borderRadius: BorderRadius.horizontal(
                  left: isLeft ? Radius.zero : const Radius.circular(280),
                  right: isLeft ? const Radius.circular(280) : Radius.zero,
                ),
                border: Border.all(
                  color: const Color(0xFFFF9F1C).withOpacity(0.35 * opacity),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFFF9F1C), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF9F1C).withOpacity(0.5),
                                blurRadius: 18,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            isLeft ? Icons.fast_rewind : Icons.fast_forward,
                            color: Colors.white,
                            size: 32.0,
                          ),
                        ),
                        const SizedBox(height: 10.0),
                        Text(
                          isLeft ? '-${seconds}s' : '+${seconds}s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.0,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassmorphicSliderIndicator extends StatelessWidget {
  final IconData icon;
  final double percentage; // 0.0 to 1.0
  final String label;

  const _GlassmorphicSliderIndicator({
    required this.icon,
    required this.percentage,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final int pctInt = (percentage.clamp(0.0, 1.0) * 100).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24.0),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 48.0,
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          decoration: BoxDecoration(
            color: const Color(0xCC0F0F11),
            borderRadius: BorderRadius.circular(24.0),
            border: Border.all(color: Colors.white24, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFFFF9F1C), size: 20.0),
              const SizedBox(height: 12.0),
              Expanded(
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      width: 6.0,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(3.0),
                      ),
                    ),
                    FractionallySizedBox(
                      heightFactor: percentage.clamp(0.05, 1.0),
                      child: Container(
                        width: 6.0,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF9F1C), Color(0xFF2EC4B6)],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          borderRadius: BorderRadius.circular(3.0),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF9F1C).withOpacity(0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12.0),
              Text(
                '$pctInt%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

