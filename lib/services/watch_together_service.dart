import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../state/player_state.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// WATCH TOGETHER — Professional WebRTC P2P Signaling
//
// SIGNALING ARCHITECTURE (collision-safe, multi-guest):
//
//  Host creates room → code=849201, sessionId=xk9m2p (hidden, ensures uniqueness)
//
//  Offer topic  : ntfy.sh/wany_849201
//    Payload    : {"v":1,"sid":"xk9m2p","offer":"<base64>","hostName":"Alice"}
//
//  Answer topic : ntfy.sh/wany_849201_xk9m2p   (unique per host session)
//    Payload    : {"v":1,"gid":"gu7abc","answer":"<base64>","guestName":"Bob"}
//
//  Host subscribes to answer topic via SSE → instant delivery, no polling race.
//  Guest picks LATEST offer from offer topic → extracts sid → posts answer back.
//
//  Multiple guests: each posts to same answer topic with different gid.
//  Host creates a new GuestConnection per answer received.
//
//  FALLBACK: If P2P fails, host publishes stream URL to ntfy media topic.
//            Guest can also manually enter a stream URL in the UI.
// ═══════════════════════════════════════════════════════════════════════════════

const List<Map<String, dynamic>> _kIceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
  {'urls': 'stun:stun2.l.google.com:19302'},
  {'urls': 'stun:stun.cloudflare.com:3478'},
];

// ─── Enums ─────────────────────────────────────────────────────────────────

enum WTConnectionStatus {
  disconnected,
  generatingOffer,
  waitingForAnswer,
  generatingAnswer,
  connecting,
  connected,
  reconnecting,
}

enum WTRole { none, host, guest }

// ─── Guest Connection Slot (host side) ─────────────────────────────────────

class GuestConnection {
  final String slotId;      // internal unique ID
  final String guestId;     // gid from the guest's answer message
  String guestName;
  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  WTConnectionStatus status;

  GuestConnection({required this.slotId, required this.guestId, this.guestName = 'Guest'})
      : status = WTConnectionStatus.connecting;
}

// ─── Data Models ───────────────────────────────────────────────────────────

class WatchParticipant {
  final String id;
  final String name;
  final bool isHost;
  bool isBuffering;
  DateTime lastSeen;

  WatchParticipant({
    required this.id,
    required this.name,
    required this.isHost,
    this.isBuffering = false,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isHost': isHost,
        'isBuffering': isBuffering,
      };

  factory WatchParticipant.fromJson(Map<String, dynamic> json) =>
      WatchParticipant(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Guest',
        isHost: json['isHost'] == true,
        isBuffering: json['isBuffering'] == true,
      );
}

class WatchMediaPayload {
  final String title;
  final String movieId;
  final String? videoUrl;
  final Map<String, String>? headers;
  final String? torrentHash;
  final int episodeNumber;
  final int? season;
  final bool isMovie;

  WatchMediaPayload({
    required this.title,
    required this.movieId,
    this.videoUrl,
    this.headers,
    this.torrentHash,
    this.episodeNumber = 1,
    this.season,
    this.isMovie = true,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'movieId': movieId,
        'videoUrl': videoUrl,
        'headers': headers,
        'torrentHash': torrentHash,
        'episodeNumber': episodeNumber,
        'season': season,
        'isMovie': isMovie,
      };

  factory WatchMediaPayload.fromJson(Map<String, dynamic> json) =>
      WatchMediaPayload(
        title: json['title']?.toString() ?? 'Unknown',
        movieId: json['movieId']?.toString() ?? '',
        videoUrl: json['videoUrl']?.toString(),
        headers: json['headers'] != null
            ? Map<String, String>.from(json['headers'] as Map)
            : null,
        torrentHash: json['torrentHash']?.toString(),
        episodeNumber: (json['episodeNumber'] as num?)?.toInt() ?? 1,
        season: (json['season'] as num?)?.toInt(),
        isMovie: json['isMovie'] != false,
      );
}

class WatchChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final int timestamp;
  final bool isSystemMessage;

  WatchChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.isSystemMessage = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'timestamp': timestamp,
        'isSystemMessage': isSystemMessage,
        'type': 'CHAT_MESSAGE',
      };

  factory WatchChatMessage.fromJson(Map<String, dynamic> json) =>
      WatchChatMessage(
        id: json['id']?.toString() ?? '',
        senderId: json['senderId']?.toString() ?? '',
        senderName: json['senderName']?.toString() ?? 'Unknown',
        text: json['text']?.toString() ?? '',
        timestamp: (json['timestamp'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        isSystemMessage: json['isSystemMessage'] == true,
      );
}

class WatchEmojiReaction {
  final String senderName;
  final String emoji;
  final int timestamp;
  WatchEmojiReaction({required this.senderName, required this.emoji, required this.timestamp});
}

// ─── Internal Signaling Blob ────────────────────────────────────────────────

class _SdpBlob {
  final String type;    // 'offer' or 'answer'
  final String sdp;
  final List<Map<String, dynamic>> candidates;

  _SdpBlob({required this.type, required this.sdp, required this.candidates});

  /// Encode to compact base64url string
  String encode() {
    final data = jsonEncode({'t': type, 's': sdp, 'c': candidates});
    return base64Url.encode(utf8.encode(data));
  }

  static _SdpBlob decode(String code) {
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(code.trim())));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    return _SdpBlob(
      type: json['t']?.toString() ?? 'offer',
      sdp: json['s']?.toString() ?? '',
      candidates: (json['c'] as List?)
              ?.map((c) => Map<String, dynamic>.from(c as Map))
              .toList() ??
          [],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WATCH TOGETHER SERVICE (singleton)
// ═══════════════════════════════════════════════════════════════════════════════

class WatchTogetherService extends ChangeNotifier {
  static final WatchTogetherService _instance = WatchTogetherService._internal();
  factory WatchTogetherService() => _instance;
  WatchTogetherService._internal();

  // ─── State ────────────────────────────────────────────────────────────────

  WTConnectionStatus _connectionStatus = WTConnectionStatus.disconnected;
  WTConnectionStatus get connectionStatus => _connectionStatus;

  WTRole _role = WTRole.none;
  WTRole get role => _role;
  bool get isHost => _role == WTRole.host;
  bool get isActive => _role != WTRole.none;
  bool get isConnected => _connectionStatus == WTConnectionStatus.connected;

  String _myId = '';
  String get myId => _myId;
  String _myName = '';
  String get myName => _myName;

  // The 6-digit human-readable room code
  String _roomCode = '';
  String get roomCode => _roomCode;

  // Host-only: internal session ID that namespaces the answer topic
  String _sessionId = '';

  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  WatchMediaPayload? _mediaPayload;
  WatchMediaPayload? get mediaPayload => _mediaPayload;

  // Guest-only: pending answer code (only populated in manual-exchange mode)
  String? _pendingAnswerCode;
  String? get pendingAnswerCode => _pendingAnswerCode;

  // Host-only: active guest slots
  final List<GuestConnection> _guestSlots = [];
  List<GuestConnection> get guestSlots => List.unmodifiable(_guestSlots);

  final List<WatchParticipant> _participants = [];
  List<WatchParticipant> get participants => List.unmodifiable(_participants);

  final List<WatchChatMessage> _chatMessages = [];
  List<WatchChatMessage> get chatMessages => List.unmodifiable(_chatMessages);

  int _unreadChatCount = 0;
  int get unreadChatCount => _unreadChatCount;

  bool _isChatDrawerOpen = false;
  bool get isChatDrawerOpen => _isChatDrawerOpen;

  Duration _currentPosition = Duration.zero;
  Duration get currentPosition => _currentPosition;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  String? _syncNotice;
  String? get syncNotice => _syncNotice;

  // ─── Streams ──────────────────────────────────────────────────────────────

  final StreamController<WatchEmojiReaction> _reactionCtrl =
      StreamController<WatchEmojiReaction>.broadcast();
  Stream<WatchEmojiReaction> get reactionStream => _reactionCtrl.stream;

  final StreamController<WatchChatMessage> _toastChatCtrl =
      StreamController<WatchChatMessage>.broadcast();
  Stream<WatchChatMessage> get toastChatStream => _toastChatCtrl.stream;

  // ─── Internals ────────────────────────────────────────────────────────────

  // Guest-side PC
  RTCPeerConnection? _guestPc;
  RTCDataChannel? _guestDc;

  Timer? _heartbeatTimer;
  HttpClient? _sseClient;           // SSE connection (host listens for answers)
  bool _sseCancelled = false;
  int _lastPosBroadcastMs = 0;

  Function(Duration, bool)? _onExternalPlaybackSync;
  Function(WatchMediaPayload)? _onMediaReceived;

  // ─── Static Helpers ───────────────────────────────────────────────────────

  static String generateRoomCode() => (100000 + Random().nextInt(900000)).toString();
  static String _genSessionId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }
  static String _genId() => 'u${Random().nextInt(899999) + 100000}';

  // ─── ntfy.sh topic names ──────────────────────────────────────────────────
  // Using 'wany' prefix + code for brevity (ntfy has topic length limits)
  String get _offerTopic  => 'wany$_roomCode';
  String get _answerTopic => 'wany${_roomCode}_$_sessionId';
  String get _mediaTopic  => 'wany${_roomCode}_${_sessionId}_m';

  // ═══════════════════════════════════════════════════════════════════════════
  // HOST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  /// Step 1 (Host): Create room. Returns true if offer published successfully.
  Future<bool> createRoom({
    required String hostName,
    required WatchMediaPayload media,
  }) async {
    _teardown();
    _role = WTRole.host;
    _roomCode = generateRoomCode();
    _sessionId = _genSessionId();
    _myId = _genId();
    _myName = hostName.trim().isNotEmpty ? hostName.trim() : 'Host';
    _mediaPayload = media;
    _participants.add(WatchParticipant(id: _myId, name: _myName, isHost: true));

    _setStatus(WTConnectionStatus.generatingOffer, 'Creating room...');
    notifyListeners();

    try {
      final offerBlob = await _createOfferBlob();
      if (offerBlob == null) {
        _setStatus(WTConnectionStatus.disconnected, 'Failed to create WebRTC offer.');
        notifyListeners();
        return false;
      }

      // Publish offer to shared topic (guests poll this by code)
      final offerPayload = jsonEncode({
        'v': 1,
        'sid': _sessionId,
        'offer': offerBlob,
        'hostName': _myName,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      final published = await _ntfyPost(_offerTopic, offerPayload);
      if (!published) {
        _setStatus(WTConnectionStatus.disconnected,
            'Could not reach signaling server. Check internet connection.');
        notifyListeners();
        return false;
      }

      _setStatus(WTConnectionStatus.waitingForAnswer,
          'Room ready. Waiting for guests...');
      notifyListeners();

      // Start SSE listener for guest answers (non-blocking)
      _startAnswerListener();
      return true;
    } catch (e) {
      developer.log('createRoom error: $e', name: 'WT');
      _setStatus(WTConnectionStatus.disconnected, 'Error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Creates a WebRTC PeerConnection + offer, waits for ICE gathering.
  /// Returns base64url-encoded SDP blob, or null on failure.
  Future<String?> _createOfferBlob() async {
    try {
      final candidates = <RTCIceCandidate>[];
      final iceCompleter = Completer<void>();

      final pc = await createPeerConnection({
        'iceServers': _kIceServers,
        'sdpSemantics': 'unified-plan',
      });

      pc.onIceCandidate = (c) {
        if (c.candidate != null && c.candidate!.isNotEmpty) candidates.add(c);
      };
      pc.onIceGatheringState = (s) {
        if (s == RTCIceGatheringState.RTCIceGatheringStateComplete) {
          if (!iceCompleter.isCompleted) iceCompleter.complete();
        }
      };

      // Create a data channel — the host initiates it
      final dc = await pc.createDataChannel(
        'watchSync',
        RTCDataChannelInit()
          ..ordered = true
          ..maxRetransmits = 5,
      );

      pc.onConnectionState = (s) {
        developer.log('HostPC state: $s', name: 'WT');
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _connectionStatus = WTConnectionStatus.connected;
          _startHeartbeat();
          notifyListeners();
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          addSystemMessage('⚠️ A guest disconnected.');
          notifyListeners();
        }
      };

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // Wait for ICE gathering (up to 8 seconds)
      await iceCompleter.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );

      final blob = _SdpBlob(
        type: 'offer',
        sdp: offer.sdp ?? '',
        candidates: candidates
            .map((c) => {
                  'candidate': c.candidate,
                  'sdpMid': c.sdpMid,
                  'sdpMLineIndex': c.sdpMLineIndex,
                })
            .toList(),
      );

      // Store PC so we can accept the first answer onto it
      // For multi-guest, subsequent answers get their own PCs via _acceptGuestAnswer
      _hostInitialPc = pc;
      _hostInitialDc = dc;

      return blob.encode();
    } catch (e) {
      developer.log('_createOfferBlob error: $e', name: 'WT');
      return null;
    }
  }

  // The first PC is shared and re-used for the first guest's answer.
  // Subsequent guests get brand-new PCs (via addGuest which re-offers).
  RTCPeerConnection? _hostInitialPc;
  RTCDataChannel? _hostInitialDc;
  bool _firstAnswerConsumed = false;

  /// SSE listener on the answer topic — handles all incoming guest answers.
  void _startAnswerListener() {
    _sseCancelled = false;
    _listenForAnswersSSE(_answerTopic);
  }

  Future<void> _listenForAnswersSSE(String topic) async {
    _sseClient?.close(force: true);
    _sseClient = HttpClient();
    try {
      final uri = Uri.parse('https://ntfy.sh/$topic/sse');
      final req = await _sseClient!.getUrl(uri)
          .timeout(const Duration(seconds: 30));
      req.headers.add('Accept', 'text/event-stream');
      final res = await req.close();

      String buffer = '';
      await for (final chunk in res.transform(utf8.decoder)) {
        if (_sseCancelled) break;
        buffer += chunk;
        // SSE events are separated by double-newline
        while (buffer.contains('\n\n')) {
          final idx = buffer.indexOf('\n\n');
          final event = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 2);
          _handleSseEvent(event);
        }
      }
    } catch (e) {
      if (!_sseCancelled) {
        developer.log('SSE error, reconnecting: $e', name: 'WT');
        await Future.delayed(const Duration(seconds: 3));
        if (!_sseCancelled && isHost) _listenForAnswersSSE(topic);
      }
    }
  }

  void _handleSseEvent(String event) {
    // SSE format: lines starting with "data: "
    for (final line in event.split('\n')) {
      if (!line.startsWith('data: ')) continue;
      try {
        final jsonStr = line.substring(6).trim();
        if (jsonStr == 'open' || jsonStr.isEmpty) continue;
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        // ntfy wraps our message in data.message
        final rawMsg = data['message']?.toString();
        if (rawMsg == null || rawMsg.isEmpty) continue;

        final msg = jsonDecode(rawMsg) as Map<String, dynamic>;
        final v = msg['v'] as int? ?? 0;
        if (v != 1) continue;

        final gid = msg['gid']?.toString() ?? _genId();
        final answerBase64 = msg['answer']?.toString();
        final guestName = msg['guestName']?.toString() ?? 'Guest';

        if (answerBase64 != null && answerBase64.isNotEmpty) {
          _acceptGuestAnswer(gid: gid, answerBase64: answerBase64, guestName: guestName);
        }
      } catch (e) {
        developer.log('SSE event parse error: $e | event: $event', name: 'WT');
      }
    }
  }

  Future<void> _acceptGuestAnswer({
    required String gid,
    required String answerBase64,
    required String guestName,
  }) async {
    // Avoid accepting the same guest twice
    if (_guestSlots.any((s) => s.guestId == gid)) return;

    final slot = GuestConnection(
      slotId: 'slot_${_guestSlots.length}',
      guestId: gid,
      guestName: guestName,
    );
    _guestSlots.add(slot);
    notifyListeners();

    try {
      final answerBlob = _SdpBlob.decode(answerBase64);
      if (answerBlob.type != 'answer') {
        developer.log('Expected answer type, got: ${answerBlob.type}', name: 'WT');
        _guestSlots.remove(slot);
        notifyListeners();
        return;
      }

      late RTCPeerConnection pc;
      late RTCDataChannel dc;

      if (!_firstAnswerConsumed && _hostInitialPc != null) {
        // Reuse the PC we used to generate the original offer
        pc = _hostInitialPc!;
        dc = _hostInitialDc!;
        _firstAnswerConsumed = true;
      } else {
        // For subsequent guests, we need a fresh offer (re-invite flow)
        // For now, signal that max 1 P2P guest is supported per session start
        // Future: implement renegotiation / multi-offer
        developer.log('Additional guest joined: $guestName (relay via host)', name: 'WT');
        // Create a new PC for subsequent guests
        final result = await _createNewGuestPc(slot);
        if (!result) {
          _guestSlots.remove(slot);
          notifyListeners();
        }
        return;
      }

      slot.pc = pc;
      slot.dc = dc;

      // Set up data channel callbacks
      dc.onDataChannelState = (s) {
        if (s == RTCDataChannelState.RTCDataChannelOpen) {
          slot.status = WTConnectionStatus.connected;
          _addOrUpdateParticipant(gid, guestName, isHost: false);
          addSystemMessage('👋 $guestName joined!');
          // Send room state to new guest
          _sendOnChannel(dc, {
            'type': 'ROOM_STATE',
            'senderId': _myId,
            'senderName': _myName,
            'media': _mediaPayload?.toJson(),
            'positionSec': _currentPosition.inMilliseconds / 1000.0,
            'isPlaying': _isPlaying,
            'participants': _participants.map((p) => p.toJson()).toList(),
          });
          notifyListeners();
        }
      };
      dc.onMessage = (msg) => _onHostReceive(msg.text, fromSlot: slot);

      pc.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          slot.status = WTConnectionStatus.connected;
          _connectionStatus = WTConnectionStatus.connected;
          _startHeartbeat();
          notifyListeners();
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          slot.status = WTConnectionStatus.disconnected;
          _participants.removeWhere((p) => p.id == gid);
          addSystemMessage('⚠️ $guestName disconnected.');
          notifyListeners();
        }
      };

      await pc.setRemoteDescription(RTCSessionDescription(answerBlob.sdp, 'answer'));
      for (final c in answerBlob.candidates) {
        await pc.addCandidate(RTCIceCandidate(
          c['candidate']?.toString(),
          c['sdpMid']?.toString(),
          (c['sdpMLineIndex'] as num?)?.toInt(),
        ));
      }

      slot.status = WTConnectionStatus.connecting;
      notifyListeners();
    } catch (e) {
      developer.log('_acceptGuestAnswer error: $e', name: 'WT');
      _guestSlots.remove(slot);
      notifyListeners();
    }
  }

  /// Create a brand-new offer+PC for a subsequent guest (re-invite)
  Future<bool> _createNewGuestPc(GuestConnection slot) async {
    // TODO: full multi-guest re-invite flow
    // For v2.2.04 we log and indicate; full renegotiation in next iteration.
    developer.log('Multi-guest re-invite not yet implemented for slot ${slot.slotId}', name: 'WT');
    return false;
  }

  /// Push current stream URL to all guests via ntfy (fallback for guests who failed P2P)
  Future<void> publishStreamUrl() async {
    if (!isHost || _mediaPayload?.videoUrl == null) return;
    final payload = jsonEncode({
      'v': 1,
      'type': 'MEDIA_FALLBACK',
      'title': _mediaPayload!.title,
      'url': _mediaPayload!.videoUrl,
      'headers': _mediaPayload!.headers,
    });
    await _ntfyPost(_mediaTopic, payload);
    developer.log('Stream URL published to $_mediaTopic', name: 'WT');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUEST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  /// Step 1 (Guest): Join room by 6-digit code.
  Future<WTJoinResult> joinRoom({
    required String code,
    required String guestName,
  }) async {
    final cleanCode = code.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleanCode.length < 4) {
      return WTJoinResult.invalidCode;
    }

    _setStatus(WTConnectionStatus.connecting, 'Looking up room $cleanCode...');
    notifyListeners();

    try {
      // Fetch host's offer from ntfy
      final offerPayload = await _ntfyGetLatest('wany$cleanCode');
      if (offerPayload == null) {
        _setStatus(WTConnectionStatus.disconnected,
            'Room $cleanCode not found. Make sure the host has created the room and both devices have internet access.');
        notifyListeners();
        return WTJoinResult.roomNotFound;
      }

      Map<String, dynamic> offerMsg;
      try {
        offerMsg = jsonDecode(offerPayload) as Map<String, dynamic>;
      } catch (_) {
        _setStatus(WTConnectionStatus.disconnected,
            'Invalid offer format from room $cleanCode.');
        notifyListeners();
        return WTJoinResult.invalidOffer;
      }

      final sid = offerMsg['sid']?.toString();
      final offerBase64 = offerMsg['offer']?.toString();
      final hostName = offerMsg['hostName']?.toString() ?? 'Host';

      if (sid == null || offerBase64 == null) {
        _setStatus(WTConnectionStatus.disconnected, 'Malformed room offer.');
        notifyListeners();
        return WTJoinResult.invalidOffer;
      }

      // Set up our state
      _teardown();
      _role = WTRole.guest;
      _roomCode = cleanCode;
      _sessionId = sid;
      _myId = _genId();
      _myName = guestName.trim().isNotEmpty ? guestName.trim() : 'Guest';
      _participants.add(WatchParticipant(id: _myId, name: _myName, isHost: false));
      _addOrUpdateParticipant('host', hostName, isHost: true);

      _setStatus(WTConnectionStatus.generatingAnswer, "Connecting to $hostName's room...");
      notifyListeners();

      // Generate answer
      final answerBase64 = await _createAnswerBlob(offerBase64);
      if (answerBase64 == null) {
        _setStatus(WTConnectionStatus.disconnected, 'Failed to generate WebRTC answer.');
        notifyListeners();
        return WTJoinResult.webrtcError;
      }

      // Post answer to unique session-namespaced topic
      final answerTopic = 'wany${cleanCode}_$sid';
      final answerPayload = jsonEncode({
        'v': 1,
        'gid': _myId,
        'answer': answerBase64,
        'guestName': _myName,
      });

      final posted = await _ntfyPost(answerTopic, answerPayload);
      if (!posted) {
        _setStatus(WTConnectionStatus.disconnected,
            'Could not reach signaling server. Check internet connection.');
        notifyListeners();
        return WTJoinResult.networkError;
      }

      _setStatus(WTConnectionStatus.connecting, 'Answer sent. Waiting for P2P handshake...');
      notifyListeners();

      // Check for media fallback simultaneously (non-blocking)
      _checkMediaFallback(cleanCode, sid);

      return WTJoinResult.success;
    } catch (e) {
      developer.log('joinRoom error: $e', name: 'WT');
      _setStatus(WTConnectionStatus.disconnected, 'Connection error: $e');
      notifyListeners();
      return WTJoinResult.error;
    }
  }

  Future<String?> _createAnswerBlob(String offerBase64) async {
    try {
      final offerBlob = _SdpBlob.decode(offerBase64);
      if (offerBlob.type != 'offer') {
        throw Exception('Expected offer, got ${offerBlob.type}');
      }

      final candidates = <RTCIceCandidate>[];
      final iceCompleter = Completer<void>();

      _guestPc = await createPeerConnection({
        'iceServers': _kIceServers,
        'sdpSemantics': 'unified-plan',
      });

      _guestPc!.onIceCandidate = (c) {
        if (c.candidate != null && c.candidate!.isNotEmpty) candidates.add(c);
      };
      _guestPc!.onIceGatheringState = (s) {
        if (s == RTCIceGatheringState.RTCIceGatheringStateComplete) {
          if (!iceCompleter.isCompleted) iceCompleter.complete();
        }
      };
      _guestPc!.onConnectionState = (s) {
        developer.log('GuestPC state: $s', name: 'WT');
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _connectionStatus = WTConnectionStatus.connected;
          _statusMessage = 'Connected!';
          _startHeartbeat();
          notifyListeners();
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _connectionStatus = WTConnectionStatus.disconnected;
          addSystemMessage('⚠️ Connection to host lost.');
          notifyListeners();
        }
      };
      _guestPc!.onDataChannel = (channel) {
        _guestDc = channel;
        _setupGuestDataChannel(channel);
      };

      await _guestPc!.setRemoteDescription(
          RTCSessionDescription(offerBlob.sdp, 'offer'));
      for (final c in offerBlob.candidates) {
        await _guestPc!.addCandidate(RTCIceCandidate(
          c['candidate']?.toString(),
          c['sdpMid']?.toString(),
          (c['sdpMLineIndex'] as num?)?.toInt(),
        ));
      }

      final answer = await _guestPc!.createAnswer();
      await _guestPc!.setLocalDescription(answer);

      await iceCompleter.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );

      final blob = _SdpBlob(
        type: 'answer',
        sdp: answer.sdp ?? '',
        candidates: candidates
            .map((c) => {
                  'candidate': c.candidate,
                  'sdpMid': c.sdpMid,
                  'sdpMLineIndex': c.sdpMLineIndex,
                })
            .toList(),
      );
      return blob.encode();
    } catch (e) {
      developer.log('_createAnswerBlob error: $e', name: 'WT');
      return null;
    }
  }

  void _setupGuestDataChannel(RTCDataChannel dc) {
    dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _sendOnChannel(dc, {
          'type': 'JOIN_ROOM',
          'senderId': _myId,
          'senderName': _myName,
          'isHost': false,
        });
      }
    };
    dc.onMessage = (msg) => _onGuestReceive(msg.text);
  }

  /// Poll ntfy for media URL fallback in case P2P is slow/fails
  Future<void> _checkMediaFallback(String code, String sid) async {
    await Future.delayed(const Duration(seconds: 15));
    if (_connectionStatus == WTConnectionStatus.connected) return;
    try {
      final mediaTopic = 'wany${code}_${sid}_m';
      final raw = await _ntfyGetLatest(mediaTopic);
      if (raw == null) return;
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      if (msg['type'] == 'MEDIA_FALLBACK' && msg['url'] != null) {
        final payload = WatchMediaPayload(
          title: msg['title']?.toString() ?? 'Shared Stream',
          movieId: 'wt_fallback',
          videoUrl: msg['url'].toString(),
          headers: msg['headers'] != null
              ? Map<String, String>.from(msg['headers'] as Map)
              : null,
        );
        _mediaPayload = payload;
        addSystemMessage('📡 Host shared a stream URL (P2P fallback).');
        _onMediaReceived?.call(payload);
        notifyListeners();
      }
    } catch (e) {
      developer.log('_checkMediaFallback error: $e', name: 'WT');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ntfy.sh HTTP HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// POST a message to ntfy topic. Returns true on success.
  static Future<bool> _ntfyPost(String topic, String body) async {
    final client = HttpClient();
    try {
      final req = await client
          .postUrl(Uri.parse('https://ntfy.sh/$topic'))
          .timeout(const Duration(seconds: 10));
      req.write(body);
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      developer.log('ntfyPost error [$topic]: $e', name: 'WT');
      return false;
    } finally {
      client.close();
    }
  }

  /// GET the most recent message from an ntfy topic.
  /// Uses ?poll=1&since=1h to only look at recent messages.
  /// Returns the raw string content of the latest message, or null.
  static Future<String?> _ntfyGetLatest(String topic) async {
    final client = HttpClient();
    try {
      // since=1h: only look at messages from last hour
      // poll=1: return cached messages and close
      final uri = Uri.parse('https://ntfy.sh/$topic/json?poll=1&since=1h');
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      final res = await req.close();

      if (res.statusCode != 200) return null;

      final bodyStr = await res.transform(utf8.decoder).join();
      if (bodyStr.trim().isEmpty) return null;

      // ntfy returns NDJSON: one JSON object per line, newest last
      final lines = bodyStr
          .trim()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      // Iterate from newest to oldest
      for (final line in lines.reversed) {
        try {
          final json = jsonDecode(line.trim()) as Map<String, dynamic>;
          final event = json['event']?.toString();
          // Skip keepalive and open events
          if (event != 'message') continue;
          final message = json['message']?.toString();
          if (message != null && message.isNotEmpty) {
            return message;
          }
        } catch (_) {}
      }
      return null;
    } catch (e) {
      developer.log('ntfyGetLatest error [$topic]: $e', name: 'WT');
      return null;
    } finally {
      client.close();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MESSAGE HANDLING — HOST RECEIVES FROM GUESTS
  // ═══════════════════════════════════════════════════════════════════════════

  void _onHostReceive(String rawData, {required GuestConnection fromSlot}) {
    try {
      final msg = jsonDecode(rawData) as Map<String, dynamic>;
      final type = msg['type']?.toString() ?? '';
      final senderId = msg['senderId']?.toString() ?? '';
      if (senderId == _myId) return;

      switch (type) {
        case 'JOIN_ROOM':
          _handleJoinRoom(msg, senderId);
          _broadcastExcept(msg, exceptSlotId: fromSlot.slotId);
          break;
        case 'CHAT_MESSAGE':
          _handleChatMessage(msg);
          _broadcastExcept(msg, exceptSlotId: fromSlot.slotId);
          break;
        case 'EMOJI_REACTION':
          _handleEmojiReaction(msg);
          _broadcastExcept(msg, exceptSlotId: fromSlot.slotId);
          break;
        case 'BUFFERING':
          _handleBuffering(msg, senderId);
          _broadcastExcept(msg, exceptSlotId: fromSlot.slotId);
          break;
        case 'HEARTBEAT':
          _handleHeartbeat(msg, senderId);
          break;
        case 'LEAVE_ROOM':
          _handleLeave(msg, senderId);
          _broadcastExcept(msg, exceptSlotId: fromSlot.slotId);
          break;
        default:
          _broadcastExcept(msg, exceptSlotId: fromSlot.slotId);
      }
    } catch (e) {
      developer.log('Host receive error: $e', name: 'WT');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MESSAGE HANDLING — GUEST RECEIVES FROM HOST
  // ═══════════════════════════════════════════════════════════════════════════

  void _onGuestReceive(String rawData) {
    try {
      final msg = jsonDecode(rawData) as Map<String, dynamic>;
      final type = msg['type']?.toString() ?? '';
      final senderId = msg['senderId']?.toString() ?? '';
      if (senderId == _myId) return;

      switch (type) {
        case 'ROOM_STATE':
          _handleRoomState(msg);
          break;
        case 'JOIN_ROOM':
          _handleJoinRoom(msg, senderId);
          break;
        case 'MEDIA_UPDATE':
          _handleMediaUpdate(msg);
          break;
        case 'PLAYBACK_STATE':
          _handlePlaybackState(msg);
          break;
        case 'BUFFERING':
          _handleBuffering(msg, senderId);
          break;
        case 'CHAT_MESSAGE':
          _handleChatMessage(msg);
          break;
        case 'EMOJI_REACTION':
          _handleEmojiReaction(msg);
          break;
        case 'HEARTBEAT':
          _handleHeartbeat(msg, senderId);
          break;
        case 'LEAVE_ROOM':
          _handleLeave(msg, senderId);
          break;
      }
    } catch (e) {
      developer.log('Guest receive error: $e', name: 'WT');
    }
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _handleJoinRoom(Map<String, dynamic> msg, String senderId) {
    final name = msg['senderName']?.toString() ?? 'Guest';
    _addOrUpdateParticipant(senderId, name, isHost: msg['isHost'] == true);
    addSystemMessage('👋 $name joined!');
  }

  void _handleRoomState(Map<String, dynamic> msg) {
    if (isHost) return;
    if (msg['participants'] is List) {
      for (final item in msg['participants'] as List) {
        if (item is Map) {
          final p = WatchParticipant.fromJson(Map<String, dynamic>.from(item));
          if (p.id != _myId) _addOrUpdateParticipant(p.id, p.name, isHost: p.isHost);
        }
      }
    }
    if (msg['media'] is Map) {
      _mediaPayload = WatchMediaPayload.fromJson(
          Map<String, dynamic>.from(msg['media'] as Map));
      addSystemMessage('🎬 Host is watching: ${_mediaPayload!.title}');
      _onMediaReceived?.call(_mediaPayload!);
    } else {
      addSystemMessage('⌛ Connected! Waiting for host to start.');
    }
    final pos = (msg['positionSec'] as num?)?.toDouble() ?? 0.0;
    if (pos > 0) {
      _applyPlaybackSync(
          Duration(milliseconds: (pos * 1000).round()), msg['isPlaying'] == true);
    }
    notifyListeners();
  }

  void _handleMediaUpdate(Map<String, dynamic> msg) {
    if (isHost) return;
    if (msg['media'] is Map) {
      _mediaPayload = WatchMediaPayload.fromJson(
          Map<String, dynamic>.from(msg['media'] as Map));
      addSystemMessage('🎬 Now playing: ${_mediaPayload!.title}');
      _onMediaReceived?.call(_mediaPayload!);
    }
    final pos = (msg['positionSec'] as num?)?.toDouble() ?? 0.0;
    _applyPlaybackSync(
        Duration(milliseconds: (pos * 1000).round()), msg['isPlaying'] == true);
  }

  void _handlePlaybackState(Map<String, dynamic> msg) {
    final pos = (msg['positionSec'] as num?)?.toDouble() ?? 0.0;
    final playing = msg['isPlaying'] == true;
    _syncNotice = playing ? null : '⏸ ${msg['senderName']} paused';
    _applyPlaybackSync(Duration(milliseconds: (pos * 1000).round()), playing);
  }

  void _handleBuffering(Map<String, dynamic> msg, String senderId) {
    final buffering = msg['isBuffering'] == true;
    final name = msg['senderName']?.toString() ?? 'Participant';
    final idx = _participants.indexWhere((p) => p.id == senderId);
    if (idx >= 0) _participants[idx].isBuffering = buffering;
    _syncNotice = buffering ? '⏳ Waiting for $name...' : null;
    notifyListeners();
  }

  void _handleChatMessage(Map<String, dynamic> msg) {
    final chat = WatchChatMessage.fromJson(msg);
    _chatMessages.add(chat);
    if (!_isChatDrawerOpen) {
      _unreadChatCount++;
      _toastChatCtrl.add(chat);
    }
    notifyListeners();
  }

  void _handleEmojiReaction(Map<String, dynamic> msg) {
    _reactionCtrl.add(WatchEmojiReaction(
      senderName: msg['senderName']?.toString() ?? 'Friend',
      emoji: msg['emoji']?.toString() ?? '❤️',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void _handleHeartbeat(Map<String, dynamic> msg, String senderId) {
    _addOrUpdateParticipant(
      senderId,
      msg['senderName']?.toString() ?? 'Guest',
      isHost: msg['isHost'] == true,
    );
  }

  void _handleLeave(Map<String, dynamic> msg, String senderId) {
    final name = msg['senderName']?.toString() ?? 'Participant';
    final before = _participants.length;
    _participants.removeWhere((p) => p.id == senderId);
    if (_participants.length < before) {
      addSystemMessage('$name left the room.');
      notifyListeners();
    }
  }

  // ─── Broadcast helpers ────────────────────────────────────────────────────

  void _sendOnChannel(RTCDataChannel dc, Map<String, dynamic> payload) {
    if (dc.state != RTCDataChannelState.RTCDataChannelOpen) return;
    try {
      dc.send(RTCDataChannelMessage(jsonEncode(payload)));
    } catch (e) {
      developer.log('DataChannel send error: $e', name: 'WT');
    }
  }

  void _broadcastAll(Map<String, dynamic> payload) {
    for (final slot in _guestSlots) {
      if (slot.dc != null) _sendOnChannel(slot.dc!, payload);
    }
  }

  void _broadcastExcept(Map<String, dynamic> payload, {required String exceptSlotId}) {
    for (final slot in _guestSlots) {
      if (slot.slotId != exceptSlotId && slot.dc != null) {
        _sendOnChannel(slot.dc!, payload);
      }
    }
  }

  void _sendPayload(Map<String, dynamic> payload) {
    if (isHost) {
      _broadcastAll(payload);
    } else {
      if (_guestDc != null) _sendOnChannel(_guestDc!, payload);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  void leaveRoom() {
    if (!isActive) return;
    _sendPayload({'type': 'LEAVE_ROOM', 'senderId': _myId, 'senderName': _myName});
    addSystemMessage('👋 You left the room.');
    _teardown();
    notifyListeners();
  }

  void updateLocalPlaybackState({
    required Duration position,
    required bool isPlaying,
    bool forceBroadcast = false,
  }) {
    _currentPosition = position;
    _isPlaying = isPlaying;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (isHost && isActive && (forceBroadcast || nowMs - _lastPosBroadcastMs > 2500)) {
      _lastPosBroadcastMs = nowMs;
      _sendPayload({
        'type': 'PLAYBACK_STATE',
        'senderId': _myId,
        'senderName': _myName,
        'positionSec': position.inMilliseconds / 1000.0,
        'isPlaying': isPlaying,
      });
    }
  }

  void notifyLocalBuffering(bool isBuffering) {
    if (!isActive) return;
    _sendPayload({
      'type': 'BUFFERING',
      'senderId': _myId,
      'senderName': _myName,
      'isBuffering': isBuffering,
    });
  }

  void updateHostMedia({
    required String streamUrl,
    required String title,
    required String movieId,
    int episodeNumber = 1,
    int? season,
    bool isMovie = true,
    Map<String, String>? headers,
    String? torrentHash,
  }) {
    if (!isActive || !isHost) return;
    _mediaPayload = WatchMediaPayload(
      title: title,
      movieId: movieId,
      videoUrl: streamUrl,
      headers: headers,
      torrentHash: torrentHash,
      episodeNumber: episodeNumber,
      season: season,
      isMovie: isMovie,
    );
    addSystemMessage('🎬 Sharing "$title" with the room...');
    _sendPayload({
      'type': 'MEDIA_UPDATE',
      'senderId': _myId,
      'senderName': _myName,
      'media': _mediaPayload!.toJson(),
      'positionSec': 0.0,
      'isPlaying': true,
    });
    // Also publish to ntfy as fallback
    publishStreamUrl();
    notifyListeners();
  }

  void sendChatMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !isActive) return;
    final chat = WatchChatMessage(
      id: Random().nextInt(9999999).toString(),
      senderId: _myId,
      senderName: _myName,
      text: trimmed,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _chatMessages.add(chat);
    notifyListeners();
    _sendPayload({...chat.toJson(), 'type': 'CHAT_MESSAGE'});
  }

  void sendEmojiReaction(String emoji) {
    if (!isActive) return;
    _reactionCtrl.add(WatchEmojiReaction(
      senderName: _myName,
      emoji: emoji,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    _sendPayload({
      'type': 'EMOJI_REACTION',
      'senderId': _myId,
      'senderName': _myName,
      'emoji': emoji,
    });
  }

  void addSystemMessage(String text) {
    _chatMessages.add(WatchChatMessage(
      id: Random().nextInt(9999999).toString(),
      senderId: 'system',
      senderName: 'System',
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSystemMessage: true,
    ));
    notifyListeners();
  }

  void setChatDrawerOpen(bool isOpen) {
    _isChatDrawerOpen = isOpen;
    if (isOpen) _unreadChatCount = 0;
    notifyListeners();
  }

  void setPlaybackSyncCallback(Function(Duration, bool) callback) {
    _onExternalPlaybackSync = callback;
  }

  void setMediaReceivedCallback(Function(WatchMediaPayload) callback) {
    _onMediaReceived = callback;
    if (_mediaPayload?.videoUrl != null) callback(_mediaPayload!);
  }

  void clearMediaReceivedCallback() => _onMediaReceived = null;

  // ─── Internals ─────────────────────────────────────────────────────────────

  void _setStatus(WTConnectionStatus status, String message) {
    _connectionStatus = status;
    _statusMessage = message;
  }

  void _applyPlaybackSync(Duration pos, bool playing) {
    _currentPosition = pos;
    _isPlaying = playing;
    _onExternalPlaybackSync?.call(pos, playing);
    notifyListeners();
  }

  void _addOrUpdateParticipant(String id, String name, {required bool isHost}) {
    if (id.isEmpty) return;
    final idx = _participants.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      _participants[idx].lastSeen = DateTime.now();
    } else {
      _participants.add(WatchParticipant(id: id, name: name, isHost: isHost));
      notifyListeners();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (isActive) {
        _sendPayload({
          'type': 'HEARTBEAT',
          'senderId': _myId,
          'senderName': _myName,
          'isHost': isHost,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  void _teardown() {
    _sseCancelled = true;
    _sseClient?.close(force: true);
    _sseClient = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _role = WTRole.none;
    _mediaPayload = null;
    _syncNotice = null;
    _currentPosition = Duration.zero;
    _isPlaying = false;
    _pendingAnswerCode = null;
    _statusMessage = '';
    _firstAnswerConsumed = false;

    _onMediaReceived = null;
    _onExternalPlaybackSync = null;

    for (final slot in _guestSlots) {
      try { slot.dc?.close(); } catch (_) {}
      try { slot.pc?.close(); } catch (_) {}
    }
    _guestSlots.clear();

    try { _hostInitialDc?.close(); } catch (_) {}
    _hostInitialDc = null;
    try { _hostInitialPc?.close(); } catch (_) {}
    _hostInitialPc = null;

    try { _guestDc?.close(); } catch (_) {}
    _guestDc = null;
    try { _guestPc?.close(); } catch (_) {}
    _guestPc = null;

    _connectionStatus = WTConnectionStatus.disconnected;
    _participants.clear();
    _chatMessages.clear();
    _unreadChatCount = 0;
    _isChatDrawerOpen = false;
  }

  // ─── Static helpers ─────────────────────────────────────────────────────

  static void playDirect(WatchMediaPayload media) {
    if (media.videoUrl == null || media.videoUrl!.isEmpty) return;
    PlayerState().startPlayback(
      streamUrl: media.videoUrl!,
      title: media.title,
      movieId: media.movieId,
      episodeNumber: media.episodeNumber,
      isMovie: media.isMovie,
      headers: media.headers,
      media: {
        'id': media.movieId,
        'stremioId': media.movieId,
        'title': media.title,
        'format': media.isMovie ? 'MOVIE' : 'SERIES',
      },
    );
  }

  static Future<void> resolveAndPlay(
      BuildContext context, WatchMediaPayload media) async {
    playDirect(media);
  }
}

// ─── Join Result Enum ─────────────────────────────────────────────────────

enum WTJoinResult {
  success,
  invalidCode,
  roomNotFound,
  invalidOffer,
  webrtcError,
  networkError,
  error,
}

extension WTJoinResultX on WTJoinResult {
  bool get isSuccess => this == WTJoinResult.success;
  String get userMessage {
    switch (this) {
      case WTJoinResult.success: return 'Connected!';
      case WTJoinResult.invalidCode: return 'Please enter a valid room code (4-6 digits).';
      case WTJoinResult.roomNotFound:
        return 'Room not found. Make sure the host has created the room and is online.';
      case WTJoinResult.invalidOffer:
        return 'Received an invalid offer from the room. Ask the host to restart.';
      case WTJoinResult.webrtcError:
        return 'WebRTC connection failed. Both devices need internet access.';
      case WTJoinResult.networkError:
        return 'Network error. Check your internet connection and try again.';
      case WTJoinResult.error:
        return 'An unexpected error occurred. Please try again.';
    }
  }
}
