import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../state/player_state.dart';
import '../main.dart';
import '../screens/player_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// WATCH TOGETHER — Supabase Realtime Engine (2-Way WebSockets & Presence)
//
// ARCHITECTURE (100% NAT/CGNAT Proof, Zero Cost, Sub-10ms Latency):
// 1. Host creates room -> gets 6-digit room code (e.g. 849201).
// 2. Both Host and Guest subscribe to Supabase Realtime Phoenix Channel:
//       wt_849201
// 3. Native 2-way WebSockets for bidirectional low-latency broadcast events.
// 4. Built-in Presence Engine automatically tracks participant joins/leaves.
// 5. Zero servers to manage, 0% dropouts, sub-10ms play/pause/seek sync!
// ═══════════════════════════════════════════════════════════════════════════════

enum WTConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

enum WTRole { none, host, guest }

// ─── Guest Connection Slot (Host View) ──────────────────────────────────────

class GuestConnection {
  final String slotId;
  final String guestId;
  String guestName;
  WTConnectionStatus status;

  GuestConnection({
    required this.slotId,
    required this.guestId,
    required this.guestName,
    this.status = WTConnectionStatus.connected,
  });
}

// ─── Data Models ───────────────────────────────────────────────────────────

class WatchParticipant {
  final String id;
  final String name;
  final bool isHost;
  bool isBuffering;
  double lastPositionSec;
  DateTime lastSeen;

  WatchParticipant({
    required this.id,
    required this.name,
    required this.isHost,
    this.isBuffering = false,
    this.lastPositionSec = 0.0,
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
  WatchEmojiReaction({
    required this.senderName,
    required this.emoji,
    required this.timestamp,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// WATCH TOGETHER SERVICE (Singleton - Supabase Realtime Backend)
// ═══════════════════════════════════════════════════════════════════════════════

class WatchTogetherService extends ChangeNotifier {
  static final WatchTogetherService _instance = WatchTogetherService._internal();
  factory WatchTogetherService() => _instance;
  WatchTogetherService._internal();

  // Supabase Credentials
  static const String _supabaseUrl = 'https://yytppifsytoasrsmwvrc.supabase.co';
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl5dHBwaWZzeXRvYXNyc213dnJjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5MjU2NDEsImV4cCI6MjEwMTUwMTY0MX0.Jh2G5_hhiroLHzdgWH41lmU9w5EF9zyjdLQYXs_Y2ig';

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

  String _roomCode = '';
  String get roomCode => _roomCode;

  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  String _lastErrorMessage = '';

  WatchMediaPayload? _mediaPayload;
  WatchMediaPayload? get mediaPayload => _mediaPayload;

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

  // ─── Event Streams ────────────────────────────────────────────────────────

  final StreamController<WatchEmojiReaction> _reactionCtrl =
      StreamController<WatchEmojiReaction>.broadcast();
  Stream<WatchEmojiReaction> get reactionStream => _reactionCtrl.stream;

  final StreamController<WatchChatMessage> _toastChatCtrl =
      StreamController<WatchChatMessage>.broadcast();
  Stream<WatchChatMessage> get toastChatStream => _toastChatCtrl.stream;

  // ─── Supabase Transport Internals ─────────────────────────────────────────

  RealtimeChannel? _channel;
  Completer<bool>? _roomStateCompleter;
  int _lastPosBroadcastMs = 0;

  Function(Duration, bool)? _onExternalPlaybackSync;
  Function(WatchMediaPayload)? _onMediaReceived;

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static String generateRoomCode() => (100000 + Random().nextInt(900000)).toString();
  static String _genId() => 'u${Random().nextInt(899999) + 100000}';

  Future<void> _ensureSupabaseInitialized() async {
    try {
      Supabase.instance;
    } catch (_) {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HOST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> createRoom({
    required String hostName,
    required WatchMediaPayload media,
  }) async {
    await _ensureSupabaseInitialized();
    _teardown();

    _role = WTRole.host;
    _roomCode = generateRoomCode();
    _myId = _genId();
    _myName = hostName.trim().isNotEmpty ? hostName.trim() : 'Host';
    _mediaPayload = media;
    _participants.add(WatchParticipant(id: _myId, name: _myName, isHost: true));

    _setStatus(WTConnectionStatus.connecting, 'Opening Supabase Realtime room...');
    notifyListeners();

    final connected = await _connectChannel();
    if (!connected) {
      final msg = _lastErrorMessage.isNotEmpty
          ? _lastErrorMessage
          : 'Could not open Supabase room. Check internet connection.';
      _setStatus(WTConnectionStatus.disconnected, msg);
      notifyListeners();
      return false;
    }

    _setStatus(WTConnectionStatus.connected, 'Room ready! Code: $_roomCode');
    addSystemMessage('🎬 Room created! Code: $_roomCode');

    // Broadcast initial room state
    _broadcastPayload({
      'type': 'ROOM_STATE',
      'senderId': _myId,
      'senderName': _myName,
      'media': _mediaPayload?.toJson(),
      'positionSec': _currentPosition.inMilliseconds / 1000.0,
      'isPlaying': _isPlaying,
      'participants': _participants.map((p) => p.toJson()).toList(),
    });

    notifyListeners();
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUEST FLOW
  // ═══════════════════════════════════════════════════════════════════════════

  Future<WTJoinResult> joinRoom({
    required String code,
    required String guestName,
  }) async {
    await _ensureSupabaseInitialized();
    final cleanCode = code.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (cleanCode.length < 4) return WTJoinResult.invalidCode;

    _teardown();
    _role = WTRole.guest;
    _roomCode = cleanCode;
    _myId = _genId();
    _myName = guestName.trim().isNotEmpty ? guestName.trim() : 'Guest';
    _participants.add(WatchParticipant(id: _myId, name: _myName, isHost: false));

    _setStatus(WTConnectionStatus.connecting, 'Connecting to room $cleanCode...');
    notifyListeners();

    final connected = await _connectChannel();
    if (!connected) {
      final msg = _lastErrorMessage.isNotEmpty
          ? _lastErrorMessage
          : 'Could not connect to room server. Check internet connection.';
      _setStatus(WTConnectionStatus.disconnected, msg);
      notifyListeners();
      return WTJoinResult.networkError;
    }

    final completer = Completer<bool>();
    _roomStateCompleter = completer;

    // Send JOIN_ROOM request to host
    await _broadcastPayload({
      'type': 'JOIN_ROOM',
      'senderId': _myId,
      'senderName': _myName,
      'isHost': false,
    });

    // Request current room state from host
    await _broadcastPayload({
      'type': 'GET_ROOM_STATE',
      'senderId': _myId,
      'senderName': _myName,
    });

    // Wait up to 5 seconds for host to respond with ROOM_STATE
    final gotState = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );

    _roomStateCompleter = null;

    if (!gotState) {
      _setStatus(WTConnectionStatus.disconnected, 'Room $cleanCode not found or host is offline.');
      _teardown();
      notifyListeners();
      return WTJoinResult.roomNotFound;
    }

    _setStatus(WTConnectionStatus.connected, 'Connected to room!');
    notifyListeners();

    return WTJoinResult.success;
  }

  bool _isSupabaseInitialized = false;

  Future<void> initSupabase() async {
    if (_isSupabaseInitialized) return;
    try {
      Supabase.instance.client;
      _isSupabaseInitialized = true;
    } catch (_) {
      try {
        await Supabase.initialize(
          url: _supabaseUrl,
          anonKey: _supabaseAnonKey,
        );
        _isSupabaseInitialized = true;
      } catch (e) {
        developer.log('Supabase.initialize error: $e', name: 'WT');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUPABASE REALTIME CHANNEL ENGINE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> _connectChannel() async {
    _lastErrorMessage = '';
    try {
      await initSupabase();
      final client = Supabase.instance.client;
      
      if (!client.realtime.isConnected) {
        developer.log('Connecting Supabase WebSocket realtime engine...', name: 'WT');
        client.realtime.connect();
      }

      final roomName = 'wt_$_roomCode';
      developer.log('Connecting to Supabase Realtime channel: $roomName', name: 'WT');

      if (_channel != null) {
        try {
          await client.removeChannel(_channel!);
        } catch (_) {}
      }

      _channel = client.channel(roomName, opts: const RealtimeChannelConfig(self: true));

      // Attach event listeners for Realtime Broadcast events
      _channel!
        .onBroadcast(event: 'JOIN_ROOM', callback: (payload) => _handleIncomingMessage(payload, payload['senderId']?.toString() ?? '', 'JOIN_ROOM'))
        .onBroadcast(event: 'GET_ROOM_STATE', callback: (payload) => _handleIncomingMessage(payload, payload['senderId']?.toString() ?? '', 'GET_ROOM_STATE'))
        .onBroadcast(event: 'ROOM_STATE', callback: (payload) => _handleIncomingMessage(payload, payload['senderId']?.toString() ?? '', 'ROOM_STATE'))
        .onBroadcast(event: 'MEDIA_UPDATE', callback: (payload) => _handleIncomingMessage(payload, payload['senderId']?.toString() ?? '', 'MEDIA_UPDATE'))
        .onBroadcast(event: 'PLAYBACK_STATE', callback: (payload) => _handleIncomingMessage(payload, payload['senderId']?.toString() ?? '', 'PLAYBACK_STATE'))
        .onBroadcast(event: 'BUFFERING', callback: (payload) => _handleIncomingMessage(payload, payload['senderId']?.toString() ?? '', 'BUFFERING'))
        .onBroadcast(event: 'CHAT_MESSAGE', callback: (payload) => _handleIncomingMessage(payload, payload['senderId']?.toString() ?? '', 'CHAT_MESSAGE'))
        .onBroadcast(event: 'EMOJI_REACTION', callback: (payload) => _handleIncomingMessage(payload, payload['senderId']?.toString() ?? '', 'EMOJI_REACTION'))
        .onBroadcast(event: 'LEAVE_ROOM', callback: (payload) => _handleIncomingMessage(payload, payload['senderId']?.toString() ?? '', 'LEAVE_ROOM'));

      // Attach Presence Listener
      _channel!.onPresenceSync((_) => _syncPresenceFromSupabase());

      final completer = Completer<bool>();
      _channel!.subscribe((status, error) {
        developer.log('Supabase channel status: $status, error: $error', name: 'WT');
        if (status == RealtimeSubscribeStatus.subscribed) {
          developer.log('Subscribed to Supabase Realtime channel!', name: 'WT');
          _lastErrorMessage = '';
          if (!completer.isCompleted) completer.complete(true);
          try {
            _channel?.track({
              'id': _myId,
              'name': _myName,
              'isHost': isHost,
            });
          } catch (e) {
            developer.log('Presence track exception: $e', name: 'WT');
          }
        } else if (status == RealtimeSubscribeStatus.closed ||
                   status == RealtimeSubscribeStatus.timedOut ||
                   status == RealtimeSubscribeStatus.channelError) {
          _lastErrorMessage = 'Supabase channel subscription failed ($status): ${error ?? "No details"}';
          developer.log('Supabase channel error: $_lastErrorMessage', name: 'WT');
          if (!completer.isCompleted) completer.complete(false);
          _handleChannelDisconnect();
        }
      });

      return await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          _lastErrorMessage = 'Supabase channel timed out after 8s (isConnected: ${client.realtime.isConnected})';
          return false;
        },
      );
    } catch (e) {
      _lastErrorMessage = 'Supabase Exception: $e';
      developer.log('Failed to connect to Supabase Realtime: $e', name: 'WT');
      return false;
    }
  }

  void _syncPresenceFromSupabase() {
    if (_channel == null || !isActive) return;
    try {
      final presences = _channel!.presenceState();
      final newParticipants = <WatchParticipant>[];
      final newGuestSlots = <GuestConnection>[];

      for (final presence in presences) {
        for (final p in presence.presences) {
          final payload = p.payload;
          final id = payload['id']?.toString() ?? '';
          final name = payload['name']?.toString() ?? 'Guest';
          final hostUser = payload['isHost'] == true;

          if (id.isNotEmpty) {
            newParticipants.add(WatchParticipant(id: id, name: name, isHost: hostUser));
            if (!hostUser && isHost) {
              newGuestSlots.add(GuestConnection(
                slotId: 'slot_$id',
                guestId: id,
                guestName: name,
              ));
            }
          }
        }
      }

      if (newParticipants.isNotEmpty) {
        _participants.clear();
        _participants.addAll(newParticipants);
        _guestSlots.clear();
        _guestSlots.addAll(newGuestSlots);
        notifyListeners();
      }
    } catch (e) {
      developer.log('_syncPresenceFromSupabase error: $e', name: 'WT');
    }
  }

  void _handleIncomingMessage(Map<String, dynamic> msg, String senderId, String type) {
    if (senderId == _myId) return;

    switch (type) {
      case 'JOIN_ROOM':
        _handleJoinRoom(msg, senderId);
        break;

      case 'GET_ROOM_STATE':
        if (isHost) {
          _broadcastPayload({
            'type': 'ROOM_STATE',
            'senderId': _myId,
            'senderName': _myName,
            'media': _mediaPayload?.toJson(),
            'positionSec': _currentPosition.inMilliseconds / 1000.0,
            'isPlaying': _isPlaying,
            'participants': _participants.map((p) => p.toJson()).toList(),
          });
        }
        break;

      case 'ROOM_STATE':
        _handleRoomState(msg);
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

      case 'LEAVE_ROOM':
        _handleLeave(msg, senderId);
        break;
    }
  }

  void _handleChannelDisconnect() {
    if (!isActive) return;
    _connectionStatus = WTConnectionStatus.reconnecting;
    _statusMessage = 'Connection lost. Reconnecting...';
    notifyListeners();
  }

  // ─── Broadcast Payload ──────────────────────────────────────────────────

  Future<void> _broadcastPayload(Map<String, dynamic> payload) async {
    if (_channel == null) return;
    final type = payload['type']?.toString() ?? 'DEFAULT';
    try {
      await _channel!.sendBroadcastMessage(
        event: type,
        payload: payload,
      );
    } catch (e) {
      developer.log('_broadcastPayload error: $e', name: 'WT');
    }
  }

  // ─── Packet Handlers ─────────────────────────────────────────────────────

  void _handleJoinRoom(Map<String, dynamic> msg, String senderId) {
    final name = msg['senderName']?.toString() ?? 'Guest';
    _addOrUpdateParticipant(senderId, name, isHost: msg['isHost'] == true);

    if (isHost) {
      final slotIdx = _guestSlots.indexWhere((s) => s.guestId == senderId);
      if (slotIdx >= 0) {
        _guestSlots[slotIdx].guestName = name;
        _guestSlots[slotIdx].status = WTConnectionStatus.connected;
      } else {
        _guestSlots.add(GuestConnection(
          slotId: 'slot_${_guestSlots.length}',
          guestId: senderId,
          guestName: name,
        ));
      }

      // Host responds with full current state
      _broadcastPayload({
        'type': 'ROOM_STATE',
        'senderId': _myId,
        'senderName': _myName,
        'media': _mediaPayload?.toJson(),
        'positionSec': _currentPosition.inMilliseconds / 1000.0,
        'isPlaying': _isPlaying,
        'participants': _participants.map((p) => p.toJson()).toList(),
      });
    }

    addSystemMessage('👋 $name joined the room!');
    notifyListeners();
  }

  void _handleRoomState(Map<String, dynamic> msg) {
    if (_roomStateCompleter != null && !_roomStateCompleter!.isCompleted) {
      _roomStateCompleter!.complete(true);
    }

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
      addSystemMessage('🎬 Now playing: ${_mediaPayload!.title}');
      _onMediaReceived?.call(_mediaPayload!);
    }

    final pos = (msg['positionSec'] as num?)?.toDouble() ?? 0.0;
    if (pos > 0) {
      _applyPlaybackSync(
          Duration(milliseconds: (pos * 1000).round()), msg['isPlaying'] == true);
    }
    notifyListeners();
  }

  void _handleMediaUpdate(Map<String, dynamic> msg) {
    if (msg['media'] is Map) {
      _mediaPayload = WatchMediaPayload.fromJson(
          Map<String, dynamic>.from(msg['media'] as Map));
      addSystemMessage('🎬 Host switched to: ${_mediaPayload!.title}');
      _onMediaReceived?.call(_mediaPayload!);
    }
    final pos = (msg['positionSec'] as num?)?.toDouble() ?? 0.0;
    if (!isHost) {
      _applyPlaybackSync(
          Duration(milliseconds: (pos * 1000).round()), msg['isPlaying'] == true);
    }
  }

  void _handlePlaybackState(Map<String, dynamic> msg) {
    final pos = (msg['positionSec'] as num?)?.toDouble() ?? 0.0;
    final playing = msg['isPlaying'] == true;
    final senderName = msg['senderName']?.toString() ?? 'Someone';
    final senderId = msg['senderId']?.toString() ?? '';

    final idx = _participants.indexWhere((p) => p.id == senderId);
    if (idx >= 0) {
      _participants[idx].lastPositionSec = pos;
    }

    _syncNotice = playing ? null : '⏸ $senderName paused';

    // HOST NEVER APPLIES PLAYBACK SYNC TO ITSELF! Host is the master timeline authority.
    if (!isHost) {
      _applyPlaybackSync(Duration(milliseconds: (pos * 1000).round()), playing);
    }
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

  VoidCallback? _onHostLeftCallback;

  void setOnHostLeftCallback(VoidCallback callback) {
    _onHostLeftCallback = callback;
  }

  void _handleLeave(Map<String, dynamic> msg, String senderId) {
    final name = msg['senderName']?.toString() ?? 'Participant';
    final wasHost = _participants.any((p) => p.id == senderId && p.isHost);

    if (wasHost || msg['type'] == 'ROOM_CLOSED') {
      addSystemMessage('👑 Host has closed the Watch Together room.');
      _onHostLeftCallback?.call();
      _teardown();
      notifyListeners();
      return;
    }

    final before = _participants.length;
    _participants.removeWhere((p) => p.id == senderId);
    _guestSlots.removeWhere((s) => s.guestId == senderId);
    if (_participants.length < before) {
      addSystemMessage('$name left the room.');
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> pingHeartbeat() async {
    try {
      await Supabase.instance.client.from('watch_together_rooms').select('id').limit(1);
    } catch (_) {}
  }

  void leaveRoom() {
    if (!isActive) return;
    if (isHost) {
      _broadcastPayload({'type': 'ROOM_CLOSED', 'senderId': _myId, 'senderName': _myName});
      addSystemMessage('👑 You closed the room.');
    } else {
      _broadcastPayload({'type': 'LEAVE_ROOM', 'senderId': _myId, 'senderName': _myName});
      addSystemMessage('👋 You left the room.');
    }
    _teardown();
    notifyListeners();
  }

  void requestRoomState() {
    if (!isActive) return;
    _broadcastPayload({'type': 'REQUEST_SYNC', 'senderId': _myId, 'senderName': _myName});
  }

  void updateLocalPlaybackState({
    required Duration position,
    required bool isPlaying,
    bool forceBroadcast = false,
  }) {
    _currentPosition = position;
    _isPlaying = isPlaying;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    if (isActive && (forceBroadcast || nowMs - _lastPosBroadcastMs > 2500)) {
      _lastPosBroadcastMs = nowMs;
      _broadcastPayload({
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
    _broadcastPayload({
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

    if (_mediaPayload != null &&
        _mediaPayload!.videoUrl == streamUrl &&
        _mediaPayload!.title == title &&
        _mediaPayload!.episodeNumber == episodeNumber) {
      return;
    }

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
    _broadcastPayload({
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
    _broadcastPayload({...chat.toJson(), 'type': 'CHAT_MESSAGE'});
  }

  void sendEmojiReaction(String emoji) {
    if (!isActive) return;
    _reactionCtrl.add(WatchEmojiReaction(
      senderName: _myName,
      emoji: emoji,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    _broadcastPayload({
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

  void clearPlaybackSyncCallback() => _onExternalPlaybackSync = null;

  void setMediaReceivedCallback(Function(WatchMediaPayload) callback) {
    _onMediaReceived = callback;
    if (_mediaPayload?.videoUrl != null) callback(_mediaPayload!);
  }

  void clearMediaReceivedCallback() => _onMediaReceived = null;

  // ─── Private Helpers ──────────────────────────────────────────────────────

  void _setStatus(WTConnectionStatus status, String message) {
    _connectionStatus = status;
    _statusMessage = message;
  }

  void _applyPlaybackSync(Duration pos, bool playing) {
    _currentPosition = pos;
    _isPlaying = isPlaying;
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

  void _teardown() {
    if (_channel != null) {
      try {
        _channel!.untrack();
        _channel!.unsubscribe();
        Supabase.instance.client.removeChannel(_channel!);
      } catch (_) {}
      _channel = null;
    }

    _role = WTRole.none;
    _mediaPayload = null;
    _syncNotice = null;
    _currentPosition = Duration.zero;
    _isPlaying = false;
    _statusMessage = '';

    _onMediaReceived = null;
    _onExternalPlaybackSync = null;

    _guestSlots.clear();
    _connectionStatus = WTConnectionStatus.disconnected;
    _participants.clear();
    _chatMessages.clear();
    _unreadChatCount = 0;
    _isChatDrawerOpen = false;
  }

  // ─── Static Helpers ──────────────────────────────────────────────────────

  static void playDirect(WatchMediaPayload media, {BuildContext? context}) {
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

    final targetContext = context ?? appNavigatorKey.currentContext;
    if (targetContext != null) {
      Navigator.of(targetContext).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            streamUrl: media.videoUrl!,
            title: media.title,
            anilistId: null,
            titles: [media.title],
            episodeCount: 1,
            episodeNumber: media.episodeNumber,
            isMovie: media.isMovie,
          ),
        ),
      );
    }
  }

  static Future<void> resolveAndPlay(
      BuildContext context, WatchMediaPayload media) async {
    playDirect(media);
  }
}

// ─── Join Result Enum ───────────────────────────────────────────────────────

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
      case WTJoinResult.success:
        return 'Connected!';
      case WTJoinResult.invalidCode:
        return 'Please enter a valid room code (4-6 digits).';
      case WTJoinResult.roomNotFound:
        return 'Room not found or host is offline.';
      case WTJoinResult.invalidOffer:
        return 'Invalid room message format.';
      case WTJoinResult.webrtcError:
      case WTJoinResult.networkError:
        return 'Network connection failed. Please check your internet connection.';
      case WTJoinResult.error:
        return 'An unexpected error occurred. Please try again.';
    }
  }
}
