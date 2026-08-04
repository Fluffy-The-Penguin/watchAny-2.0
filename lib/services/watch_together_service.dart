import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../state/player_state.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// WATCH TOGETHER — Pure WebRTC P2P with 6-Digit Auto-Signaling (No servers to manage)
//
//  HOW IT WORKS:
//    1. Host creates room → gets a 6-digit room code (e.g. 849201)
//    2. Host posts SDP offer to public pub/sub channel: ntfy.sh/watchany_wt_849201_offer
//    3. Guest enters 6-digit code '849201' → fetches SDP offer from ntfy.sh
//    4. Guest generates SDP answer → posts to ntfy.sh/watchany_wt_849201_answer
//    5. Host receives answer from ntfy.sh → WebRTC P2P DataChannel established ✅
//
//  After 1-second signaling handshake:
//  ALL playback sync, chat, emoji reactions run 100% P2P through WebRTC.
//  ntfy.sh is ONLY used for 1 second during initial room code lookup.
// ═══════════════════════════════════════════════════════════════════════════════

const List<Map<String, dynamic>> _kIceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
  {'urls': 'stun:stun2.l.google.com:19302'},
];

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

class GuestConnection {
  final String slotId;
  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  String? pendingOfferCode;
  WTConnectionStatus status;

  GuestConnection({required this.slotId})
      : status = WTConnectionStatus.generatingOffer;
}

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

class _SignalingBlob {
  final String type;
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

class WatchTogetherService extends ChangeNotifier {
  static final WatchTogetherService _instance =
      WatchTogetherService._internal();
  factory WatchTogetherService() => _instance;
  WatchTogetherService._internal();

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

  String? _pendingAnswerCode;
  String? get pendingAnswerCode => _pendingAnswerCode;

  final List<GuestConnection> _guestSlots = [];
  List<GuestConnection> get guestSlots => List.unmodifiable(_guestSlots);

  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  WatchMediaPayload? _mediaPayload;
  WatchMediaPayload? get mediaPayload => _mediaPayload;

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

  final StreamController<WatchEmojiReaction> _reactionCtrl =
      StreamController<WatchEmojiReaction>.broadcast();
  Stream<WatchEmojiReaction> get reactionStream => _reactionCtrl.stream;

  final StreamController<WatchChatMessage> _toastChatCtrl =
      StreamController<WatchChatMessage>.broadcast();
  Stream<WatchChatMessage> get toastChatStream => _toastChatCtrl.stream;

  RTCPeerConnection? _guestPc;
  RTCDataChannel? _guestDc;
  List<RTCIceCandidate> _guestCandidates = [];
  Completer<void>? _guestIceCompleter;

  Timer? _heartbeatTimer;
  Timer? _signalingPollTimer;
  int _lastPositionBroadcastMs = 0;
  Function(Duration position, bool isPlaying)? _onExternalPlaybackSync;
  Function(WatchMediaPayload media)? _onMediaReceived;

  static String generateRoomCode() =>
      (100000 + Random().nextInt(900000)).toString();

  static String generateId() => 'usr${Random().nextInt(89999) + 10000}';

  static String _slotId() => 'slot_${Random().nextInt(999999)}';

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO 6-DIGIT ROOM HOST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> createRoom({
    required String hostName,
    required WatchMediaPayload media,
  }) async {
    _teardown();
    _role = WTRole.host;
    _roomCode = generateRoomCode();
    _myId = generateId();
    _myName = hostName.trim().isNotEmpty ? hostName.trim() : 'Host';
    _mediaPayload = media;
    _participants.add(WatchParticipant(id: _myId, name: _myName, isHost: true));
    _setStatus(WTConnectionStatus.generatingOffer, 'Creating room $_roomCode...');
    notifyListeners();

    try {
      final slot = await addGuest();
      if (slot.pendingOfferCode != null) {
        // Publish host offer to public pub/sub for this 6-digit room code
        await _httpPost('https://ntfy.sh/watchany_wt_${_roomCode}_offer', slot.pendingOfferCode!);
        
        _setStatus(WTConnectionStatus.waitingForAnswer, 'Waiting for guest to join room $_roomCode...');
        notifyListeners();

        // Listen for guest answer on ntfy.sh
        _pollForAnswer(slot);
        return true;
      }
    } catch (e) {
      developer.log('createRoom error: $e', name: 'WT');
    }
    _setStatus(WTConnectionStatus.disconnected, 'Failed to create room.');
    notifyListeners();
    return false;
  }

  void _pollForAnswer(GuestConnection slot) {
    _signalingPollTimer?.cancel();
    _signalingPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_connectionStatus == WTConnectionStatus.connected || _role != WTRole.host) {
        timer.cancel();
        return;
      }
      try {
        final answerCode = await _httpGetLast('https://ntfy.sh/watchany_wt_${_roomCode}_answer');
        if (answerCode != null && answerCode.isNotEmpty) {
          timer.cancel();
          await completeGuestConnection(slot.slotId, answerCode);
        }
      } catch (e) {
        developer.log('Poll answer error: $e', name: 'WT');
      }
    });
  }

  void startHostSession({
    required String hostName,
    required WatchMediaPayload media,
  }) {
    createRoom(hostName: hostName, media: media);
  }

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

      final dc = await pc.createDataChannel(
        'watchSync',
        RTCDataChannelInit()
          ..ordered = true
          ..maxRetransmits = 3,
      );
      slot.dc = dc;
      _setupHostDataChannel(dc, slot);

      pc.onConnectionState = (s) {
        developer.log('Guest ${slot.slotId} state: $s', name: 'WT');
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          slot.status = WTConnectionStatus.connected;
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

      await Future.delayed(const Duration(milliseconds: 100));
      await iceCompleter.future.timeout(const Duration(seconds: 6), onTimeout: () {});

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

  Future<void> completeGuestConnection(String slotId, String answerCode) async {
    final GuestConnection slot = _guestSlots.firstWhere((s) => s.slotId == slotId,
        orElse: () => throw Exception('Slot not found'));

    try {
      final blob = _SignalingBlob.decode(answerCode);
      if (blob.type != 'answer') {
        throw Exception('Expected answer, got ${blob.type}');
      }

      await slot.pc!.setRemoteDescription(RTCSessionDescription(blob.sdp, 'answer'));
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
    dc.onMessage = (msg) => _onHostReceive(msg.text, fromSlot: slot);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO 6-DIGIT ROOM GUEST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> joinRoom({
    required String code,
    required String guestName,
  }) async {
    final cleanCode = code.trim();
    if (cleanCode.length < 4) return false;

    _setStatus(WTConnectionStatus.connecting, 'Looking for room $cleanCode...');
    notifyListeners();

    try {
      // 1. Fetch host offer from public topic
      final offerCode = await _httpGetLast('https://ntfy.sh/watchany_wt_${cleanCode}_offer');
      if (offerCode == null || offerCode.isEmpty) {
        _setStatus(WTConnectionStatus.disconnected, 'Room $cleanCode not found or expired.');
        notifyListeners();
        return false;
      }

      _roomCode = cleanCode;
      await joinWithOffer(offerCode: offerCode, guestName: guestName);

      if (_pendingAnswerCode != null) {
        // 2. Publish guest answer to public topic
        await _httpPost('https://ntfy.sh/watchany_wt_${cleanCode}_answer', _pendingAnswerCode!);
        return true;
      }
    } catch (e) {
      developer.log('joinRoom error: $e', name: 'WT');
    }

    _setStatus(WTConnectionStatus.disconnected, 'Could not join room $cleanCode.');
    notifyListeners();
    return false;
  }

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
    _statusMessage = 'Connecting to room...';
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

      await _guestPc!.setRemoteDescription(RTCSessionDescription(blob.sdp, 'offer'));
      for (final c in blob.candidates) {
        await _guestPc!.addCandidate(RTCIceCandidate(
          c['candidate']?.toString(),
          c['sdpMid']?.toString(),
          (c['sdpMLineIndex'] as num?)?.toInt(),
        ));
      }

      final answer = await _guestPc!.createAnswer();
      await _guestPc!.setLocalDescription(answer);

      await Future.delayed(const Duration(milliseconds: 100));
      await _guestIceCompleter!.future.timeout(const Duration(seconds: 6), onTimeout: () {});

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
      _statusMessage = 'Connecting P2P...';
      notifyListeners();
    } catch (e) {
      developer.log('joinWithOffer error: $e', name: 'WT');
      _connectionStatus = WTConnectionStatus.disconnected;
      _statusMessage = '❌ Connection failed: $e';
      notifyListeners();
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

  // ═══════════════════════════════════════════════════════════════════════════
  // HTTP SIGNALING HELPERS (ntfy.sh pub/sub)
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _httpPost(String url, String bodyText) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.write(bodyText);
      final res = await req.close();
      await res.drain();
    } catch (e) {
      developer.log('_httpPost error: $e', name: 'WT');
    } finally {
      client.close();
    }
  }

  static Future<String?> _httpGetLast(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$url/json?poll=1'));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final lines = body.trim().split('\n');
        for (final line in lines.reversed) {
          if (line.trim().isEmpty) continue;
          final json = jsonDecode(line.trim());
          if (json is Map && json['message'] != null) {
            final msg = json['message'].toString();
            if (msg.isNotEmpty && !msg.contains('v=0')) {
              return msg;
            }
          }
        }
      }
    } catch (e) {
      developer.log('_httpGetLast error: $e', name: 'WT');
    } finally {
      client.close();
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HOST / GUEST RECEIVE & BROADCAST
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

  void _broadcastExcept(Map<String, dynamic> payload,
      {required String exceptSlotId}) {
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
    _signalingPollTimer?.cancel();
    _signalingPollTimer = null;

    _onMediaReceived = null;
    _onExternalPlaybackSync = null;

    for (final slot in _guestSlots) {
      try { slot.dc?.close(); } catch (_) {}
      try { slot.pc?.close(); } catch (_) {}
    }
    _guestSlots.clear();

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
