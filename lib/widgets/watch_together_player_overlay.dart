import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/watch_together_service.dart';

class WatchTogetherPlayerOverlay extends StatefulWidget {
  const WatchTogetherPlayerOverlay({super.key});

  @override
  State<WatchTogetherPlayerOverlay> createState() =>
      _WatchTogetherPlayerOverlayState();
}

class _WatchTogetherPlayerOverlayState
    extends State<WatchTogetherPlayerOverlay> {
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<_FloatingEmojiParticle> _floatingParticles = [];
  final List<WatchChatMessage> _toastMessages = [];
  StreamSubscription<WatchEmojiReaction>? _reactionSub;
  StreamSubscription<WatchChatMessage>? _toastSub;

  @override
  void initState() {
    super.initState();
    final service = WatchTogetherService();

    // Listen to reactions
    _reactionSub = service.reactionStream.listen((reaction) {
      _spawnEmojiParticle(reaction.emoji);
    });

    // Listen to toast popups
    _toastSub = service.toastChatStream.listen((chat) {
      if (!mounted) return;
      setState(() {
        _toastMessages.add(chat);
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _toastMessages.remove(chat);
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _chatInputController.dispose();
    _chatScrollController.dispose();
    _reactionSub?.cancel();
    _toastSub?.cancel();
    super.dispose();
  }

  void _spawnEmojiParticle(String emoji) {
    if (!mounted) return;
    final particle = _FloatingEmojiParticle(
      id: Random().nextDouble(),
      emoji: emoji,
      startXRatio: 0.75 + (Random().nextDouble() * 0.18),
    );
    setState(() {
      _floatingParticles.add(particle);
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _floatingParticles.removeWhere((p) => p.id == particle.id);
        });
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WatchTogetherService(),
      builder: (context, _) {
        final service = WatchTogetherService();
        if (!service.isActive) return const SizedBox.shrink();

        return Stack(
          children: [
            // 1. Sync Notice Banner (Top Center)
            if (service.syncNotice != null)
              Positioned(
                top: 70,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20.0),
                      border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: Colors.amber,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          service.syncNotice!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 2. Top-Left Room Status Badge & Control Buttons
            Positioned(
              top: 16,
              left: 60,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 6.0),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20.0),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.groups_rounded,
                            color: Colors.deepPurpleAccent, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${service.participants.length} Watching',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.0,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 1,
                          height: 12,
                          color: Colors.white24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Code: ${service.roomCode}',
                          style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 12.0,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: service.roomCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Room code copied to clipboard!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(2.0),
                            child: Icon(Icons.copy_rounded,
                                color: Colors.white70, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Leave Room Icon
                  IconButton(
                    icon: const Icon(Icons.logout_rounded,
                        color: Colors.redAccent, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      shape: const CircleBorder(),
                    ),
                    tooltip: 'Leave Watch Together',
                    onPressed: () => service.leaveRoom(),
                  ),
                ],
              ),
            ),

            // 3. Top-Right Chat Drawer Toggle Button
            Positioned(
              top: 16,
              right: 60,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      service.setChatDrawerOpen(!service.isChatDrawerOpen);
                      if (service.isChatDrawerOpen) {
                        _scrollToBottom();
                      }
                    },
                    icon: Icon(
                      service.isChatDrawerOpen
                          ? Icons.chat_bubble
                          : Icons.chat_bubble_outline,
                      color: Colors.white,
                      size: 16,
                    ),
                    label: Text(
                      service.isChatDrawerOpen ? 'Close Chat' : 'Chat',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.0,
                          fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.65),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.0),
                        side: const BorderSide(color: Colors.white24),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14.0, vertical: 8.0),
                    ),
                  ),
                  if (service.unreadChatCount > 0 && !service.isChatDrawerOpen)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${service.unreadChatCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 4. Floating Emoji Reactions Particles
            ..._floatingParticles.map((p) => Positioned(
                  key: ValueKey(p.id),
                  bottom: 120,
                  left: MediaQuery.of(context).size.width * p.startXRatio,
                  child: _AnimatedEmojiBubble(emoji: p.emoji),
                )),

            // 5. Toast Popups when Chat Drawer is Closed
            if (!service.isChatDrawerOpen && _toastMessages.isNotEmpty)
              Positioned(
                bottom: 110,
                left: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _toastMessages.take(3).map((chat) {
                    return Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${chat.senderName}: ',
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            TextSpan(
                              text: chat.text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // 6. Quick Emoji Reactions Bar (Bottom Center Above Controls)
            Positioned(
              bottom: 90,
              right: service.isChatDrawerOpen ? 340 : 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: ['❤️', '😂', '😱', '🔥', '👏', '🍿'].map((emoji) {
                    return InkWell(
                      onTap: () => service.sendEmojiReaction(emoji),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6.0, vertical: 4.0),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // 7. Slide-Out Chat Drawer Panel (Right Side)
            if (service.isChatDrawerOpen)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 320,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141417).withValues(alpha: 0.95),
                    border: const Border(
                        left: BorderSide(color: Colors.white12)),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: Colors.white10)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.chat_rounded,
                                color: Colors.deepPurpleAccent, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Live Room Chat',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white54, size: 18),
                              onPressed: () =>
                                  service.setChatDrawerOpen(false),
                            ),
                          ],
                        ),
                      ),

                      // Messages List
                      Expanded(
                        child: ListView.builder(
                          controller: _chatScrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: service.chatMessages.length,
                          itemBuilder: (context, index) {
                            final chat = service.chatMessages[index];
                            if (chat.isSystemMessage) {
                              return Container(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.amber.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color:
                                          Colors.amber.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  chat.text,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }

                            final isMe = chat.senderId == service.myId;
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 240),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.deepPurpleAccent
                                          .withValues(alpha: 0.8)
                                      : Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: isMe
                                          ? Colors.deepPurpleAccent
                                          : Colors.white10),
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (!isMe)
                                      Text(
                                        chat.senderName,
                                        style: const TextStyle(
                                          color: Colors.amber,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    Text(
                                      chat.text,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Input Bar
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          border:
                              Border(top: BorderSide(color: Colors.white10)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _chatInputController,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle:
                                      const TextStyle(color: Colors.white30),
                                  filled: true,
                                  fillColor:
                                      Colors.white.withValues(alpha: 0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide:
                                        const BorderSide(color: Colors.white12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                ),
                                onSubmitted: (val) {
                                  service.sendChatMessage(val);
                                  _chatInputController.clear();
                                  _scrollToBottom();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.send_rounded,
                                  color: Colors.deepPurpleAccent, size: 20),
                              onPressed: () {
                                service.sendChatMessage(
                                    _chatInputController.text);
                                _chatInputController.clear();
                                _scrollToBottom();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FloatingEmojiParticle {
  final double id;
  final String emoji;
  final double startXRatio;

  _FloatingEmojiParticle({
    required this.id,
    required this.emoji,
    required this.startXRatio,
  });
}

class _AnimatedEmojiBubble extends StatefulWidget {
  final String emoji;
  const _AnimatedEmojiBubble({required this.emoji});

  @override
  State<_AnimatedEmojiBubble> createState() => _AnimatedEmojiBubbleState();
}

class _AnimatedEmojiBubbleState extends State<_AnimatedEmojiBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnim;
  late Animation<double> _translateYAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _opacityAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);

    _translateYAnim = Tween<double>(begin: 0.0, end: -180.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.3), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 30),
    ]).animate(_controller);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _translateYAnim.value),
          child: Transform.scale(
            scale: _scaleAnim.value,
            child: Opacity(
              opacity: _opacityAnim.value,
              child: Text(
                widget.emoji,
                style: const TextStyle(fontSize: 32),
              ),
            ),
          ),
        );
      },
    );
  }
}
