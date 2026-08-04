import 'dart:math';
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

class _WatchTogetherDialogState extends State<WatchTogetherDialog> {
  int _selectedTabIndex = 0; // 0: Create, 1: Join
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
    if (widget.mediaPayload == null) {
      _selectedTabIndex = 1; // Default to Join tab if opened globally without a host payload
    }
  }

  @override
  void dispose() {
    _hostNameController.dispose();
    _guestNameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateRoom() async {
    if (widget.mediaPayload == null) {
      setState(() => _errorMessage = 'No media selected to host.');
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
      } else {
        WatchTogetherService.launchMediaPayload(context, widget.mediaPayload!);
      }
    } else {
      setState(() => _errorMessage = 'Failed to create room. Please try again.');
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

    void launchPlayback(WatchMediaPayload media) {
      if (!mounted) return;
      Navigator.of(context).pop();
      if (widget.onStartPlayback != null) {
        widget.onStartPlayback!(media);
      } else {
        WatchTogetherService.launchMediaPayload(context, media);
      }
    }

    // Bind callback FIRST before joining so we never miss incoming ROOM_STATE
    service.setMediaReceivedCallback(launchPlayback);

    final success = await service.joinRoom(
      code: code,
      guestName: _guestNameController.text,
    );

    if (!mounted) return;
    setState(() => _isConnecting = false);

    if (success) {
      // Check if host media is already populated
      if (service.mediaPayload != null) {
        launchPlayback(service.mediaPayload!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Joined Room $code! Syncing stream with host...'),
            backgroundColor: Colors.deepPurple,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      setState(() => _errorMessage = 'Could not join room $code. Verify code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double dialogWidth = min(screenWidth - 32.0, 430.0);

    return Dialog(
      backgroundColor: const Color(0xFF141417),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.0),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: SingleChildScrollView(
        child: Container(
          width: dialogWidth,
          padding: const EdgeInsets.all(22.0),
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
                      color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14.0),
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
                            fontSize: 19.0,
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
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20.0),

              // Modern Custom Segmented Control (Zero Overflow)
              Container(
                height: 44,
                padding: const EdgeInsets.all(4.0),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    if (widget.mediaPayload != null)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTabIndex = 0),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _selectedTabIndex == 0
                                  ? Colors.deepPurpleAccent
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9.0),
                            ),
                            child: Text(
                              'Create Room',
                              style: TextStyle(
                                color: _selectedTabIndex == 0
                                    ? Colors.white
                                    : Colors.white60,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTabIndex = 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedTabIndex == 1
                                ? Colors.deepPurpleAccent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9.0),
                          ),
                          child: Text(
                            'Join Room',
                            style: TextStyle(
                              color: _selectedTabIndex == 1
                                  ? Colors.white
                                  : Colors.white60,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20.0),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
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

              // Tab 1: Create Room
              if (_selectedTabIndex == 0 && widget.mediaPayload != null) ...[
                const Text(
                  'Your Name / Alias',
                  style: TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.w500),
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
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: const BorderSide(color: Colors.deepPurpleAccent),
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
                        borderRadius: BorderRadius.circular(8),
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
                const SizedBox(height: 24.0),
                SizedBox(
                  width: double.infinity,
                  height: 48,
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
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                  ),
                ),
              ],

              // Tab 2: Join Room
              if (_selectedTabIndex == 1 || widget.mediaPayload == null) ...[
                const Text(
                  'Your Name',
                  style: TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.w500),
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
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: const BorderSide(color: Colors.deepPurpleAccent),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14.0, vertical: 11.0),
                  ),
                ),
                const SizedBox(height: 14.0),
                const Text(
                  '6-Digit Room Code',
                  style: TextStyle(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6.0),
                TextField(
                  controller: _roomCodeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 18.0,
                      letterSpacing: 6.0,
                      fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '849201',
                    hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2),
                        letterSpacing: 6.0),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: const BorderSide(color: Colors.deepPurpleAccent),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14.0, vertical: 11.0),
                  ),
                ),
                const SizedBox(height: 24.0),
                SizedBox(
                  width: double.infinity,
                  height: 48,
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
                      _isConnecting ? 'Joining Room...' : 'Join Room & Watch',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15.0),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
