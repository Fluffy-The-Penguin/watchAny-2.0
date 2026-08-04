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
      startXRatio: 0.70 + (Random().nextDouble() * 0.22),
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
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final bool isMobile = screenWidth < 650;
    // On mobile (portrait or landscape), the native controls header is ~48–56px tall.
    // We need to sit just below it. Use the shorter dimension as a landscape check.
    final bool isLandscape = screenWidth > screenHeight;
    // Header offset: account for status bar + controls bar height
    final double statusBarH = MediaQuery.of(context).padding.top;
    // Native player top bar is ~50px; push WT header below it
    final double headerTop = isMobile
        ? (isLandscape ? (statusBarH + 50) : (statusBarH + 52))
        : 64.0;

    return ListenableBuilder(
      listenable: WatchTogetherService(),
      builder: (context, _) {
        final service = WatchTogetherService();
        if (!service.isActive) return const SizedBox.shrink();

        return Stack(
          children: [
            // 1. Top Header Row — positioned below native player controls header
            Positioned(
              top: headerTop,
              left: isMobile ? 12 : 24,
              right: isMobile ? 12 : 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left Badge: Room Status
                  Flexible(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 8.0 : 12.0, vertical: 5.0),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(20.0),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.groups_rounded,
                              color: Colors.deepPurpleAccent, size: 15),
                          const SizedBox(width: 5),
                          Text(
                            isMobile ? '${service.participants.length}' : '${service.participants.length} Watching',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          Container(width: 1, height: 11, color: Colors.white24),
                          const SizedBox(width: 6),
                          Text(
                            service.roomCode,
                            style: TextStyle(
                                color: Colors.amberAccent,
                                fontSize: isMobile ? 11.5 : 12.5,
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
                                  content: Text('Room code copied!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(2.0),
                              child: Icon(Icons.copy_rounded,
                                  color: Colors.white70, size: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Right Side Controls: Chat Toggle & Leave
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Chat Toggle Button with Unread Badge
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          InkWell(
                            onTap: () {
                              service.setChatDrawerOpen(!service.isChatDrawerOpen);
                              if (service.isChatDrawerOpen) {
                                _scrollToBottom();
                              }
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 10.0 : 12.0, vertical: 5.0),
                              decoration: BoxDecoration(
                                color: service.isChatDrawerOpen
                                    ? Colors.deepPurpleAccent
                                    : Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(20.0),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    service.isChatDrawerOpen
                                        ? Icons.chat_bubble
                                        : Icons.chat_bubble_outline,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  if (!isMobile) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      service.isChatDrawerOpen ? 'Close Chat' : 'Chat',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.0,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (service.unreadChatCount > 0 && !service.isChatDrawerOpen)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${service.unreadChatCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(width: 6),

                      // Leave Room Button
                      InkWell(
                        onTap: () => service.leaveRoom(),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                          ),
                          child: const Icon(Icons.logout_rounded,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 2. Sync Notice Banner — below the header
            if (service.syncNotice != null)
              Positioned(
                top: headerTop + 42,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14.0, vertical: 6.0),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20.0),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            color: Colors.amber,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          service.syncNotice!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 3. Floating Emoji Particles
            ..._floatingParticles.map((p) => Positioned(
                  key: ValueKey(p.id),
                  bottom: 120,
                  left: screenWidth * p.startXRatio,
                  child: _AnimatedEmojiBubble(emoji: p.emoji),
                )),

            // 4. Toast Popups when Chat Drawer is Closed
            if (!service.isChatDrawerOpen && _toastMessages.isNotEmpty)
              Positioned(
                bottom: 130,
                left: isMobile ? 12 : 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _toastMessages.take(2).map((chat) {
                    return Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${chat.senderName}: ',
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            TextSpan(
                              text: chat.text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // 5. Slide-Out / Responsive Live Chat Panel
            if (service.isChatDrawerOpen)
              Positioned(
                // On mobile start from below native header; fullscreen starts from top
                top: isMobile ? headerTop : 0,
                bottom: isMobile ? 72 : 0,
                right: 0,
                width: isMobile ? min(screenWidth * 0.85, 300.0) : 310.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141417).withValues(alpha: 0.96),
                    borderRadius: isMobile
                        ? const BorderRadius.horizontal(left: Radius.circular(16))
                        : BorderRadius.zero,
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      // Panel Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: Colors.white10)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.chat_rounded,
                                color: Colors.deepPurpleAccent, size: 16),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Live Chat',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white54, size: 18),
                              onPressed: () => service.setChatDrawerOpen(false),
                            ),
                          ],
                        ),
                      ),

                      // Chat Messages View
                      Expanded(
                        child: ListView.builder(
                          controller: _chatScrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: service.chatMessages.length,
                          itemBuilder: (context, index) {
                            final chat = service.chatMessages[index];
                            if (chat.isSystemMessage) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Center(
                                  child: Text(
                                    chat.text,
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.w500,
                                    ),
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
                                constraints:
                                    const BoxConstraints(maxWidth: 220),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.deepPurpleAccent
                                          .withValues(alpha: 0.85)
                                      : Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
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
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    Text(
                                      chat.text,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12.5),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Emoji Quick Bar inside Chat Panel
                      Container(
                        height: 36,
                        color: Colors.black.withValues(alpha: 0.3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children:
                              ['❤️', '😂', '😱', '🔥', '👏', '🍿'].map((emoji) {
                            return InkWell(
                              onTap: () => service.sendEmojiReaction(emoji),
                              child: Text(emoji,
                                  style: const TextStyle(fontSize: 18)),
                            );
                          }).toList(),
                        ),
                      ),

                      // Input Bar
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: Colors.white10)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _chatInputController,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                                textInputAction: TextInputAction.send,
                                onSubmitted: (text) {
                                  if (text.trim().isNotEmpty) {
                                    service.sendChatMessage(text);
                                    _chatInputController.clear();
                                    _scrollToBottom();
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'Type message...',
                                  hintStyle: const TextStyle(
                                      color: Colors.white30, fontSize: 12),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.send_rounded,
                                  color: Colors.deepPurpleAccent, size: 18),
                              onPressed: () {
                                final text = _chatInputController.text.trim();
                                if (text.isNotEmpty) {
                                  service.sendChatMessage(text);
                                  _chatInputController.clear();
                                  _scrollToBottom();
                                }
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
  late Animation<double> _yAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    );

    _yAnimation = Tween<double>(begin: 0, end: -180).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1), weight: 15),
      TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1), weight: 60),
      TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0), weight: 25),
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
          offset: Offset(0, _yAnimation.value),
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Text(
              widget.emoji,
              style: const TextStyle(fontSize: 28),
            ),
          ),
        );
      },
    );
  }
}
