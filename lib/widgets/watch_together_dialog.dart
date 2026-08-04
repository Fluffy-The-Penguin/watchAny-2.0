import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/watch_together_service.dart';
import '../screens/watch_together_room_screen.dart';

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

  final _hostNameCtrl = TextEditingController(text: 'Host');
  final _guestNameCtrl = TextEditingController(text: 'Guest');
  final _roomCodeCtrl = TextEditingController();

  // Advanced Manual Exchange fallbacks
  bool _showManualExchange = false;
  final _offerInputCtrl = TextEditingController();
  final _answerInputCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

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
    _roomCodeCtrl.dispose();
    _offerInputCtrl.dispose();
    _answerInputCtrl.dispose();
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

  // ─── 6-Digit Auto Host Flow ────────────────────────────────────────────────

  Future<void> _handleCreateRoom() async {
    setState(() { _loading = true; _error = null; });

    final defaultPayload = WatchMediaPayload(
      title: 'Watch Together Session',
      movieId: 'room_${WatchTogetherService.generateRoomCode()}',
      episodeNumber: 1,
      isMovie: true,
    );

    final ok = await _service.createRoom(
      hostName: _hostNameCtrl.text,
      media: widget.mediaPayload ?? defaultPayload,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      _closeModal();
      _openRoomScreen();
      if (widget.onStartPlayback != null && widget.mediaPayload != null) {
        widget.onStartPlayback!(widget.mediaPayload!);
      }
    } else {
      setState(() => _error = 'Failed to create room. Please try again.');
    }
  }

  // ─── 6-Digit Auto Guest Flow ───────────────────────────────────────────────

  Future<void> _handleJoinRoom() async {
    final code = _roomCodeCtrl.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Please enter a valid 6-digit room code.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final ok = await _service.joinRoom(
      code: code,
      guestName: _guestNameCtrl.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      _closeModal();
      _openRoomScreen();
    } else {
      setState(() => _error = 'Could not join room $code. Verify code or make sure host is online.');
    }
  }

  // ─── Advanced Manual Fallbacks ─────────────────────────────────────────────

  Future<void> _handleManualAnswer() async {
    final offer = _offerInputCtrl.text.trim();
    if (offer.isEmpty) {
      setState(() => _error = 'Please paste the offer code.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    await _service.joinWithOffer(offerCode: offer, guestName: _guestNameCtrl.text);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final dialogWidth = min(MediaQuery.of(context).size.width - 32.0, 440.0);

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
              _buildHeader(),
              const SizedBox(height: 20.0),
              _buildTabs(),
              const SizedBox(height: 20.0),
              if (_error != null) ...[_buildError(), const SizedBox(height: 16.0)],
              if (_tabIndex == 0) _buildCreateTab(),
              if (_tabIndex == 1) _buildJoinTab(),
            ],
          ),
        ),
      ),
    );
  }

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
                  widget.mediaPayload?.title ?? 'SyncPlay Room',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5),
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

  Widget _buildError() => Container(
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
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
          ],
        ),
      );

  // ─── Create Tab ────────────────────────────────────────────────────────────

  Widget _buildCreateTab() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Your Name / Alias'),
          const SizedBox(height: 6.0),
          _textField(_hostNameCtrl, 'Enter your name'),
          const SizedBox(height: 16.0),
          _infoBox(
            icon: Icons.bolt_rounded,
            color: Colors.deepPurpleAccent,
            text: 'You will get a 6-digit room code to share with your friends.',
          ),
          const SizedBox(height: 20.0),
          _actionButton(
            label: _loading ? 'Creating Room...' : 'Start Watch Together',
            icon: Icons.play_arrow_rounded,
            loading: _loading,
            onPressed: _handleCreateRoom,
          ),
        ],
      );

  // ─── Join Tab ──────────────────────────────────────────────────────────────

  Widget _buildJoinTab() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Your Name'),
          const SizedBox(height: 6.0),
          _textField(_guestNameCtrl, 'Enter your name'),
          const SizedBox(height: 14.0),
          _label('6-Digit Room Code'),
          const SizedBox(height: 6.0),
          TextField(
            controller: _roomCodeCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            style: const TextStyle(
                color: Colors.amberAccent,
                fontSize: 20.0,
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
          const SizedBox(height: 20.0),
          _actionButton(
            label: _loading ? 'Joining Room...' : 'Join Room & Watch',
            icon: Icons.group_add_rounded,
            loading: _loading,
            onPressed: _handleJoinRoom,
          ),

          // Advanced manual exchange foldout
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _showManualExchange = !_showManualExchange),
              icon: Icon(
                _showManualExchange ? Icons.expand_less : Icons.tune_rounded,
                size: 14,
                color: Colors.white38,
              ),
              label: Text(
                _showManualExchange ? 'Hide Manual Code Exchange' : 'Manual Signal Exchange (Offline)',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ),
          if (_showManualExchange) ...[
            const SizedBox(height: 8),
            _label('Paste Offer Code from Host'),
            const SizedBox(height: 6),
            _multilineField(_offerInputCtrl, 'Paste offer string...'),
            const SizedBox(height: 10),
            _actionButton(
              label: 'Generate Manual Answer',
              icon: Icons.cable_rounded,
              loading: _loading,
              onPressed: _handleManualAnswer,
              color: Colors.deepPurple,
            ),
            if (_service.pendingAnswerCode != null) ...[
              const SizedBox(height: 10),
              _label('Copy your Answer Code & send back'),
              const SizedBox(height: 6),
              _codeBox(_service.pendingAnswerCode!),
            ],
          ],
        ],
      );

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.w500),
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
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
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
        maxLines: 3,
        style: const TextStyle(
            color: Colors.amberAccent, fontSize: 10.5, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 12.0),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.04),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
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
          border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.4)),
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
