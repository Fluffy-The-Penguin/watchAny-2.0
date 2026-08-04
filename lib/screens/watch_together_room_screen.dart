import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/watch_together_service.dart';

class WatchTogetherRoomScreen extends StatefulWidget {
  const WatchTogetherRoomScreen({super.key});

  @override
  State<WatchTogetherRoomScreen> createState() =>
      _WatchTogetherRoomScreenState();
}

class _WatchTogetherRoomScreenState extends State<WatchTogetherRoomScreen>
    with TickerProviderStateMixin {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _autoJoin = true;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    final service = WatchTogetherService();
    service.setMediaReceivedCallback((media) {
      if (_autoJoin && media.videoUrl != null && media.videoUrl!.isNotEmpty) {
        if (mounted) WatchTogetherService.playDirect(media);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    WatchTogetherService().clearMediaReceivedCallback();
    super.dispose();
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

  void _copyRoomCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Room code $code copied!'),
          ],
        ),
        backgroundColor: Colors.deepPurpleAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showLeaveDialog(WatchTogetherService service) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C22),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave Room?',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit')),
        content: const Text(
          'Are you sure you want to leave this Watch Together session?',
          style: TextStyle(color: Colors.white60, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              service.leaveRoom();
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Leave',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WatchTogetherService(),
      builder: (context, _) {
        final service = WatchTogetherService();

        // If not active, pop back
        if (!service.isActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const SizedBox.shrink();
        }

        final bool isWide = MediaQuery.of(context).size.width >= 700;
        final media = service.mediaPayload;
        final bool isDefaultSession = media == null ||
            media.videoUrl == null ||
            media.movieId.startsWith('room_');

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          appBar: _buildAppBar(service),
          body: isWide
              ? _buildWideLayout(service, media, isDefaultSession)
              : _buildNarrowLayout(service, media, isDefaultSession),
        );
      },
    );
  }

  AppBar _buildAppBar(WatchTogetherService service) {
    return AppBar(
      backgroundColor: const Color(0xFF111118),
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        tooltip: 'Back (room stays active)',
        onPressed: () {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        },
      ),
      title: Row(
        children: [
          // Live indicator
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (ctx, _) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.greenAccent
                    .withValues(alpha: _pulseAnimation.value),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.greenAccent
                        .withValues(alpha: _pulseAnimation.value * 0.6),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Watch Together',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Outfit',
            ),
          ),
          const SizedBox(width: 10),
          _ConnectionChip(status: service.connectionStatus),
        ],
      ),
      actions: [
        // Auto-join toggle
        Tooltip(
          message: _autoJoin
              ? 'Auto-join: ON (will play when host starts)'
              : 'Auto-join: OFF',
          child: GestureDetector(
            onTap: () => setState(() => _autoJoin = !_autoJoin),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _autoJoin
                    ? Colors.deepPurpleAccent.withValues(alpha: 0.25)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _autoJoin
                      ? Colors.deepPurpleAccent
                      : Colors.white24,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_circle_outline,
                    color:
                        _autoJoin ? Colors.deepPurpleAccent : Colors.white38,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Auto',
                    style: TextStyle(
                      color: _autoJoin
                          ? Colors.deepPurpleAccent
                          : Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Leave button
        IconButton(
          icon: const Icon(Icons.logout_rounded,
              color: Colors.redAccent, size: 20),
          tooltip: 'Leave Room',
          onPressed: () => _showLeaveDialog(service),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildWideLayout(WatchTogetherService service,
      WatchMediaPayload? media, bool isDefaultSession) {
    return Row(
      children: [
        // Left: media + participants
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRoomCodeCard(service),
                const SizedBox(height: 16),
                _buildMediaCard(service, media, isDefaultSession),
                const SizedBox(height: 16),
                _buildParticipantsCard(service),
              ],
            ),
          ),
        ),
        // Right: chat
        Container(
          width: 320,
          decoration: const BoxDecoration(
            color: Color(0xFF111118),
            border: Border(left: BorderSide(color: Colors.white10)),
          ),
          child: _buildChatPanel(service),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(WatchTogetherService service,
      WatchMediaPayload? media, bool isDefaultSession) {
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildRoomCodeCard(service),
                    const SizedBox(height: 14),
                    _buildMediaCard(service, media, isDefaultSession),
                    const SizedBox(height: 14),
                    _buildParticipantsCard(service),
                    const SizedBox(height: 14),
                    // Chat header for narrow
                    const Row(
                      children: [
                        Icon(Icons.chat_rounded,
                            color: Colors.deepPurpleAccent, size: 16),
                        SizedBox(width: 8),
                        Text('Live Chat',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                fontFamily: 'Outfit')),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ]),
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildChatMessages(service),
                ),
              ),
            ],
          ),
        ),
        // Emoji + input fixed at bottom
        _buildChatInputArea(service),
      ],
    );
  }

  // ── Room Code Card ────────────────────────────────────────────────────────────

  Widget _buildRoomCodeCard(WatchTogetherService service) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.withValues(alpha: 0.3),
            Colors.deepPurpleAccent.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.deepPurpleAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Room Code',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2),
                ),
                const SizedBox(height: 4),
                Text(
                  service.roomCode,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  service.isHost
                      ? 'Share this code with friends'
                      : 'You are a guest in this room',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Column(
            children: [
              _ActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy',
                color: Colors.deepPurpleAccent,
                onTap: () => _copyRoomCode(service.roomCode),
              ),
              const SizedBox(height: 8),
              _ActionButton(
                icon: Icons.share_rounded,
                label: 'Share',
                color: Colors.blueAccent,
                onTap: () {
                  final text =
                      'Join my Watch Together room on WatchAny!\nRoom code: ${service.roomCode}';
                  Clipboard.setData(ClipboardData(text: text));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Share text copied to clipboard!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Media Card ───────────────────────────────────────────────────────────────

  Widget _buildMediaCard(WatchTogetherService service,
      WatchMediaPayload? media, bool isDefaultSession) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151520),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.movie_rounded,
                    color: Colors.amber, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('Now Watching',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 12),
          if (isDefaultSession) ...[
            const Text(
              'Waiting for media...',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 4),
            const Text(
              'Browse and start playing something to sync with the room.',
              style: TextStyle(color: Colors.white30, fontSize: 12),
            ),
          ] else ...[
            Text(
              media?.title ?? 'Unknown Title',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (media?.isMovie == false && media?.episodeNumber != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Episode ${media!.episodeNumber}',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12.5),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (service.isHost && isDefaultSession)
                Expanded(
                  child: _PrimaryButton(
                    icon: Icons.search_rounded,
                    label: 'Browse & Pick Movie',
                    color: Colors.amber.shade700,
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              if (!isDefaultSession) ...[
                Expanded(
                  child: _PrimaryButton(
                    icon: Icons.play_arrow_rounded,
                    label: 'Join Stream',
                    color: Colors.deepPurpleAccent,
                    onTap: () {
                      if (media != null) {
                        WatchTogetherService.resolveAndPlay(
                            context, media);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                _ActionButton(
                  icon: _autoJoin
                      ? Icons.sync_rounded
                      : Icons.sync_disabled_rounded,
                  label: _autoJoin ? 'Auto ON' : 'Auto OFF',
                  color: _autoJoin
                      ? Colors.greenAccent
                      : Colors.white38,
                  onTap: () =>
                      setState(() => _autoJoin = !_autoJoin),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Participants Card ─────────────────────────────────────────────────────────

  Widget _buildParticipantsCard(WatchTogetherService service) {
    final participants = service.participants;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151520),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded,
                  color: Colors.deepPurpleAccent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Watching Together (${participants.length})',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: participants.isEmpty
                ? const Center(
                    child: Text('No participants yet',
                        style: TextStyle(color: Colors.white30)))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: participants.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: 12),
                    itemBuilder: (ctx, i) {
                      final p = participants[i];
                      return _ParticipantChip(participant: p);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Chat Panel ────────────────────────────────────────────────────────────────

  Widget _buildChatPanel(WatchTogetherService service) {
    return Column(
      children: [
        // Header
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: const Row(
            children: [
              Icon(Icons.chat_rounded,
                  color: Colors.deepPurpleAccent, size: 16),
              SizedBox(width: 8),
              Text('Live Chat',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Outfit')),
            ],
          ),
        ),
        // Messages
        Expanded(child: _buildChatMessages(service)),
        // Input
        _buildChatInputArea(service),
      ],
    );
  }

  Widget _buildChatMessages(WatchTogetherService service) {
    final messages = service.chatMessages;
    _scrollToBottom();

    return ListView.builder(
      controller: _chatScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (ctx, i) {
        final msg = messages[i];
        return _ChatBubble(
          message: msg,
          isMe: msg.senderId == service.myId,
        );
      },
    );
  }

  Widget _buildChatInputArea(WatchTogetherService service) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111118),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Emoji quick bar
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['❤️', '😂', '😱', '🔥', '👏', '🍿', '😭', '🎉']
                  .map((emoji) => InkWell(
                        onTap: () =>
                            service.sendEmojiReaction(emoji),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 18)),
                        ),
                      ))
                  .toList(),
            ),
          ),
          // Text input
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13.5),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (text) {
                      if (text.trim().isNotEmpty) {
                        service.sendChatMessage(text);
                        _chatController.clear();
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Say something...',
                      hintStyle: const TextStyle(
                          color: Colors.white30, fontSize: 13),
                      filled: true,
                      fillColor:
                          Colors.white.withValues(alpha: 0.05),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    final text = _chatController.text.trim();
                    if (text.isNotEmpty) {
                      service.sendChatMessage(text);
                      _chatController.clear();
                    }
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Colors.deepPurpleAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 17),
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

// ─── Sub-Widgets ──────────────────────────────────────────────────────────────

class _ConnectionChip extends StatelessWidget {
  final WTConnectionStatus status;
  const _ConnectionChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (status) {
      case WTConnectionStatus.connected:
        color = Colors.greenAccent;
        label = 'Online';
        break;
      case WTConnectionStatus.connecting:
      case WTConnectionStatus.generatingOffer:
      case WTConnectionStatus.generatingAnswer:
      case WTConnectionStatus.waitingForAnswer:
        color = Colors.amberAccent;
        label = 'Connecting...';
        break;
      case WTConnectionStatus.reconnecting:
        color = Colors.orangeAccent;
        label = 'Reconnecting...';
        break;
      case WTConnectionStatus.disconnected:
        color = Colors.redAccent;
        label = 'Offline';
        break;
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ParticipantChip extends StatelessWidget {
  final WatchParticipant participant;
  const _ParticipantChip({required this.participant});

  Color _avatarColor(String name) {
    final colors = [
      Colors.deepPurple,
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
      Colors.amber,
    ];
    final idx = name.isEmpty ? 0 : name.codeUnitAt(0) % colors.length;
    return colors[idx];
  }

  @override
  Widget build(BuildContext context) {
    final color = _avatarColor(participant.name);
    final initial =
        participant.name.isNotEmpty ? participant.name[0].toUpperCase() : '?';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(
                  color: participant.isHost
                      ? Colors.amberAccent
                      : color.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(initial,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ),
            ),
            // Status dot
            Positioned(
              bottom: -2,
              right: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: participant.isBuffering
                      ? Colors.orangeAccent
                      : Colors.greenAccent,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFF0A0A0F), width: 2),
                ),
              ),
            ),
            // Host crown
            if (participant.isHost)
              const Positioned(
                top: -8,
                left: 0,
                right: 0,
                child: Center(
                  child: Text('👑', style: TextStyle(fontSize: 12)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: 52,
          child: Text(
            participant.name,
            style: const TextStyle(
                color: Colors.white70, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final WatchChatMessage message;
  final bool isMe;
  const _ChatBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    if (message.isSystemMessage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              message.text,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment:
            isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.deepPurpleAccent.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isMe ? 14 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 14),
            ),
            border: Border.all(
              color: isMe
                  ? Colors.deepPurpleAccent.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    message.senderName,
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Text(
                message.text,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5)),
          ],
        ),
      ),
    );
  }
}
