import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/watch_together_service.dart';
import '../screens/watch_together_room_screen.dart';

// ─── Watch Together Dialog ────────────────────────────────────────────────────
//
//  HOST FLOW (Create Room tab):
//    Step 0 → enter name → tap "Start Session"
//    Step 1 → (room active) shows guest slots + "Add Guest" button
//             Each slot shows its offer code + a field to paste the answer back
//
//  GUEST FLOW (Join Room tab):
//    Step 0 → enter name + paste host's offer code → tap "Generate Answer"
//    Step 1 → shows answer code to send back to host, then auto-opens room
// ─────────────────────────────────────────────────────────────────────────────

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
  int _tabIndex = 0; // 0 = Create, 1 = Join

  // Host flow steps: 0 = name entry, 1 = session active / manage guests
  int _hostStep = 0;

  // Guest flow steps: 0 = paste offer, 1 = show answer code
  int _guestStep = 0;

  final _hostNameCtrl = TextEditingController(text: 'Host');
  final _guestNameCtrl = TextEditingController(text: 'Guest');
  final _offerInputCtrl = TextEditingController(); // guest: paste host's offer

  // Per-slot answer controllers (host: one field per guest slot)
  final Map<String, TextEditingController> _answerCtrls = {};

  bool _loading = false;
  String? _error;

  // Track which slots are currently being completed (loading state per slot)
  final Set<String> _completingSlots = {};

  final _service = WatchTogetherService();

  @override
  void initState() {
    super.initState();
    if (widget.mediaPayload == null) _tabIndex = 1;
  }

  @override
  void dispose() {
    _hostNameCtrl.dispose();
    _guestNameCtrl.dispose();
    _offerInputCtrl.dispose();
    for (final c in _answerCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _closeModal() {
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _openRoomScreen() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const WatchTogetherRoomScreen()),
    );
  }

  // ─── Host Step 0: Start the session ────────────────────────────────────────

  void _handleStartSession() {
    setState(() { _loading = true; _error = null; });

    final defaultPayload = WatchMediaPayload(
      title: 'Watch Together Session',
      movieId: 'room_${WatchTogetherService.generateRoomCode()}',
      episodeNumber: 1,
      isMovie: true,
    );

    _service.startHostSession(
      hostName: _hostNameCtrl.text,
      media: widget.mediaPayload ?? defaultPayload,
    );

    setState(() { _loading = false; _hostStep = 1; });
  }

  // ─── Host Step 1: Add a guest slot (generate offer) ────────────────────────

  Future<void> _handleAddGuest() async {
    setState(() { _loading = true; _error = null; });

    try {
      final slot = await _service.addGuest();
      _answerCtrls[slot.slotId] = TextEditingController();
      setState(() {});
    } catch (e) {
      setState(() => _error = 'Failed to generate offer: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Host: Complete a specific slot ────────────────────────────────────────

  Future<void> _handleCompleteSlot(GuestConnection slot) async {
    final answerCode = _answerCtrls[slot.slotId]?.text.trim() ?? '';
    if (answerCode.isEmpty) {
      setState(() => _error = 'Paste the answer code from your guest first.');
      return;
    }

    setState(() {
      _completingSlots.add(slot.slotId);
      _error = null;
    });

    try {
      await _service.completeGuestConnection(slot.slotId, answerCode);
    } catch (e) {
      setState(() => _error = 'Invalid answer code: $e');
    } finally {
      if (mounted) setState(() => _completingSlots.remove(slot.slotId));
    }
  }

  // ─── Host: open the room screen ────────────────────────────────────────────

  void _handleHostOpenRoom() {
    _closeModal();
    _openRoomScreen();
    if (widget.onStartPlayback != null && widget.mediaPayload != null) {
      widget.onStartPlayback!(widget.mediaPayload!);
    }
  }

  // ─── Guest Step 0: paste offer → generate answer ───────────────────────────

  Future<void> _handleGenerateAnswer() async {
    final offer = _offerInputCtrl.text.trim();
    if (offer.isEmpty) {
      setState(() => _error = 'Please paste the offer code from your host.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    await _service.joinWithOffer(
      offerCode: offer,
      guestName: _guestNameCtrl.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (_service.pendingAnswerCode != null) {
      setState(() => _guestStep = 1);
    } else {
      setState(() => _error = 'Invalid offer code. Ask the host to generate a new one.');
    }
  }

  // ─── Guest: open room (connection will auto-complete in the background) ─────

  void _handleGuestOpenRoom() {
    _closeModal();
    _openRoomScreen();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final dialogWidth =
        min(MediaQuery.of(context).size.width - 32.0, 460.0);

    return Dialog(
      backgroundColor: const Color(0xFF141417),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
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
              _buildHeader(),
              const SizedBox(height: 20.0),
              _buildTabs(),
              const SizedBox(height: 20.0),
              if (_error != null) ...[
                _buildError(),
                const SizedBox(height: 16.0),
              ],
              if (_tabIndex == 0) _buildHostFlow(),
              if (_tabIndex == 1) _buildGuestFlow(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Row(
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
                  widget.mediaPayload?.title ??
                      'P2P · No servers · Up to 8 guests',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            onPressed: _closeModal,
          ),
        ],
      );

  // ─── Tab Bar ───────────────────────────────────────────────────────────────

  Widget _buildTabs() => Container(
        height: 44,
        padding: const EdgeInsets.all(4.0),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            _tabChip('Create Room', 0),
            _tabChip('Join Room', 1),
          ],
        ),
      );

  Widget _tabChip(String label, int idx) {
    final active = _tabIndex == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _tabIndex = idx;
          _error = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.deepPurpleAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(9.0),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white60,
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Error Banner ──────────────────────────────────────────────────────────

  Widget _buildError() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_error!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12))),
          ],
        ),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // HOST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHostFlow() =>
      _hostStep == 0 ? _buildHostStep0() : _buildHostStep1();

  // Step 0: Name entry
  Widget _buildHostStep0() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Your Name / Alias'),
          const SizedBox(height: 6.0),
          _textField(_hostNameCtrl, 'Enter your name'),
          const SizedBox(height: 8),
          _infoBox(
            icon: Icons.info_outline,
            color: Colors.deepPurpleAccent,
            text:
                'After starting, use "Add Guest" to invite each friend.\n'
                'Each guest gets their own Offer Code — share it via chat.',
          ),
          const SizedBox(height: 20.0),
          _actionButton(
            label: _loading ? 'Starting...' : 'Start Session',
            icon: Icons.play_arrow_rounded,
            loading: _loading,
            onPressed: _handleStartSession,
          ),
        ],
      );

  // Step 1: Session active — manage guest slots
  Widget _buildHostStep1() {
    return ListenableBuilder(
      listenable: _service,
      builder: (_, __) {
        final liveSlots = _service.guestSlots;
        final liveConnected =
            liveSlots.any((s) => s.status == WTConnectionStatus.connected);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_tethering_rounded,
                      color: Colors.deepPurpleAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Session active · ${liveSlots.length} guest slot(s)',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12.5),
                    ),
                  ),
                  if (liveConnected)
                    GestureDetector(
                      onTap: _handleHostOpenRoom,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Open Room →',
                            style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Guest slot list
            if (liveSlots.isEmpty)
              _infoBox(
                icon: Icons.person_add_alt_1_rounded,
                color: Colors.white38,
                text:
                    'Tap "Add Guest" below to generate an offer code for your first friend.',
              ),

            ...liveSlots.map((slot) => _buildGuestSlot(slot)),

            const SizedBox(height: 14),

            // Add Guest button
            if (liveSlots.length < 8)
              _actionButton(
                label: _loading ? 'Generating...' : '+ Add Guest',
                icon: Icons.person_add_rounded,
                loading: _loading,
                onPressed: _handleAddGuest,
                color: Colors.deepPurple,
              ),
            if (liveConnected) ...[
              const SizedBox(height: 10),
              _actionButton(
                label: 'Open Room',
                icon: Icons.play_circle_rounded,
                loading: false,
                onPressed: _handleHostOpenRoom,
                color: Colors.greenAccent.shade700,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGuestSlot(GuestConnection slot) {
    final ctrl = _answerCtrls[slot.slotId] ??= TextEditingController();
    final isCompleting = _completingSlots.contains(slot.slotId);
    final connected = slot.status == WTConnectionStatus.connected;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: connected
            ? Colors.greenAccent.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: connected
              ? Colors.greenAccent.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                connected
                    ? Icons.check_circle_rounded
                    : Icons.hourglass_empty_rounded,
                color: connected ? Colors.greenAccent : Colors.amber,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                connected ? 'Guest connected ✅' : 'Guest slot (waiting for answer)',
                style: TextStyle(
                  color: connected ? Colors.greenAccent : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          if (!connected && slot.pendingOfferCode != null) ...[
            const SizedBox(height: 10),
            _label('Step 1 — Share this Offer Code with your guest'),
            const SizedBox(height: 6),
            _codeBox(slot.pendingOfferCode!),
            const SizedBox(height: 10),
            _label('Step 2 — Paste their Answer Code'),
            const SizedBox(height: 6),
            _multilineField(ctrl, 'Paste guest\'s answer code...'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton.icon(
                onPressed: isCompleting ? null : () => _handleCompleteSlot(slot),
                icon: isCompleting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.link_rounded,
                        size: 16, color: Colors.white),
                label: Text(
                  isCompleting ? 'Connecting...' : 'Connect Guest',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUEST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGuestFlow() =>
      _guestStep == 0 ? _buildGuestStep0() : _buildGuestStep1();

  Widget _buildGuestStep0() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Your Name'),
          const SizedBox(height: 6.0),
          _textField(_guestNameCtrl, 'Enter your name'),
          const SizedBox(height: 14),
          _label('Paste the Offer Code from your Host'),
          const SizedBox(height: 8),
          _multilineField(_offerInputCtrl, 'Paste offer code here...'),
          const SizedBox(height: 20),
          _actionButton(
            label: _loading ? 'Processing...' : 'Generate Answer Code',
            icon: Icons.reply_rounded,
            loading: _loading,
            onPressed: _handleGenerateAnswer,
          ),
        ],
      );

  Widget _buildGuestStep1() {
    final answerCode = _service.pendingAnswerCode ?? '';

    return ListenableBuilder(
      listenable: _service,
      builder: (_, __) {
        final connected =
            _service.connectionStatus == WTConnectionStatus.connected;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Share this Answer Code with your Host'),
            const SizedBox(height: 8),
            _codeBox(answerCode),
            const SizedBox(height: 14),
            _infoBox(
              icon: Icons.hourglass_top_rounded,
              color: Colors.amberAccent,
              text:
                  'Your host pastes this into their app. The P2P connection\n'
                  'completes automatically — you\'ll see the button turn green.',
            ),
            const SizedBox(height: 20),
            if (connected)
              _actionButton(
                label: 'Connected! Open Room →',
                icon: Icons.check_circle_rounded,
                loading: false,
                color: Colors.green.shade600,
                onPressed: _handleGuestOpenRoom,
              )
            else
              _actionButton(
                label: 'Waiting for host to paste...',
                icon: Icons.hourglass_empty_rounded,
                loading: true,
                onPressed: null,
              ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMMON WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            color: Colors.white70,
            fontSize: 12.0,
            fontWeight: FontWeight.w500),
      );

  Widget _textField(TextEditingController ctrl, String hint) => TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 14.0),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white30),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: const BorderSide(color: Colors.deepPurpleAccent),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        ),
      );

  Widget _multilineField(TextEditingController ctrl, String hint) => TextField(
        controller: ctrl,
        maxLines: 4,
        style: const TextStyle(
            color: Colors.amberAccent,
            fontSize: 10.5,
            fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 12.0),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.04),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: const BorderSide(color: Colors.deepPurpleAccent),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        ),
      );

  Widget _codeBox(String code) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.deepPurpleAccent.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              code,
              style: const TextStyle(
                color: Colors.amberAccent,
                fontSize: 10.5,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 36,
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Code copied to clipboard!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded,
                    size: 16, color: Colors.deepPurpleAccent),
                label: const Text(
                  'Copy Code',
                  style: TextStyle(
                      color: Colors.deepPurpleAccent,
                      fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: Colors.deepPurpleAccent.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _infoBox(
          {required IconData icon,
          required Color color,
          required String text}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: TextStyle(color: color, fontSize: 11.5))),
          ],
        ),
      );

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool loading,
    required VoidCallback? onPressed,
    Color color = Colors.deepPurpleAccent,
  }) =>
      SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Icon(icon, color: Colors.white, size: 18),
          label: Text(
            label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15.0),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0)),
          ),
        ),
      );
}
