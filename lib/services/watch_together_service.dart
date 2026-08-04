import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../state/player_state.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// WATCH TOGETHER — Pure WebRTC P2P, no servers, no tunnels, no accounts.
//
//  MULTI-GUEST (star topology):
//    Host ←──── DataChannel ────► Guest 1
//    Host ←──── DataChannel ────► Guest 2
//    Host ←──── DataChannel ────► Guest 3  (up to ~8 guests practical)
//
//  HOST creates a NEW offer code for EACH guest.
//  Guest messages arrive at host → host re-broadcasts to all other guests.
//
//  HOW TO ADD A GUEST:
//    Host taps "Add Guest" → new offer code generated
//    Guest pastes offer → sends back answer code
//    Host pastes answer → P2P DataChannel established for that guest
//    Repeat for each additional guest.
// ═══════════════════════════════════════════════════════════════════════════════

const List<Map<String, dynamic>> _kIceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
  {'urls': 'stun:stun2.l.google.com:19302'},
];

// ─── Enums ────────────────────────────────────────────────────────────────────

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

// ─── Per-Guest Connection (host side) ────────────────────────────────────────

class GuestConnection {
  final String slotId;          // unique ID for this offer slot
  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  String? pendingOfferCode;     // show to user → they paste to guest
  WTConnectionStatus status;

  GuestConnection({required this.slotId})
      : status = WTConnectionStatus.generatingOffer;
}

// ─── Data Models ─────────────────────────────────────────────────────────────

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

  WatchEmojiReaction({
    required this.senderName,
    required this.emoji,
    required this.timestamp,
  });
}

// ─── Signaling Blob (the "code" exchanged manually) ──────────────────────────

class _SignalingBlob {
  final String type; // 'offer' or 'answer'
  final String sdp;
  final List<Map<String, dynamic>> candidates;

  _SignalingBlob({
    required this.type,
    required this.sdp,
    required this.candidates,
  });

  String encode() {
    final json = jsonEncode({'t': type, 's': sdp, 'c': candidates});
    return base64Url.encode(utf8.encode(json));
  }

  static _SignalingBlob decode(String code) {
    final json = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(code.trim()))))
        as Map<String, dynamic>;
    return _SignalingBlob(
      type: json['t']?.toString() ?? 'offer',
      sdp: json['s']?.toString() ?? '',
      candidates: (json['c'] as List?)
              ?.map((c) => Map<String, dynamic>.from(c as Map))
              .toList() ??
          [],
    );
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class WatchTogetherService extends ChangeNotifier {
  static final WatchTogetherService _instance =
      WatchTogetherService._internal();
  factory WatchTogetherService() => _instance;
  WatchTogetherService._internal();

  // ── Public State ─────────────────────────────────────────────────────────────

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

  String _roomCode = '';
  String get roomCode => _roomCode;

  /// Guest-side: the answer code to send back to the host.
  String? _pendingAnswerCode;
  String? get pendingAnswerCode => _pendingAnswerCode;

  /// Host-side: list of active guest slots (each has its own offer/answer).
  final List<GuestConnection> _guestSlots = [];
  List<GuestConnection> get guestSlots =>
      List.unmodifiable(_guestSlots);

  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  WatchMediaPayload? _mediaPayload;
  WatchMediaPayload? get mediaPayload => _mediaPayload;

  final List<WatchParticipant> _participants = [];
  List<WatchParticipant> get participants =>
      List.unmodifiable(_participants);

  final List<WatchChatMessage> _chatMessages = [];
  List<WatchChatMessage> get chatMessages =>
      List.unmodifiable(_chatMessages);

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

  // ── Streams ──────────────────────────────────────────────────────────────────

  final StreamController<WatchEmojiReaction> _reactionCtrl =
      StreamController<WatchEmojiReaction>.broadcast();
  Stream<WatchEmojiReaction> get reactionStream => _reactionCtrl.stream;

  final StreamController<WatchChatMessage> _toastChatCtrl =
      StreamController<WatchChatMessage>.broadcast();
  Stream<WatchChatMessage> get toastChatStream => _toastChatCtrl.stream;

  // ── Guest-side WebRTC (single PC for the guest) ───────────────────────────
  RTCPeerConnection? _guestPc;
  RTCDataChannel? _guestDc;
  List<RTCIceCandidate> _guestCandidates = [];
  Completer<void>? _guestIceCompleter;

  // ── Misc ──────────────────────────────────────────────────────────────────
  Timer? _heartbeatTimer;
  int _lastPositionBroadcastMs = 0;
  Function(Duration position, bool isPlaying)? _onExternalPlaybackSync;
  Function(WatchMediaPayload media)? _onMediaReceived;

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String generateRoomCode() =>
      (100000 + Random().nextInt(900000)).toString();

  static String generateId() =>
      'usr${Random().nextInt(89999) + 10000}';

  static String _slotId() =>
      'slot_${Random().nextInt(999999)}';

  // ═══════════════════════════════════════════════════════════════════════════
  // HOST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  /// Step 0 (Host): Start the session. Call once when creating a room.
  void startHostSession({
    required String hostName,
    required WatchMediaPayload media,
  }) {
    _teardown();
    _role = WTRole.host;
    _roomCode = generateRoomCode();
    _myId = generateId();
    _myName = hostName.trim().isNotEmpty ? hostName.trim() : 'Host';
    _mediaPayload = media;
    _participants.add(WatchParticipant(id: _myId, name: _myName, isHost: true));
    _connectionStatus = WTConnectionStatus.waitingForAnswer;
    _statusMessage = 'Session ready. Tap "Add Guest" to invite someone.';
    notifyListeners();
  }

  /// Step 1 (Host): Generate a new offer code for ONE guest.
  /// Returns a [_GuestConnection] whose [pendingOfferCode] you show to the user.
  Future<GuestConnection> addGuest() async {
    assert(_role == WTRole.host, 'Only host can add guests');

    final slot = GuestConnection(slotId: _slotId());
    _guestSlots.add(slot);
    notifyListeners();

    try {
      final candidates = <RTCIceCandidate>[];
      final iceCompleter = Completer<void>();

      final pc = await createPeerConnection({
        'iceServers': _kIceServers,
        'sdpSemantics': 'unified-plan',
      });
      slot.pc = pc;

      pc.onIceCandidate = (c) {
        if (c.candidate != null && c.candidate!.isNotEmpty) {
          candidates.add(c);
        }
      };
      pc.onIceGatheringState = (s) {
        if (s == RTCIceGatheringState.RTCIceGatheringStateComplete) {
          if (!iceCompleter.isCompleted) iceCompleter.complete();
        }
      };

      // Host creates the DataChannel
      final dc = await pc.createDataChannel(
        'watchSync',
        RTCDataChannelInit()
          ..ordered = true
          ..maxRetransmits = 3,
      );
      slot.dc = dc;
      _setupHostDataChannel(dc, slot);

      pc.onConnectionState = (s) {
        developer.log(
            'Guest ${slot.slotId} connection state: $s', name: 'WT');
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          slot.status = WTConnectionStatus.connected;
          // If at least one guest is connected, we're "connected"
          _connectionStatus = WTConnectionStatus.connected;
          _startHeartbeat();
          notifyListeners();
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          slot.status = WTConnectionStatus.disconnected;
          addSystemMessage('⚠️ A guest disconnected.');
          notifyListeners();
        }
      };

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // Wait for ICE (up to 6s)
      await Future.delayed(const Duration(milliseconds: 100));
      await iceCompleter.future.timeout(const Duration(seconds: 6),
          onTimeout: () {});

      final blob = _SignalingBlob(
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

      slot.pendingOfferCode = blob.encode();
      slot.status = WTConnectionStatus.waitingForAnswer;
      notifyListeners();
    } catch (e) {
      developer.log('addGuest error: $e', name: 'WT');
      slot.status = WTConnectionStatus.disconnected;
      notifyListeners();
    }

    return slot;
  }

  /// Step 2 (Host): Paste the guest's Answer Code for a specific slot.
  Future<void> completeGuestConnection(String slotId, String answerCode) async {
    final GuestConnection slot = _guestSlots.firstWhere((s) => s.slotId == slotId,
        orElse: () => throw Exception('Slot not found'));

    try {
      final blob = _SignalingBlob.decode(answerCode);
      if (blob.type != 'answer') {
        throw Exception('Expected answer, got ${blob.type}');
      }

      await slot.pc!
          .setRemoteDescription(RTCSessionDescription(blob.sdp, 'answer'));
      for (final c in blob.candidates) {
        await slot.pc!.addCandidate(RTCIceCandidate(
          c['candidate']?.toString(),
          c['sdpMid']?.toString(),
          (c['sdpMLineIndex'] as num?)?.toInt(),
        ));
      }
      slot.status = WTConnectionStatus.connecting;
      notifyListeners();
    } catch (e) {
      developer.log('completeGuestConnection error: $e', name: 'WT');
      rethrow;
    }
  }

  void _setupHostDataChannel(RTCDataChannel dc, GuestConnection slot) {
    dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        // Announce ourselves and send current room state
        _sendOnChannel(dc, {
          'type': 'ROOM_STATE',
          'senderId': _myId,
          'senderName': _myName,
          'media': _mediaPayload?.toJson(),
          'positionSec': _currentPosition.inMilliseconds / 1000.0,
          'isPlaying': _isPlaying,
          'participants': _participants.map((p) => p.toJson()).toList(),
        });
      }
    };

    dc.onMessage = (msg) {
      _onHostReceive(msg.text, fromSlot: slot);
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUEST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  /// Guest: paste the host's Offer Code → generates Answer Code.
  Future<void> joinWithOffer({
    required String offerCode,
    required String guestName,
  }) async {
    _teardown();
    _role = WTRole.guest;
    _myId = generateId();
    _myName = guestName.trim().isNotEmpty ? guestName.trim() : 'Guest';
    _participants.add(WatchParticipant(id: _myId, name: _myName, isHost: false));
    _connectionStatus = WTConnectionStatus.generatingAnswer;
    _statusMessage = '🔧 Processing offer...';
    notifyListeners();

    try {
      final blob = _SignalingBlob.decode(offerCode);
      if (blob.type != 'offer') {
        throw Exception('Expected offer, got ${blob.type}');
      }

      _guestCandidates = [];
      _guestIceCompleter = Completer<void>();

      _guestPc = await createPeerConnection({
        'iceServers': _kIceServers,
        'sdpSemantics': 'unified-plan',
      });

      _guestPc!.onIceCandidate = (c) {
        if (c.candidate != null && c.candidate!.isNotEmpty) {
          _guestCandidates.add(c);
        }
      };
      _guestPc!.onIceGatheringState = (s) {
        if (s == RTCIceGatheringState.RTCIceGatheringStateComplete) {
          if (!(_guestIceCompleter?.isCompleted ?? true)) {
            _guestIceCompleter!.complete();
          }
        }
      };
      _guestPc!.onConnectionState = (s) {
        developer.log('Guest PC state: $s', name: 'WT');
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _connectionStatus = WTConnectionStatus.connected;
          _statusMessage = '✅ Connected!';
          _pendingAnswerCode = null;
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

      // Apply host offer + ICE
      await _guestPc!.setRemoteDescription(
          RTCSessionDescription(blob.sdp, 'offer'));
      for (final c in blob.candidates) {
        await _guestPc!.addCandidate(RTCIceCandidate(
          c['candidate']?.toString(),
          c['sdpMid']?.toString(),
          (c['sdpMLineIndex'] as num?)?.toInt(),
        ));
      }

      // Generate answer
      final answer = await _guestPc!.createAnswer();
      await _guestPc!.setLocalDescription(answer);

      // Wait for ICE
      await Future.delayed(const Duration(milliseconds: 100));
      await _guestIceCompleter!.future
          .timeout(const Duration(seconds: 6), onTimeout: () {});

      final answerBlob = _SignalingBlob(
        type: 'answer',
        sdp: answer.sdp ?? '',
        candidates: _guestCandidates
            .map((c) => {
                  'candidate': c.candidate,
                  'sdpMid': c.sdpMid,
                  'sdpMLineIndex': c.sdpMLineIndex,
                })
            .toList(),
      );

      _pendingAnswerCode = answerBlob.encode();
      _connectionStatus = WTConnectionStatus.connecting;
      _statusMessage =
          '📋 Send your answer code to the host.\nConnection completes automatically.';
      notifyListeners();
    } catch (e) {
      developer.log('joinWithOffer error: $e', name: 'WT');
      _connectionStatus = WTConnectionStatus.disconnected;
      _statusMessage = '❌ Invalid offer code: $e';
      notifyListeners();
    }
  }

  void _setupGuestDataChannel(RTCDataChannel dc) {
    dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        // Announce ourselves to host
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

  // ═══════════════════════════════════════════════════════════════════════════
  // HOST MESSAGE HANDLING
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
          // Re-broadcast JOIN to all OTHER guests so they know someone joined
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
          // Unknown message — just re-broadcast
          _broadcastExcept(msg, exceptSlotId: fromSlot.slotId);
      }
    } catch (e) {
      developer.log('Host receive error: $e', name: 'WT');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUEST MESSAGE HANDLING
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

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED MESSAGE HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

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
          final p = WatchParticipant.fromJson(
              Map<String, dynamic>.from(item));
          if (p.id != _myId) {
            _addOrUpdateParticipant(p.id, p.name, isHost: p.isHost);
          }
        }
      }
    }

    if (msg['media'] is Map) {
      _mediaPayload = WatchMediaPayload.fromJson(
          Map<String, dynamic>.from(msg['media'] as Map));
      addSystemMessage('🎬 Host is watching: ${_mediaPayload!.title}');
      _onMediaReceived?.call(_mediaPayload!);
    } else {
      addSystemMessage('⌛ Connected! Waiting for host to pick something.');
    }

    final pos = (msg['positionSec'] as num?)?.toDouble() ?? 0.0;
    if (pos > 0) {
      _applyPlaybackSync(
          Duration(milliseconds: (pos * 1000).round()),
          msg['isPlaying'] == true);
    }

    notifyListeners();
  }

  void _handleMediaUpdate(Map<String, dynamic> msg) {
    if (isHost) return;
    if (msg['media'] is Map) {
      _mediaPayload = WatchMediaPayload.fromJson(
          Map<String, dynamic>.from(msg['media'] as Map));
      addSystemMessage('🎬 Host started: ${_mediaPayload!.title}');
      _onMediaReceived?.call(_mediaPayload!);
    }
    final pos = (msg['positionSec'] as num?)?.toDouble() ?? 0.0;
    _applyPlaybackSync(
        Duration(milliseconds: (pos * 1000).round()),
        msg['isPlaying'] == true);
  }

  void _handlePlaybackState(Map<String, dynamic> msg) {
    final pos = (msg['positionSec'] as num?)?.toDouble() ?? 0.0;
    final playing = msg['isPlaying'] == true;
    _syncNotice = playing ? null : '⏸ ${msg['senderName']} paused';
    _applyPlaybackSync(
        Duration(milliseconds: (pos * 1000).round()), playing);
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

  // ═══════════════════════════════════════════════════════════════════════════
  // SENDING
  // ═══════════════════════════════════════════════════════════════════════════

  void _sendOnChannel(RTCDataChannel dc, Map<String, dynamic> payload) {
    if (dc.state != RTCDataChannelState.RTCDataChannelOpen) return;
    try {
      dc.send(RTCDataChannelMessage(jsonEncode(payload)));
    } catch (e) {
      developer.log('DataChannel send error: $e', name: 'WT');
    }
  }

  /// Host: broadcast to ALL connected guests (used for host-originated messages).
  void _broadcastAll(Map<String, dynamic> payload) {
    for (final slot in _guestSlots) {
      if (slot.dc != null) _sendOnChannel(slot.dc!, payload);
    }
  }

  /// Host: broadcast to all guests EXCEPT one slot (relay from another guest).
  void _broadcastExcept(Map<String, dynamic> payload,
      {required String exceptSlotId}) {
    for (final slot in _guestSlots) {
      if (slot.slotId != exceptSlotId && slot.dc != null) {
        _sendOnChannel(slot.dc!, payload);
      }
    }
  }

  /// Send from THIS peer: host broadcasts to all, guest sends to host.
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
    _sendPayload({
      'type': 'LEAVE_ROOM',
      'senderId': _myId,
      'senderName': _myName,
    });
    addSystemMessage('👋 Left the Watch Together session.');
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
    if (isHost &&
        isActive &&
        (forceBroadcast || nowMs - _lastPositionBroadcastMs > 2500)) {
      _lastPositionBroadcastMs = nowMs;
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

  void setPlaybackSyncCallback(
      Function(Duration position, bool isPlaying) callback) {
    _onExternalPlaybackSync = callback;
  }

  void setMediaReceivedCallback(Function(WatchMediaPayload media) callback) {
    _onMediaReceived = callback;
    if (_mediaPayload?.videoUrl != null) callback(_mediaPayload!);
  }

  void clearMediaReceivedCallback() => _onMediaReceived = null;

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNALS
  // ═══════════════════════════════════════════════════════════════════════════

  void _applyPlaybackSync(Duration pos, bool playing) {
    _currentPosition = pos;
    _isPlaying = playing;
    _onExternalPlaybackSync?.call(pos, playing);
    notifyListeners();
  }

  void _addOrUpdateParticipant(String id, String name,
      {required bool isHost}) {
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
    _role = WTRole.none;
    _mediaPayload = null;
    _syncNotice = null;
    _currentPosition = Duration.zero;
    _isPlaying = false;
    _pendingAnswerCode = null;
    _statusMessage = '';

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _onMediaReceived = null;
    _onExternalPlaybackSync = null;

    // Close all host guest slots
    for (final slot in _guestSlots) {
      try { slot.dc?.close(); } catch (_) {}
      try { slot.pc?.close(); } catch (_) {}
    }
    _guestSlots.clear();

    // Close guest-side PC
    if (!(_guestIceCompleter?.isCompleted ?? true)) {
      _guestIceCompleter!.complete();
    }
    _guestIceCompleter = null;
    _guestCandidates = [];
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

  // ═══════════════════════════════════════════════════════════════════════════
  // STATIC: Play helper (direct URL only — page handles addon resolution)
  // ═══════════════════════════════════════════════════════════════════════════

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
