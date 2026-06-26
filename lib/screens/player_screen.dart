import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WindowListener {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  bool _isMaximized = false;

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
    windowManager.removeListener(this);
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

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final rate = player.state.rate;
            final audioTracks = player.state.tracks.audio;
            final currentAudio = player.state.track.audio;
            final subtitleTracks = player.state.tracks.subtitle;
            final currentSubtitle = player.state.track.subtitle;

            return AlertDialog(
              backgroundColor: const Color(0xFF0F0F11),
              title: const Text(
                "Playback Settings",
                style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 16.0),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Playback Speed
                    const Text("Playback Speed", style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [0.5, 1.0, 1.25, 1.5, 2.0].map((r) {
                        final isSelected = rate == r;
                        return ChoiceChip(
                          label: Text("${r}x"),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) {
                              player.setRate(r);
                              setDialogState(() {});
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const Divider(color: Colors.white10, height: 24),

                    // Audio Tracks
                    const Text("Audio Track", style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                    const SizedBox(height: 8),
                    if (audioTracks.isEmpty)
                      const Text("No audio tracks found", style: TextStyle(color: Colors.white38, fontSize: 12.0))
                    else
                      DropdownButton<AudioTrack>(
                        value: currentAudio,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF0F0F11),
                        style: const TextStyle(color: Colors.white, fontSize: 13.0),
                        items: audioTracks.map((track) {
                          final label = [
                            track.title,
                            track.language,
                            "ID: ${track.id}"
                          ].where((s) => s != null && s.isNotEmpty).join(" - ");
                          return DropdownMenuItem(
                            value: track,
                            child: Text(label, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (track) {
                          if (track != null) {
                            player.setAudioTrack(track);
                            setDialogState(() {});
                          }
                        },
                      ),
                    const Divider(color: Colors.white10, height: 24),

                    // Subtitle Tracks
                    const Text("Subtitle Track", style: TextStyle(color: Colors.white70, fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                    const SizedBox(height: 8),
                    if (subtitleTracks.isEmpty)
                      const Text("No subtitle tracks found", style: TextStyle(color: Colors.white38, fontSize: 12.0))
                    else
                      DropdownButton<SubtitleTrack>(
                        value: currentSubtitle,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF0F0F11),
                        style: const TextStyle(color: Colors.white, fontSize: 13.0),
                        items: subtitleTracks.map((track) {
                          final label = [
                            track.title,
                            track.language,
                            "ID: ${track.id}"
                          ].where((s) => s != null && s.isNotEmpty).join(" - ");
                          return DropdownMenuItem(
                            value: track,
                            child: Text(label, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (track) {
                          if (track != null) {
                            player.setSubtitleTrack(track);
                            setDialogState(() {});
                          }
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Done", style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
                ),
              ],
            );
          },
        );
      },
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
          // Settings Button
          MaterialDesktopCustomButton(
            onPressed: _showSettingsDialog,
            icon: const Icon(Icons.settings, color: Colors.white),
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
          // Settings Button
          MaterialDesktopCustomButton(
            onPressed: _showSettingsDialog,
            icon: const Icon(Icons.settings, color: Colors.white),
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
          MaterialCustomButton(
            onPressed: _showSettingsDialog,
            icon: const Icon(Icons.settings, color: Colors.white),
          ),
          const MaterialFullscreenButton(),
        ],
      ),
      fullscreen: MaterialVideoControlsThemeData(
        bottomButtonBar: [
          const MaterialPlayOrPauseButton(),
          const MaterialPositionIndicator(),
          const Spacer(),
          MaterialCustomButton(
            onPressed: _showSettingsDialog,
            icon: const Icon(Icons.settings, color: Colors.white),
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
              widget.title,
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
      body: Center(
        child: mobileTheme,
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
