import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../widgets/torrent_selector_panel.dart';

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
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  bool _isMaximized = false;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  // Dynamically tracked state
  late int _currentEpisodeNumber = widget.episodeNumber ?? 1;
  late String _currentTitle = widget.title;
  bool _isEpisodesExpanded = false;
  final ScrollController _scrollController = ScrollController();
  bool _isQualityEnhanced = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximizedState();
    
    // Play the provided URL
    player.open(Media(widget.streamUrl));
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    windowManager.removeListener(this);
    _scrollController.dispose();
    player.dispose();
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
    if (_overlayEntry != null) {
      _hideSettingsMenu();
    } else {
      _showSettingsMenu();
    }
  }

  void _hideSettingsMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showSettingsMenu() {
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Tap outside to close
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideSettingsMenu,
              child: Container(
                color: Colors.transparent,
              ),
            ),
            Positioned(
              width: 280.0,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topRight,
                followerAnchor: Alignment.bottomRight,
                offset: const Offset(0.0, -12.0),
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
                    isQualityEnhanced: _isQualityEnhanced,
                    onToggleQualityEnhanced: _toggleQualityEnhancement,
                    anilistId: widget.anilistId,
                    titles: widget.titles,
                    episodeCount: widget.episodeCount,
                    episodeNumber: _currentEpisodeNumber,
                    isMovie: widget.isMovie,
                    media: widget.media,
                    onOpenTorrentPanel: () {
                      _hideSettingsMenu();
                      _openTorrentSelectorPanel();
                    },
                  ),
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
    setState(() {
      _isQualityEnhanced = !_isQualityEnhanced;
    });
    try {
      await (player.platform as dynamic).setProperty('deband', _isQualityEnhanced ? 'yes' : 'no');
    } catch (_) {}
  }

  void _openTorrentSelectorPanel({int? epNum}) {
    if (widget.anilistId == null) return;
    final targetEpNum = epNum ?? _currentEpisodeNumber;
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
            margin: isMobileSheet ? EdgeInsets.zero : const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C0E),
              borderRadius: isMobileSheet
                  ? const BorderRadius.vertical(top: Radius.circular(16.0))
                  : BorderRadius.circular(12.0),
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
              borderRadius: isMobileSheet
                  ? const BorderRadius.vertical(top: Radius.circular(15.0))
                  : BorderRadius.circular(11.0),
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
                  player.open(Media(streamUrl));
                  setState(() {
                    _currentTitle = title;
                    _currentEpisodeNumber = targetEpNum;
                  });
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

  Widget _buildUnderPlayerEpisodeList() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 650;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isMobile ? 2 : 4,
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
            
            final isPlaying = _currentEpisodeNumber == epNum;
            
            return GestureDetector(
              onTap: () {
                if (!isPlaying) {
                  _openTorrentSelectorPanel(epNum: epNum);
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Desktop custom controls theme configuration
    final desktopTheme = MaterialDesktopVideoControlsTheme(
      normal: MaterialDesktopVideoControlsThemeData(
        bottomButtonBar: [
          const MaterialDesktopPlayOrPauseButton(),
          const MaterialDesktopVolumeButton(),
          const MaterialPositionIndicator(),
          const Spacer(),
          // Quality Enhancement Button
          MaterialDesktopCustomButton(
            onPressed: _toggleQualityEnhancement,
            icon: Icon(
              Icons.auto_awesome,
              color: _isQualityEnhanced ? Colors.amber : Colors.white38,
            ),
          ),
          // Subtitles On/Off Button (CC)
          MaterialDesktopCustomButton(
            onPressed: () {
              final isOff = player.state.track.subtitle.id == 'no';
              if (isOff) {
                final firstTrack = player.state.tracks.subtitle.firstWhere(
                  (t) => t.id != 'no',
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
        bottomButtonBar: [
          const MaterialDesktopPlayOrPauseButton(),
          const MaterialDesktopVolumeButton(),
          const MaterialPositionIndicator(),
          const Spacer(),
          // Quality Enhancement Button
          MaterialDesktopCustomButton(
            onPressed: _toggleQualityEnhancement,
            icon: Icon(
              Icons.auto_awesome,
              color: _isQualityEnhanced ? Colors.amber : Colors.white38,
            ),
          ),
          // Subtitles On/Off Button (CC)
          MaterialDesktopCustomButton(
            onPressed: () {
              final isOff = player.state.track.subtitle.id == 'no';
              if (isOff) {
                final firstTrack = player.state.tracks.subtitle.firstWhere(
                  (t) => t.id != 'no',
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
      ),
    );

    // 2. Mobile custom controls theme configuration (just in case)
    final mobileTheme = MaterialVideoControlsTheme(
      normal: MaterialVideoControlsThemeData(
        bottomButtonBar: [
          const MaterialPlayOrPauseButton(),
          const MaterialPositionIndicator(),
          const Spacer(),
          // Quality Enhancement Button
          MaterialCustomButton(
            onPressed: _toggleQualityEnhancement,
            icon: Icon(
              Icons.auto_awesome,
              color: _isQualityEnhanced ? Colors.amber : Colors.white38,
            ),
          ),
          // Subtitles On/Off Button (CC)
          MaterialCustomButton(
            onPressed: () {
              final isOff = player.state.track.subtitle.id == 'no';
              if (isOff) {
                final firstTrack = player.state.tracks.subtitle.firstWhere(
                  (t) => t.id != 'no',
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
        bottomButtonBar: [
          const MaterialPlayOrPauseButton(),
          const MaterialPositionIndicator(),
          const Spacer(),
          // Quality Enhancement Button
          MaterialCustomButton(
            onPressed: _toggleQualityEnhancement,
            icon: Icon(
              Icons.auto_awesome,
              color: _isQualityEnhanced ? Colors.amber : Colors.white38,
            ),
          ),
          // Subtitles On/Off Button (CC)
          MaterialCustomButton(
            onPressed: () {
              final isOff = player.state.track.subtitle.id == 'no';
              if (isOff) {
                final firstTrack = player.state.tracks.subtitle.firstWhere(
                  (t) => t.id != 'no',
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
        titleSpacing: 0,
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
            height: 56.0, // standard AppBar height
            alignment: Alignment.centerLeft,
            child: Text(
              _currentTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15.0, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18.0),
          onPressed: () => Navigator.of(context).pop(),
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
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: mobileTheme,
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isEpisodesExpanded = !_isEpisodesExpanded;
                });
                if (_isEpisodesExpanded) {
                  _scrollController.animateTo(
                    260.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else {
                  _scrollController.animateTo(
                    0.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F0F11),
                  border: Border(
                    bottom: BorderSide(color: Colors.white10, width: 1.0),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isEpisodesExpanded ? "HIDE EPISODE LIST" : "SHOW EPISODE LIST",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.0,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _isEpisodesExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: Colors.white70,
                      size: 16.0,
                    ),
                  ],
                ),
              ),
            ),
            if (_isEpisodesExpanded && widget.episodes != null && widget.episodes!.isNotEmpty)
              Container(
                color: Colors.black,
                padding: const EdgeInsets.all(16.0),
                child: _buildUnderPlayerEpisodeList(),
              )
            else if (_isEpisodesExpanded)
              Container(
                height: 150,
                alignment: Alignment.center,
                child: const Text(
                  "No episode list available for this media.",
                  style: TextStyle(color: Colors.white38, fontSize: 13.0, fontFamily: 'Outfit'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsOverlayCard extends StatefulWidget {
  final Player player;
  final VoidCallback onClose;
  final bool isQualityEnhanced;
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
    required this.isQualityEnhanced,
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
    if (track.id == 'auto') return 'Auto';
    if (track.id == 'no') return 'Off';
    final parts = [
      track.title,
      track.language,
    ].where((s) => s != null && s.isNotEmpty).toList();
    if (parts.isEmpty) return 'Track ${track.id}';
    return parts.join(' - ');
  }

  String _getSubtitleTrackLabel(SubtitleTrack track) {
    if (track.id == 'auto') return 'Auto';
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
            child: Switch(
              value: widget.isQualityEnhanced,
              activeColor: Colors.amber,
              onChanged: (val) {
                widget.onToggleQualityEnhanced();
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
                  widget.onClose();
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
    final audioTracks = widget.player.state.tracks.audio.where((t) => t.id != 'no').toList();

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
                    widget.onClose();
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
    final subtitleTracks = widget.player.state.tracks.subtitle.where((t) => t.id != 'no').toList();

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
                        (t) => t.id != 'no',
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
                    widget.onClose();
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
          width: 46.0,
          height: 32.0,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _isHovering ? widget.hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(4.0),
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
