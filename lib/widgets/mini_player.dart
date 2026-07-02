import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../state/player_state.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final playerState = PlayerState();
    if (!playerState.isActive || playerState.player == null || playerState.controller == null) {
      return const SizedBox.shrink();
    }

    final player = playerState.player!;
    final controller = playerState.controller!;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          playerState.maximize();
        },
        child: Container(
          width: 280.0,
          height: 158.0, // 16:9 aspect ratio for 280 width
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F11),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.0),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 15.0,
                spreadRadius: 2.0,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11.0),
            child: Stack(
              children: [
                // Video Texture
                Positioned.fill(
                  child: IgnorePointer(
                    child: Video(
                      controller: controller,
                      controls: (state) => const SizedBox.shrink(),
                    ),
                  ),
                ),

                // Hover / Mobile always-on Overlay Controls
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: (MediaQuery.of(context).size.width < 650 || _isHovered) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      color: Colors.black45,
                      child: Stack(
                        children: [
                          // Title (Top Left)
                          Positioned(
                            top: 8.0,
                            left: 8.0,
                            right: 36.0,
                            child: Text(
                              playerState.title ?? 'Playing',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.0,
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black87,
                                    offset: Offset(1, 1),
                                    blurRadius: 2.0,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Close Button (Top Right)
                          Positioned(
                            top: 4.0,
                            right: 4.0,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {}, // Prevent click propagation to parent GestureDetector
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 16.0),
                                padding: const EdgeInsets.all(4.0),
                                constraints: const BoxConstraints(),
                                tooltip: 'Close player',
                                onPressed: () {
                                  playerState.stopPlayback();
                                },
                              ),
                            ),
                          ),

                          // Center Play/Pause Button
                          Center(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {}, // Prevent click propagation to parent GestureDetector
                              child: StreamBuilder<bool>(
                                stream: player.stream.playing,
                                builder: (context, snapshot) {
                                  final isPlaying = snapshot.data ?? player.state.playing;
                                  return IconButton(
                                    icon: Icon(
                                      isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                      color: Colors.white,
                                      size: 40.0,
                                    ),
                                    onPressed: () {
                                      player.playOrPause();
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Thin Progress Bar (Bottom)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: StreamBuilder<Duration>(
                    stream: player.stream.position,
                    builder: (context, posSnapshot) {
                      final position = posSnapshot.data ?? player.state.position;
                      return StreamBuilder<Duration>(
                        stream: player.stream.duration,
                        builder: (context, durSnapshot) {
                          final duration = durSnapshot.data ?? player.state.duration;
                          final double progress = duration.inMilliseconds > 0
                              ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                              : 0.0;
                          return LinearProgressIndicator(
                            value: progress,
                            minHeight: 3.0,
                            backgroundColor: Colors.white24,
                            color: Colors.amber,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
