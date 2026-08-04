import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/watch_together_service.dart';

class WatchTogetherDialog extends StatefulWidget {
  final WatchMediaPayload? mediaPayload;
  final Function(WatchMediaPayload media)? onStartPlayback;

  const WatchTogetherDialog({
    super.key,
    this.mediaPayload,
    this.onStartPlayback,
  });

  @override
  State<WatchTogetherDialog> createState() => _WatchTogetherDialogState();
}

class _WatchTogetherDialogState extends State<WatchTogetherDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _hostNameController =
      TextEditingController(text: 'Host');
  final TextEditingController _guestNameController =
      TextEditingController(text: 'Guest');
  final TextEditingController _roomCodeController = TextEditingController();

  bool _isConnecting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hostNameController.dispose();
    _guestNameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateRoom() async {
    if (widget.mediaPayload == null) {
      setState(() => _errorMessage = 'No media payload available to stream.');
      return;
    }
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    final service = WatchTogetherService();
    final success = await service.createRoom(
      hostName: _hostNameController.text,
      media: widget.mediaPayload!,
    );

    if (!mounted) return;
    setState(() => _isConnecting = false);

    if (success) {
      Navigator.of(context).pop();
      if (widget.onStartPlayback != null) {
        widget.onStartPlayback!(widget.mediaPayload!);
      }
    } else {
      setState(() => _errorMessage = 'Failed to connect host signaling server.');
    }
  }

  Future<void> _handleJoinRoom() async {
    final code = _roomCodeController.text.trim();
    if (code.length < 4) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit room code.');
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    final service = WatchTogetherService();
    
    // Bind media received callback to launch player automatically for Guest!
    service.setMediaReceivedCallback((media) {
      if (mounted) {
        Navigator.of(context).pop();
        if (widget.onStartPlayback != null) {
          widget.onStartPlayback!(media);
        }
      }
    });

    final success = await service.joinRoom(
      code: code,
      guestName: _guestNameController.text,
    );

    if (!mounted) return;
    setState(() => _isConnecting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Joined Room $code! Syncing with host...'),
          backgroundColor: Colors.deepPurple,
        ),
      );
    } else {
      setState(() => _errorMessage = 'Could not connect to room. Check room code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141417),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: const BorderSide(color: Colors.white12),
      ),
      child: SingleChildScrollView(
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10.0),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: const Icon(Icons.groups_rounded,
                        color: Colors.deepPurpleAccent, size: 24),
                  ),
                  const SizedBox(width: 14.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Watch Together',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20.0,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        Text(
                          widget.mediaPayload?.title ?? 'SyncPlay Room',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20.0),

              // Tab Switcher
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: Colors.deepPurpleAccent,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                  tabs: const [
                    Tab(text: 'Create Room'),
                    Tab(text: 'Join Room'),
                  ],
                ),
              ),
              const SizedBox(height: 20.0),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16.0),
              ],

              SizedBox(
                height: 230,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Create Room
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your Name / Alias',
                          style: TextStyle(color: Colors.white70, fontSize: 12.0),
                        ),
                        const SizedBox(height: 6.0),
                        TextField(
                          controller: _hostNameController,
                          style: const TextStyle(color: Colors.white, fontSize: 14.0),
                          decoration: InputDecoration(
                            hintText: 'Enter your name',
                            hintStyle: const TextStyle(color: Colors.white30),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14.0, vertical: 12.0),
                          ),
                        ),
                        const SizedBox(height: 12.0),
                        ListenableBuilder(
                          listenable: WatchTogetherService(),
                          builder: (context, _) {
                            final ip = WatchTogetherService().hostLocalIp;
                            if (ip == null) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'LAN Direct Sync IP: $ip:8492',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          },
                        ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: _isConnecting ? null : _handleCreateRoom,
                            icon: _isConnecting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.play_arrow_rounded, color: Colors.white),
                            label: Text(
                              _isConnecting ? 'Creating Room...' : 'Start Watch Together',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15.0),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurpleAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Tab 2: Join Room
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your Name',
                          style: TextStyle(color: Colors.white70, fontSize: 12.0),
                        ),
                        const SizedBox(height: 6.0),
                        TextField(
                          controller: _guestNameController,
                          style: const TextStyle(color: Colors.white, fontSize: 14.0),
                          decoration: InputDecoration(
                            hintText: 'Enter your name',
                            hintStyle: const TextStyle(color: Colors.white30),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14.0, vertical: 10.0),
                          ),
                        ),
                        const SizedBox(height: 12.0),
                        const Text(
                          '6-Digit Room Code',
                          style: TextStyle(color: Colors.white70, fontSize: 12.0),
                        ),
                        const SizedBox(height: 6.0),
                        TextField(
                          controller: _roomCodeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          maxLength: 6,
                          style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 16.0,
                              letterSpacing: 4.0,
                              fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '849201',
                            hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.2),
                                letterSpacing: 4.0),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14.0, vertical: 10.0),
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: _isConnecting ? null : _handleJoinRoom,
                            icon: _isConnecting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.group_add_rounded, color: Colors.white),
                            label: Text(
                              _isConnecting ? 'Joining...' : 'Join Room & Watch',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15.0),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurpleAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
