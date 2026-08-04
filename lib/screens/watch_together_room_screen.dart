import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/watch_together_service.dart';

class WatchTogetherRoomScreen extends StatefulWidget {
  const WatchTogetherRoomScreen({super.key});

  @override
  State<WatchTogetherRoomScreen> createState() => _WatchTogetherRoomScreenState();
}

class _WatchTogetherRoomScreenState extends State<WatchTogetherRoomScreen> {
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _autoJoin = true;

  @override
  void initState() {
    super.initState();
    final service = WatchTogetherService();
    
    // Auto-launch playback if autoJoin is enabled and media videoUrl becomes available
    service.setMediaReceivedCallback((media) {
      if (_autoJoin && media.videoUrl != null && media.videoUrl!.isNotEmpty) {
        if (mounted) {
          WatchTogetherService.resolveAndPlay(context, media);
        }
      }
    });
  }

  @override
  void dispose() {
    _chatInputController.dispose();
    _chatScrollController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 750;

    return ListenableBuilder(
      listenable: WatchTogetherService(),
      builder: (context, _) {
        final service = WatchTogetherService();
        final media = service.mediaPayload;

        return Scaffold(
          backgroundColor: const Color(0xFF0F0F12),
          appBar: AppBar(
            backgroundColor: const Color(0xFF141417),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () {
                _showLeaveConfirmation(context, service);
              },
            ),
            title: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.greenAccent,
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Watch Together Room',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
            actions: [
              // Room Code Chip
              Container(
                margin: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Code: ',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      service.roomCode,
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: service.roomCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Room code copied!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Icon(Icons.copy_rounded, color: Colors.white70, size: 14),
                    ),
                  ],
                ),
              ),

              // Leave Room Button
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                tooltip: 'Leave Room',
                onPressed: () => _showLeaveConfirmation(context, service),
              ),
            ],
          ),
          body: isMobile
              ? Column(
                  children: [
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildMediaCard(context, service, media),
                            const SizedBox(height: 16),
                            _buildParticipantsCard(context, service),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: _buildChatPanel(context, service),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            _buildMediaCard(context, service, media),
                            const SizedBox(height: 20),
                            _buildParticipantsCard(context, service),
                          ],
                        ),
                      ),
                    ),
                    Container(width: 1, color: Colors.white10),
                    Expanded(
                      flex: 4,
                      child: _buildChatPanel(context, service),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildMediaCard(
      BuildContext context, WatchTogetherService service, WatchMediaPayload? media) {
    final bool hasVideo = media?.videoUrl != null && media!.videoUrl!.isNotEmpty;
    final bool isDefaultSession = media == null || media.title == 'Watch Together Session';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141417),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Center(
                  child: Icon(Icons.movie_rounded, color: Colors.deepPurpleAccent, size: 32),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDefaultSession ? 'Room Active - Pick Media to Watch' : (media!.title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasVideo
                            ? Colors.greenAccent.withValues(alpha: 0.15)
                            : Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: hasVideo
                                ? Colors.greenAccent.withValues(alpha: 0.4)
                                : Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasVideo ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                            color: hasVideo ? Colors.greenAccent : Colors.amberAccent,
                            size: 13,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hasVideo ? 'Stream Ready' : 'Waiting for host stream...',
                            style: TextStyle(
                              color: hasVideo ? Colors.greenAccent : Colors.amberAccent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Action Buttons Row
          Row(
            children: [
              if (service.isHost && isDefaultSession)
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(); // Return to home/browse to pick a movie
                      },
                      icon: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                      label: const Text(
                        'Browse & Select Movie',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade800,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: media == null
                          ? null
                          : () {
                              WatchTogetherService.resolveAndPlay(context, media);
                            },
                      icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                      label: Text(
                        hasVideo ? 'Join Stream & Watch' : 'Resolve & Watch Now',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        disabledBackgroundColor: Colors.white10,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Auto-launch player when host plays',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Switch(
                value: _autoJoin,
                activeColor: Colors.deepPurpleAccent,
                onChanged: (val) => setState(() => _autoJoin = val),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsCard(BuildContext context, WatchTogetherService service) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141417),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.people_alt_rounded, color: Colors.deepPurpleAccent, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Room Participants',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${service.participants.length} Active',
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: service.participants.map((p) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: p.isHost
                      ? Colors.deepPurpleAccent.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: p.isHost
                        ? Colors.deepPurpleAccent.withValues(alpha: 0.6)
                        : Colors.white10,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: p.isHost ? Colors.deepPurpleAccent : Colors.blueGrey,
                      child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      p.name,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (p.isHost) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 14),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPanel(BuildContext context, WatchTogetherService service) {
    return Container(
      color: const Color(0xFF121215),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: const Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded, color: Colors.deepPurpleAccent, size: 18),
                SizedBox(width: 8),
                Text(
                  'Room Chat',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: ListView.builder(
              controller: _chatScrollController,
              padding: const EdgeInsets.all(12),
              itemCount: service.chatMessages.length,
              itemBuilder: (context, index) {
                final chat = service.chatMessages[index];
                if (chat.isSystemMessage) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: Text(
                        chat.text,
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 11.5),
                      ),
                    ),
                  );
                }

                final isMe = chat.senderId == service.myId;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.deepPurpleAccent.withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Text(
                            chat.senderName,
                            style: const TextStyle(
                                color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        Text(
                          chat.text,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Emoji Quick Bar
          Container(
            height: 38,
            color: Colors.black.withValues(alpha: 0.3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['❤️', '😂', '😱', '🔥', '👏', '🍿'].map((emoji) {
                return InkWell(
                  onTap: () => service.sendEmojiReaction(emoji),
                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                );
              }).toList(),
            ),
          ),

          // Input field
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatInputController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Type message...',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    onSubmitted: (text) {
                      if (text.trim().isNotEmpty) {
                        service.sendChatMessage(text);
                        _chatInputController.clear();
                        _scrollToBottom();
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.deepPurpleAccent, size: 18),
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
    );
  }

  void _showLeaveConfirmation(BuildContext context, WatchTogetherService service) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141417),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Room?', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to leave this Watch Together session?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.of(ctx).pop(); // Close dialog
              service.leaveRoom();
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop(); // Exit WatchTogetherRoomScreen
              }
            },
            child: const Text('Leave Room', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
