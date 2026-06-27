import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/torrent_selector_panel.dart';
import '../services/download_service.dart';
import '../state/player_state.dart';
import '../services/stremio_addon_service.dart';
import '../services/extension_service.dart';

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
  final Map<int, dynamic>? tmdbEpisodesMap;

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
    this.tmdbEpisodesMap,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WindowListener {
  late final Player player = PlayerState().player!;
  late final VideoController controller = PlayerState().controller!;
  bool _isMaximized = false;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  DateTime? _lastClosedTime;
  DateTime? _lastOpenedTime;

  // Track settings open/close hover state
  Duration _controlsHoverDuration = const Duration(seconds: 3);
  final ValueNotifier<bool> _isQualityEnhancedNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximizedState();
  }

  @override
  void dispose() {
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);

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
    _isQualityEnhancedNotifier.value = !_isQualityEnhancedNotifier.value;
    try {
      final nativePlayer = player.platform as NativePlayer;
      if (_isQualityEnhancedNotifier.value) {
        // Add sharpening + debanding filters
        await nativePlayer.setProperty('deband', 'yes');
        await nativePlayer.setProperty('deband-iterations', '4');
        await nativePlayer.setProperty('deband-threshold', '48');
        await nativePlayer.setProperty('deband-range', '16');
        await nativePlayer.command(
          ['vf', 'add', '@enhance:lavfi=[unsharp=lx=5:ly=5:la=0.3:cx=5:cy=5:ca=0.3]'],
        );
      } else {
        await nativePlayer.setProperty('deband', 'no');
        await nativePlayer.command(['vf', 'remove', '@enhance']);
      }
    } catch (_) {}
  }

  void _openTorrentSelectorPanel({int? epNum}) {
    if (widget.anilistId == null) return;
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
                anilistId: widget.anilistId!,
                titles: widget.titles ?? [],
                episodeCount: widget.episodeCount ?? 0,
                episodeNumber: targetEpNum,
                isMovie: widget.isMovie ?? false,
                media: widget.media,
                episodes: widget.episodes,
                tmdbEpisodesMap: widget.tmdbEpisodesMap,
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

  int _extractEpNum(String title, int fallback) {
    final match = RegExp(r"(?:Episode|Ep\.?)\s*(\d+)", caseSensitive: false).firstMatch(title) ??
                  RegExp(r"^(\d+)\s*[-.]").firstMatch(title);
    return match != null ? int.parse(match.group(1)!) : fallback;
  }

  String _cleanEpTitle(String title) {
    final cleaned = title.replaceAll(RegExp(r"^Episode\s*\d+\s*[-–—:·]?\s*", caseSensitive: false), '').trim();
    return cleaned.isNotEmpty ? cleaned : title;
  }



  void _openEpisodesPanel() {
    _hideSettingsMenu();
    if (widget.episodes == null || widget.episodes!.isEmpty) return;
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
                      const Text(
                        "Episodes List",
                        style: TextStyle(
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
                      itemCount: widget.episodes!.length,
                      itemBuilder: (context, index) {
                        final ep = widget.episodes![index];
                        final String epTitle = ep['title'] ?? '';
                        final String thumbnail = ep['thumbnail'] ?? '';
                        final int epNum = ep['isPlaceholder'] == true ? (index + 1) : _extractEpNum(epTitle, index + 1);
                        final String cleanTitle = ep['isPlaceholder'] == true ? epTitle : _cleanEpTitle(epTitle);
                        
                        // Check TMDB overrides
                        final tmdbEp = widget.tmdbEpisodesMap?[epNum];
                        final String finalTitle = tmdbEp?['name'] ?? cleanTitle;
                        final String finalThumbnail = tmdbEp?['still_path'] ?? thumbnail;
                                            final isPlaying = (PlayerState().episodeNumber ?? widget.episodeNumber ?? 1) == epNum;
                        
                        return GestureDetector(
                          onTap: () {
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
                                if (widget.anilistId != null) {
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
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayerState(),
      builder: (context, _) {
        final playerState = PlayerState();
        final currentTitle = playerState.title ?? widget.title;

        // 1. Desktop custom controls theme configuration
    final desktopTheme = MaterialDesktopVideoControlsTheme(
      normal: MaterialDesktopVideoControlsThemeData(
        controlsHoverDuration: _controlsHoverDuration,
        seekBarBufferColor: Colors.white24,
        seekBarPositionColor: Colors.amber,
        seekBarColor: Colors.white12,
        seekBarThumbColor: Colors.amber,
        bottomButtonBar: [
          const MaterialDesktopPlayOrPauseButton(),
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
          ValueListenableBuilder<bool>(
            valueListenable: _isQualityEnhancedNotifier,
            builder: (context, isEnhanced, _) {
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
          // Change Stream Button
          if (widget.anilistId != null)
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
      fullscreen: MaterialDesktopVideoControlsThemeData(
        controlsHoverDuration: _controlsHoverDuration,
        seekBarBufferColor: Colors.white24,
        seekBarPositionColor: Colors.amber,
        seekBarColor: Colors.white12,
        seekBarThumbColor: Colors.amber,
        bottomButtonBar: [
          const MaterialDesktopPlayOrPauseButton(),
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
          ValueListenableBuilder<bool>(
            valueListenable: _isQualityEnhancedNotifier,
            builder: (context, isEnhanced, _) {
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
          // Change Stream Button
          if (widget.anilistId != null)
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
      child: Video(
        controller: controller,
        onEnterFullscreen: () async {
          PlayerState().enterFullscreen();
          await windowManager.setFullScreen(true);
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        },
        onExitFullscreen: () async {
          PlayerState().exitFullscreen();
          await windowManager.setFullScreen(false);
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          );
        },
        controls: (state) {
          final bool isDesktop = [
            TargetPlatform.windows,
            TargetPlatform.linux,
            TargetPlatform.macOS,
          ].contains(Theme.of(state.context).platform);
          return KeyedSubtree(
            key: ValueKey(_overlayEntry != null),
            child: isDesktop
                ? MaterialDesktopVideoControls(state)
                : MaterialVideoControls(state),
          );
        },
      ),
    );

    // 2. Mobile custom controls theme configuration (just in case)
    final mobileTheme = MaterialVideoControlsTheme(
      normal: MaterialVideoControlsThemeData(
        controlsHoverDuration: _controlsHoverDuration,
        seekBarBufferColor: Colors.white24,
        seekBarPositionColor: Colors.amber,
        seekBarColor: Colors.white12,
        seekBarThumbColor: Colors.amber,
        bottomButtonBar: [
          const MaterialPlayOrPauseButton(),
          const MaterialPositionIndicator(),
          const Spacer(),
          if (widget.episodes != null && widget.episodes!.isNotEmpty)
            MaterialCustomButton(
              onPressed: _openEpisodesPanel,
              icon: const Icon(
                Icons.keyboard_arrow_up,
                color: Colors.white,
              ),
            ),
          if (widget.episodes != null && widget.episodes!.isNotEmpty)
            const Spacer(),
          // Quality Enhancement Button
          ValueListenableBuilder<bool>(
            valueListenable: _isQualityEnhancedNotifier,
            builder: (context, isEnhanced, _) {
              return MaterialCustomButton(
                onPressed: _toggleQualityEnhancement,
                icon: Icon(
                  Icons.auto_awesome,
                  color: isEnhanced ? Colors.amber : Colors.white38,
                ),
              );
            },
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
          // Change Stream Button
          if (widget.anilistId != null)
            MaterialCustomButton(
              onPressed: () {
                _hideSettingsMenu();
                _openTorrentSelectorPanel();
              },
              icon: const Icon(Icons.swap_horizontal_circle, color: Colors.white),
            ),
          CompositedTransformTarget(
            link: _layerLink,
            child: MaterialCustomButton(
              onPressed: _toggleSettingsMenu,
              icon: const Icon(Icons.settings, color: Colors.white),
            ),
          ),
          const MaterialFullscreenButton(),
        ],
      ),
      fullscreen: MaterialVideoControlsThemeData(
        controlsHoverDuration: _controlsHoverDuration,
        seekBarBufferColor: Colors.white24,
        seekBarPositionColor: Colors.amber,
        seekBarColor: Colors.white12,
        seekBarThumbColor: Colors.amber,
        bottomButtonBar: [
          const MaterialPlayOrPauseButton(),
          const MaterialPositionIndicator(),
          const Spacer(),
          if (widget.episodes != null && widget.episodes!.isNotEmpty)
            MaterialCustomButton(
              onPressed: _openEpisodesPanel,
              icon: const Icon(
                Icons.keyboard_arrow_up,
                color: Colors.white,
              ),
            ),
          if (widget.episodes != null && widget.episodes!.isNotEmpty)
            const Spacer(),
          // Quality Enhancement Button
          ValueListenableBuilder<bool>(
            valueListenable: _isQualityEnhancedNotifier,
            builder: (context, isEnhanced, _) {
              return MaterialCustomButton(
                onPressed: _toggleQualityEnhancement,
                icon: Icon(
                  Icons.auto_awesome,
                  color: isEnhanced ? Colors.amber : Colors.white38,
                ),
              );
            },
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
          // Change Stream Button
          if (widget.anilistId != null)
            MaterialCustomButton(
              onPressed: () {
                _hideSettingsMenu();
                _openTorrentSelectorPanel();
              },
              icon: const Icon(Icons.swap_horizontal_circle, color: Colors.white),
            ),
          CompositedTransformTarget(
            link: _layerLink,
            child: MaterialCustomButton(
              onPressed: _toggleSettingsMenu,
              icon: const Icon(Icons.settings, color: Colors.white),
            ),
          ),
          const MaterialFullscreenButton(),
        ],
      ),
      child: desktopTheme,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        toolbarHeight: 36.0,
        titleSpacing: 0,
        actionsPadding: EdgeInsets.zero,
        title: GestureDetector(
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
            width: double.infinity,
            height: 36.0,
            alignment: Alignment.centerLeft,
            child: Text(
              currentTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
            ),
          ),
        ),
        leading: SizedBox(
          width: 40.0,
          height: 36.0,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16.0),
            onPressed: () async {
              final isFullScreen = await windowManager.isFullScreen();
              if (isFullScreen) {
                await windowManager.setFullScreen(false);
              }
              PlayerState().minimize();
            },
          ),
        ),
        actions: [
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
      body: mobileTheme,
    );
      },
    );
  }

  void _changeStremioEpisode(int epNum) {
    final List videos = widget.episodes ?? [];
    final epObj = videos.firstWhere(
      (v) => v['episode'] == epNum,
      orElse: () => null,
    );
    final String targetId = epObj?['id'] ?? '${PlayerState().movieId}:$epNum';
    
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
    final enabledStreamAddons = addonService.addons
        .where((a) => a.isEnabled && a.resources.contains('stream'))
        .toList();

    List<dynamic> allStreams = [];
    final String type = PlayerState().isMovie == true ? 'movie' : 'series';

    for (final addon in enabledStreamAddons) {
      if (addon.types.contains(type)) {
        try {
          final streamUrl = '${addon.url.replaceAll('/manifest.json', '')}/stream/$type/$targetId.json';
          final response = await http.get(Uri.parse(streamUrl)).timeout(const Duration(seconds: 8));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final List streams = data['streams'] ?? [];
            for (final s in streams) {
              allStreams.add({
                ...s,
                'addonName': addon.name,
              });
            }
          }
        } catch (e) {
          debugPrint('Error loading stream from ${addon.name}: $e');
        }
      }
    }

    if (mounted) {
      Navigator.pop(context); // close progress dialog
    }

    if (allStreams.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No streams found for this episode.')),
        );
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

  void _playStremioStream(dynamic stream, int epNum) {
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
      PlayerState().updateActiveEpisode(
        streamUrl: streamUrl,
        title: '$mediaTitle - Episode $epNum',
        episodeNumber: epNum,
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
    final match = RegExp(r'(?:👤|seeders:?\s*)(\d+)\b', caseSensitive: false).firstMatch(title);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  int _parseImdbIdToInt(String imdbId) {
    final digits = imdbId.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digits) ?? 0;
  }
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
    switch (_pageIndex) {
      case 1:
        return _buildSpeedMenu();
      case 2:
        return _buildAudioMenu();
      case 3:
        return _buildSubtitlesMenu();
      default:
        return _buildMainMenu();
    }
  }

  Widget _buildMainMenu() {
    final rate = widget.player.state.rate;
    final currentAudio = widget.player.state.track.audio;
    final currentSubtitle = widget.player.state.track.subtitle;

    final audioLabel = _getAudioTrackLabel(currentAudio);
    final subtitleLabel = _getSubtitleTrackLabel(currentSubtitle);

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
        ListTile(
          dense: true,
          leading: const Icon(Icons.auto_awesome, color: Colors.amber, size: 18),
          title: const Text("Quality Enhancement", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
          trailing: SizedBox(
            height: 24,
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.isQualityEnhancedNotifier,
              builder: (context, isEnhanced, _) {
                return Switch(
                  value: isEnhanced,
                  activeColor: Colors.amber,
                  onChanged: (val) {
                    widget.onToggleQualityEnhanced();
                  },
                );
              },
            ),
          ),
        ),
        if (widget.anilistId != null) ...[
          const Divider(color: Colors.white10, height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.swap_horizontal_circle, color: Colors.white70, size: 18),
            title: const Text("Change Stream", style: TextStyle(color: Colors.white, fontSize: 13.0, fontFamily: 'Outfit')),
            trailing: const Icon(Icons.chevron_right, color: Colors.white30, size: 16),
            onTap: widget.onOpenTorrentPanel,
          ),
        ],
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250.0),
            child: ListView.builder(
              shrinkWrap: true,
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
        const Divider(color: Colors.white10, height: 1),

        if (subtitleTracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Text("No subtitle tracks found", style: TextStyle(color: Colors.white38, fontSize: 12.0)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250.0),
            child: ListView.builder(
              shrinkWrap: true,
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
          ),
      ],
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

  const _PlayerEpisodeCard({
    required this.epNum,
    required this.title,
    required this.thumbnail,
    required this.isPlaying,
  });

  @override
  State<_PlayerEpisodeCard> createState() => _PlayerEpisodeCardState();
}

class _PlayerEpisodeCardState extends State<_PlayerEpisodeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(
                  color: widget.isPlaying 
                      ? Colors.amber.withValues(alpha: 0.6) 
                      : (_isHovered ? Colors.white30 : Colors.white10),
                  width: widget.isPlaying ? 2.0 : 1.0,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5.0),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: widget.thumbnail.isNotEmpty
                          ? Image.network(
                              widget.thumbnail,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildPlaceholder(),
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
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[950],
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
