import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/watch_together_service.dart';
import '../screens/watch_together_room_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Watch Together Dialog — Professional Join / Host UI
//
// HOST FLOW:
//   1. Enter name → Create Room
//   2. Room is created → 6-digit code shown prominently + Share button
//   3. When a guest answers → status updates live (via SSE listener in service)
//   4. Open Room → goes to room screen
//
// GUEST FLOW:
//   1. Enter name + 6-digit code → Join Room
//   2. Connection progress shown step by step
//   3. Success → goes to room screen automatically
//   4. Failure → specific error + "Enter Stream URL directly" fallback
// ═══════════════════════════════════════════════════════════════════════════════

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
  int _tabIndex = 0;

  // Host state
  bool _hostCreating = false;
  bool _hostRoomReady = false;

  // Guest state — tracks step in join flow
  _GuestStep _guestStep = _GuestStep.idle;
  WTJoinResult? _lastJoinResult;

  // Controllers
  final _hostNameCtrl = TextEditingController(text: 'Host');
  final _guestNameCtrl = TextEditingController(text: 'Guest');
  final _roomCodeCtrl = TextEditingController();
  final _streamUrlCtrl = TextEditingController();

  bool _showUrlFallback = false;

  final _service = WatchTogetherService();

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    if (widget.mediaPayload == null) _tabIndex = 1;

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _hostNameCtrl.dispose();
    _guestNameCtrl.dispose();
    _roomCodeCtrl.dispose();
    _streamUrlCtrl.dispose();
    super.dispose();
  }

  void _closeModal() {
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _openRoomScreen() {
    if (!mounted) return;
    _closeModal();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const WatchTogetherRoomScreen()),
    );
  }

  // ─── HOST: Create Room ──────────────────────────────────────────────────────

  Future<void> _handleCreateRoom() async {
    setState(() { _hostCreating = true; _hostRoomReady = false; });

    final defaultPayload = WatchMediaPayload(
      title: 'Watch Together',
      movieId: 'wt_${WatchTogetherService.generateRoomCode()}',
      episodeNumber: 1,
      isMovie: true,
    );

    final ok = await _service.createRoom(
      hostName: _hostNameCtrl.text,
      media: widget.mediaPayload ?? defaultPayload,
    );

    if (!mounted) return;
    setState(() {
      _hostCreating = false;
      _hostRoomReady = ok;
    });

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_service.statusMessage.isNotEmpty
            ? _service.statusMessage
            : 'Failed to create room. Check your internet connection.'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _handleHostOpenRoom() {
    _openRoomScreen();
    if (widget.onStartPlayback != null && widget.mediaPayload != null) {
      widget.onStartPlayback!(widget.mediaPayload!);
    }
  }

  // ─── GUEST: Join Room ───────────────────────────────────────────────────────

  Future<void> _handleJoinByCode() async {
    final code = _roomCodeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() { _guestStep = _GuestStep.error; _lastJoinResult = WTJoinResult.invalidCode; });
      return;
    }

    setState(() { _guestStep = _GuestStep.connecting; _lastJoinResult = null; _showUrlFallback = false; });

    final result = await _service.joinRoom(
      code: code,
      guestName: _guestNameCtrl.text,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() => _guestStep = _GuestStep.connected);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _openRoomScreen();
      });
    } else {
      setState(() {
        _guestStep = _GuestStep.error;
        _lastJoinResult = result;
        _showUrlFallback = true;
      });
    }
  }

  void _onServiceChange() {
    if (!mounted) return;
    if (_service.connectionStatus == WTConnectionStatus.connected) {
      _service.removeListener(_onServiceChange);
      setState(() => _guestStep = _GuestStep.connected);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _openRoomScreen();
      });
    } else if (_service.connectionStatus == WTConnectionStatus.disconnected &&
        _guestStep == _GuestStep.waitingP2P) {
      _service.removeListener(_onServiceChange);
      setState(() {
        _guestStep = _GuestStep.error;
        _lastJoinResult = WTJoinResult.webrtcError;
        _showUrlFallback = true;
      });
    }
  }

  Future<void> _handleJoinByUrl() async {
    final url = _streamUrlCtrl.text.trim();
    if (url.isEmpty) return;

    final payload = WatchMediaPayload(
      title: 'Shared Stream',
      movieId: 'wt_direct',
      videoUrl: url,
      episodeNumber: 1,
      isMovie: true,
    );

    WatchTogetherService.playDirect(payload);
    _closeModal();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final dialogWidth = min(MediaQuery.of(context).size.width - 32.0, 460.0);

    return Dialog(
      backgroundColor: const Color(0xFF111115),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22.0),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: SingleChildScrollView(
        child: Container(
          width: dialogWidth,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 18.0),
              if (_service.isActive) _buildActiveRoomBanner(),
              _buildTabs(),
              const SizedBox(height: 22.0),
              if (_tabIndex == 0) _buildHostFlow(),
              if (_tabIndex == 1) _buildGuestFlow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveRoomBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sensors, color: Colors.tealAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Active Room: ${_service.roomCode}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _service.isHost ? 'HOST' : 'GUEST',
                  style: const TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Participants: ${_service.participants.length} connected',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open Room', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WatchTogetherRoomScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                icon: const Icon(Icons.exit_to_app, size: 16),
                label: const Text('Leave', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  _service.leaveRoom();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.deepPurple.shade700,
                Colors.deepPurpleAccent,
              ]),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.groups_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Watch Together',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                Text(
                  widget.mediaPayload?.title ?? 'P2P · Zero servers required',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.4), size: 20),
            onPressed: _closeModal,
          ),
        ],
      );

  // ─── Tabs ────────────────────────────────────────────────────────────────────

  Widget _buildTabs() => Container(
        height: 42,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            _tabChip('🎬  Create Room', 0),
            _tabChip('🔗  Join Room', 1),
          ],
        ),
      );

  Widget _tabChip(String label, int idx) {
    final active = _tabIndex == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_tabIndex == idx) return;
          setState(() {
            _tabIndex = idx;
            _guestStep = _GuestStep.idle;
            _lastJoinResult = null;
            _showUrlFallback = false;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: active
                ? LinearGradient(colors: [
                    Colors.deepPurple.shade600,
                    Colors.deepPurpleAccent.shade200,
                  ])
                : null,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HOST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHostFlow() {
    if (_hostCreating) return _buildHostCreating();
    if (_hostRoomReady) return _buildHostRoomReady();
    return _buildHostSetup();
  }

  /// Step 0: Name entry
  Widget _buildHostSetup() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Your Display Name'),
          const SizedBox(height: 6),
          _textField(_hostNameCtrl, 'e.g. Alice'),
          const SizedBox(height: 14),
          _infoCard(
            icon: Icons.bolt_rounded,
            color: Colors.deepPurpleAccent,
            title: 'Instant room code',
            body: 'Share a 6-digit code with friends. They join in seconds — no accounts, no downloads.',
          ),
          const SizedBox(height: 22),
          _primaryButton(
            label: 'Create Room',
            icon: Icons.add_circle_outline_rounded,
            onPressed: _handleCreateRoom,
          ),
        ],
      );

  /// Step 1: Creating room (loading)
  Widget _buildHostCreating() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.deepPurpleAccent),
            SizedBox(height: 16),
            Text(
              'Setting up your room...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            SizedBox(height: 6),
            Text(
              'Generating WebRTC offer & publishing to signaling server',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11.5),
            ),
          ],
        ),
      );

  /// Step 2: Room is live — show code and status
  Widget _buildHostRoomReady() => ListenableBuilder(
        listenable: _service,
        builder: (_, __) {
          final connected = _service.guestSlots
              .where((s) => s.status == WTConnectionStatus.connected)
              .length;
          final isConnected = _service.isConnected;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Room Code Card ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.deepPurple.withValues(alpha: 0.4),
                      Colors.deepPurpleAccent.withValues(alpha: 0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.deepPurpleAccent.withValues(alpha: 0.45)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isConnected ? Colors.greenAccent : Colors.amberAccent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (isConnected ? Colors.greenAccent : Colors.amberAccent)
                                    .withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isConnected
                              ? '$connected guest${connected == 1 ? '' : 's'} connected'
                              : 'Waiting for guests...',
                          style: TextStyle(
                            color: isConnected ? Colors.greenAccent : Colors.amberAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Room Code',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Big code display
                    Row(
                      children: [
                        Text(
                          _service.roomCode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 10,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const Spacer(),
                        Column(
                          children: [
                            _iconButton(
                              icon: Icons.copy_rounded,
                              tooltip: 'Copy Code',
                              color: Colors.deepPurpleAccent,
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: _service.roomCode));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Code copied to clipboard!'),
                                    duration: Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 6),
                            _iconButton(
                              icon: Icons.share_rounded,
                              tooltip: 'Share',
                              color: Colors.blueAccent,
                              onTap: () {
                                Clipboard.setData(ClipboardData(
                                    text:
                                        'Join my Watch Together room!\nRoom code: ${_service.roomCode}\n(Open watchAny → Watch Together → Join Room)'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Share text copied!'),
                                    duration: Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Share this 6-digit code with your friends.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.38), fontSize: 11.5),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Guest list (if any)
              if (_service.guestSlots.isNotEmpty) ...[
                _fieldLabel('Guests (${_service.guestSlots.length})'),
                const SizedBox(height: 8),
                ..._service.guestSlots.map((slot) => _buildGuestSlotTile(slot)),
                const SizedBox(height: 14),
              ],

              // Open Room Button (always shown once room is ready)
              _primaryButton(
                label: isConnected
                    ? 'Open Room ($connected connected)'
                    : 'Open Room & Wait for Guests',
                icon: isConnected
                    ? Icons.meeting_room_rounded
                    : Icons.door_front_door_outlined,
                color: isConnected ? Colors.green.shade600 : Colors.deepPurple,
                onPressed: _handleHostOpenRoom,
              ),

              const SizedBox(height: 12),

              // Restart
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() { _hostRoomReady = false; }),
                  icon: const Icon(Icons.refresh_rounded, size: 14, color: Colors.white38),
                  label: const Text('Create a new room',
                      style: TextStyle(color: Colors.white38, fontSize: 11.5)),
                ),
              ),
            ],
          );
        },
      );

  Widget _buildGuestSlotTile(GuestConnection slot) {
    final connected = slot.status == WTConnectionStatus.connected;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: connected
            ? Colors.greenAccent.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: connected
              ? Colors.greenAccent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.check_circle_rounded : Icons.sync_rounded,
            color: connected ? Colors.greenAccent : Colors.amberAccent,
            size: 15,
          ),
          const SizedBox(width: 8),
          Text(
            slot.guestName,
            style: TextStyle(
              color: connected ? Colors.greenAccent : Colors.white60,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            connected ? 'Connected' : 'Connecting...',
            style: TextStyle(
              color: connected ? Colors.greenAccent.withValues(alpha: 0.7) : Colors.amberAccent.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUEST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGuestFlow() {
    switch (_guestStep) {
      case _GuestStep.idle:
        return _buildGuestIdle();
      case _GuestStep.connecting:
        return _buildGuestConnecting();
      case _GuestStep.waitingP2P:
        return _buildGuestWaitingP2P();
      case _GuestStep.connected:
        return _buildGuestConnected();
      case _GuestStep.error:
        return _buildGuestError();
    }
  }

  Widget _buildGuestIdle() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Your Display Name'),
          const SizedBox(height: 6),
          _textField(_guestNameCtrl, 'e.g. Bob'),
          const SizedBox(height: 16),
          _fieldLabel('6-Digit Room Code'),
          const SizedBox(height: 6),
          _roomCodeField(),
          const SizedBox(height: 22),
          _primaryButton(
            label: 'Join Room',
            icon: Icons.group_add_rounded,
            onPressed: _handleJoinByCode,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _showUrlFallback = !_showUrlFallback),
              icon: Icon(
                _showUrlFallback ? Icons.expand_less : Icons.link_rounded,
                size: 14,
                color: Colors.white30,
              ),
              label: Text(
                'Join via stream URL instead',
                style: const TextStyle(color: Colors.white30, fontSize: 11.5),
              ),
            ),
          ),
          if (_showUrlFallback) _buildUrlFallback(),
        ],
      );

  Widget _buildGuestConnecting() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.deepPurpleAccent),
            const SizedBox(height: 16),
            const Text(
              'Connecting...',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            _buildStepProgress(),
          ],
        ),
      );

  Widget _buildStepProgress() => Column(
        children: [
          _stepRow(icon: Icons.wifi_tethering_rounded, label: 'Connecting to room socket channel', done: true),
          _stepRow(icon: Icons.send_rounded, label: 'Sending join request to host', done: true),
          _stepRow(icon: Icons.sync_rounded, label: 'Syncing media & playback state', loading: true),
        ],
      );

  Widget _stepRow({required IconData icon, required String label, bool done = false, bool loading = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent))
                : Icon(done ? Icons.check_circle_rounded : icon,
                    size: 16,
                    color: done ? Colors.greenAccent : Colors.white38),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: done ? Colors.greenAccent.withValues(alpha: 0.8) : Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );

  Widget _buildGuestWaitingP2P() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Opacity(
                opacity: _pulseAnim.value,
                child: const Icon(
                  Icons.wifi_tethering_rounded,
                  color: Colors.deepPurpleAccent,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Answer sent to host!',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'Waiting for peer-to-peer handshake...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5),
            ),
            const SizedBox(height: 4),
            Text(
              'This usually takes 2-5 seconds.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11.5),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                _service.removeListener(_onServiceChange);
                setState(() {
                  _guestStep = _GuestStep.idle;
                  _showUrlFallback = true;
                });
              },
              child: const Text('Taking too long? Try a URL instead',
                  style: TextStyle(color: Colors.white38, fontSize: 11.5)),
            ),
          ],
        ),
      );

  Widget _buildGuestConnected() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.greenAccent, size: 36),
            ),
            const SizedBox(height: 14),
            const Text(
              'Connected!',
              style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'Outfit'),
            ),
            const SizedBox(height: 6),
            Text(
              'Opening room...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
            ),
          ],
        ),
      );

  Widget _buildGuestError() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Error banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Could not join room',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _lastJoinResult?.userMessage ??
                      (_service.statusMessage.isNotEmpty
                          ? _service.statusMessage
                          : 'An error occurred.'),
                  style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Retry button
          _primaryButton(
            label: 'Try Again',
            icon: Icons.refresh_rounded,
            color: Colors.deepPurple,
            onPressed: () => setState(() {
              _guestStep = _GuestStep.idle;
              _lastJoinResult = null;
            }),
          ),
          const SizedBox(height: 12),

          // URL Fallback section
          if (_showUrlFallback) _buildUrlFallback()
          else Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _showUrlFallback = true),
              icon: const Icon(Icons.link_rounded, size: 14, color: Colors.amberAccent),
              label: const Text(
                'Join via stream URL directly',
                style: TextStyle(color: Colors.amberAccent, fontSize: 12),
              ),
            ),
          ),
        ],
      );

  Widget _buildUrlFallback() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.link_rounded, color: Colors.amberAccent, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'Join via Stream URL',
                      style: TextStyle(
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Ask the host to share the stream link directly. Paste it below to play independently.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45), fontSize: 11.5, height: 1.4),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _streamUrlCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://... or magnet:...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.amberAccent),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _handleJoinByUrl,
                    icon: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 18),
                    label: const Text(
                      'Play Stream URL',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  // ─── Shared Widgets ─────────────────────────────────────────────────────────

  Widget _roomCodeField() => TextField(
        controller: _roomCodeCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.bold,
          letterSpacing: 8,
          fontFamily: 'Outfit',
        ),
        decoration: InputDecoration(
          hintText: '• • • • • •',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.2),
            letterSpacing: 8,
            fontSize: 22,
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.04),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Colors.deepPurpleAccent, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      );

  Widget _fieldLabel(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      );

  Widget _textField(TextEditingController ctrl, String hint) => TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.deepPurpleAccent),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5)),
                  const SizedBox(height: 3),
                  Text(body,
                      style: TextStyle(
                          color: color.withValues(alpha: 0.7), fontSize: 11.5, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    Color color = Colors.deepPurpleAccent,
  }) =>
      SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white, size: 19),
          label: Text(
            label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13)),
          ),
        ),
      );

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      );
}

// ─── Guest Step Enum ────────────────────────────────────────────────────────

enum _GuestStep { idle, connecting, waitingP2P, connected, error }
