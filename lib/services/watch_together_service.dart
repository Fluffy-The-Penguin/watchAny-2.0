import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../state/player_state.dart';
import 'stremio_addon_service.dart';

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

  factory WatchParticipant.fromJson(Map<String, dynamic> json) => WatchParticipant(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Guest',
        isHost: json['isHost'] == true,
        isBuffering: json['isBuffering'] == true,
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

  factory WatchChatMessage.fromJson(Map<String, dynamic> json) => WatchChatMessage(
        id: json['id']?.toString() ?? Random().nextInt(9999999).toString(),
        senderId: json['senderId']?.toString() ?? '',
        senderName: json['senderName']?.toString() ?? 'User',
        text: json['text']?.toString() ?? '',
        timestamp: (json['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
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
    required this.episodeNumber,
    this.season,
    required this.isMovie,
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

  factory WatchMediaPayload.fromJson(Map<String, dynamic> json) => WatchMediaPayload(
        title: json['title']?.toString() ?? 'Shared Media',
        movieId: json['movieId']?.toString() ?? '',
        videoUrl: json['videoUrl']?.toString(),
        headers: (json['headers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())),
        torrentHash: json['torrentHash']?.toString(),
        episodeNumber: (json['episodeNumber'] as num?)?.toInt() ?? 1,
        season: (json['season'] as num?)?.toInt(),
        isMovie: json['isMovie'] == true,
      );
}

class WatchTogetherService extends ChangeNotifier {
  static final WatchTogetherService _instance = WatchTogetherService._internal();
  factory WatchTogetherService() => _instance;
  WatchTogetherService._internal();

  // Connection State
  bool _isActive = false;
  bool get isActive => _isActive;

  bool _isHost = false;
  bool get isHost => _isHost;

  String _roomCode = '';
  String get roomCode => _roomCode;

  String _myId = '';
  String get myId => _myId;

  String _myName = 'User';
  String get myName => _myName;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  String? _syncNotice;
  String? get syncNotice => _syncNotice;

  String? _hostLocalIp;
  String? get hostLocalIp => _hostLocalIp;

  // Media Payload
  WatchMediaPayload? _mediaPayload;
  WatchMediaPayload? get mediaPayload => _mediaPayload;

  // Participants & Messaging
  final List<WatchParticipant> _participants = [];
  List<WatchParticipant> get participants => List.unmodifiable(_participants);

  final List<WatchChatMessage> _chatMessages = [];
  List<WatchChatMessage> get chatMessages => List.unmodifiable(_chatMessages);

  int _unreadChatCount = 0;
  int get unreadChatCount => _unreadChatCount;

  bool _isChatDrawerOpen = false;
  bool get isChatDrawerOpen => _isChatDrawerOpen;

  // Reaction Broadcast Stream
  final StreamController<WatchEmojiReaction> _reactionStreamController =
      StreamController<WatchEmojiReaction>.broadcast();
  Stream<WatchEmojiReaction> get reactionStream => _reactionStreamController.stream;

  // Toast Chat Message Stream
  final StreamController<WatchChatMessage> _toastChatStreamController =
      StreamController<WatchChatMessage>.broadcast();
  Stream<WatchChatMessage> get toastChatStream => _toastChatStreamController.stream;

  // Playback Control Callbacks
  Function(Duration position, bool isPlaying)? _onExternalPlaybackSync;
  Function(WatchMediaPayload media)? _onMediaReceived;

  WebSocket? _relaySocket;
  HttpServer? _localServer;
  final List<WebSocket> _localClients = [];
  Timer? _heartbeatTimer;
  int _lastPositionBroadcastMs = 0;

  // Sync state tracking
  Duration _currentPosition = Duration.zero;
  Duration get currentPosition => _currentPosition;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  // ── Helper: Random 6-digit Code ───────────────────────────────────────────
  static String generateRoomCode() {
    final rng = Random();
    return (100000 + rng.nextInt(900000)).toString();
  }

  static String generateId() {
    return 'usr_${Random().nextInt(899999) + 100000}';
  }

  // ── Create Room (Host) ────────────────────────────────────────────────────
  Future<bool> createRoom({
    required String hostName,
    required WatchMediaPayload media,
  }) async {
    _leaveCurrentRoomSilent();
    _isHost = true;
    _roomCode = generateRoomCode();
    _myId = generateId();
    _myName = hostName.trim().isNotEmpty ? hostName.trim() : 'Host';
    _mediaPayload = media;
    _isActive = true;
    _unreadChatCount = 0;
    _chatMessages.clear();

    _participants.clear();
    _participants.add(WatchParticipant(id: _myId, name: _myName, isHost: true));

    addSystemMessage('Room created! Share code $_roomCode with friends.');

    await _startLocalServer();
    await _connectRelaySocket();

    notifyListeners();
    return true;
  }

  // ── Join Room (Guest) ─────────────────────────────────────────────────────
  Future<bool> joinRoom({
    required String code,
    required String guestName,
  }) async {
    _leaveCurrentRoomSilent();
    _isHost = false;
    _roomCode = code.trim();
    _myId = generateId();
    _myName = guestName.trim().isNotEmpty ? guestName.trim() : 'Guest';
    _isActive = true;
    _unreadChatCount = 0;
    _chatMessages.clear();
    _mediaPayload = null;

    _participants.clear();
    _participants.add(WatchParticipant(id: _myId, name: _myName, isHost: false));

    addSystemMessage('Joining room $_roomCode...');

    final success = await _connectRelaySocket();
    if (success) {
      _sendPayload({
        'type': 'JOIN_ROOM',
        'roomCode': _roomCode,
        'senderId': _myId,
        'senderName': _myName,
      });
    }
    notifyListeners();
    return success;
  }

  // ── Leave Room ────────────────────────────────────────────────────────────
  void leaveRoom() {
    if (!_isActive) return;
    addSystemMessage('Left Watch Together session.');
    _sendPayload({
      'type': 'LEAVE_ROOM',
      'roomCode': _roomCode,
      'senderId': _myId,
      'senderName': _myName,
    });
    _leaveCurrentRoomSilent();
    notifyListeners();
  }

  void _leaveCurrentRoomSilent() {
    _isActive = false;
    _isConnected = false;
    _isHost = false;
    _roomCode = '';
    _syncNotice = null;
    _hostLocalIp = null;
    _heartbeatTimer?.cancel();
    
    for (final client in _localClients) {
      client.close();
    }
    _localClients.clear();
    _localServer?.close(force: true);
    _localServer = null;

    _relaySocket?.close();
    _relaySocket = null;
  }

  // ── Local Host WebSocket Server (LAN Sync) ────────────────────────────────
  Future<void> _startLocalServer() async {
    if (kIsWeb) return;
    try {
      _localServer = await HttpServer.bind(InternetAddress.anyIPv4, 8492);
      _findHostLocalIp();

      _localServer!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _localClients.add(socket);

          socket.listen(
            (data) => _onSocketData(data),
            onDone: () => _localClients.remove(socket),
            onError: (_) => _localClients.remove(socket),
          );
        }
      });
    } catch (e) {
      developer.log('Local WS server bind error (port 8492 in use?): $e', name: 'WatchTogetherService');
    }
  }

  Future<void> _findHostLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && (addr.address.startsWith('192.168.') || addr.address.startsWith('10.'))) {
            _hostLocalIp = addr.address;
            return;
          }
        }
      }
    } catch (_) {}
  }

  // ── Public WebSocket Relay Client (Internet Sync) ─────────────────────────
  Future<bool> _connectRelaySocket() async {
    try {
      final wsUri = Uri.parse('wss://demo.piesocket.com/v3/channel_1?api_key=VCXSpRycMzldJybd2WnnSAuhMsZaWtToxBHvZRYD');
      _relaySocket = await WebSocket.connect(wsUri.toString()).timeout(const Duration(seconds: 6));
      _isConnected = true;

      _relaySocket!.listen(
        (data) => _onSocketData(data),
        onError: (err) {
          developer.log('Relay error: $err', name: 'WatchTogetherService');
          _isConnected = false;
          notifyListeners();
        },
        onDone: () {
          _isConnected = false;
          notifyListeners();
        },
      );

      _startHeartbeat();
      return true;
    } catch (e) {
      developer.log('Relay socket connection error: $e', name: 'WatchTogetherService');
      _isConnected = true; 
      _startHeartbeat();
      return true;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isActive) {
        _sendPayload({
          'type': 'HEARTBEAT',
          'roomCode': _roomCode,
          'senderId': _myId,
          'senderName': _myName,
          'isHost': _isHost,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  void _sendPayload(Map<String, dynamic> payload) {
    final encoded = jsonEncode(payload);

    // 1. Send via Relay Socket
    if (_relaySocket != null && _isConnected) {
      try {
        _relaySocket!.add(encoded);
      } catch (e) {
        developer.log('Relay send error: $e', name: 'WatchTogetherService');
      }
    }

    // 2. Broadcast to connected local P2P clients if host
    if (_isHost && _localClients.isNotEmpty) {
      for (final client in List<WebSocket>.from(_localClients)) {
        try {
          client.add(encoded);
        } catch (_) {
          _localClients.remove(client);
        }
      }
    }
  }

  // ── Socket Message Handler ────────────────────────────────────────────────
  void _onSocketData(dynamic rawData) {
    try {
      final Map<String, dynamic> msg = jsonDecode(rawData.toString());
      final String? msgRoomCode = msg['roomCode']?.toString();

      // Filter messages strictly for this room
      if (msgRoomCode != _roomCode) return;

      final String type = msg['type']?.toString() ?? '';
      final String senderId = msg['senderId']?.toString() ?? '';

      // Ignore self-emitted broadcast messages
      if (senderId == _myId && type != 'JOIN_ROOM') return;

      switch (type) {
        case 'JOIN_ROOM':
          final String newUserName = msg['senderName']?.toString() ?? 'Guest';
          _addParticipantIfMissing(senderId, newUserName, isHost: false);
          addSystemMessage('$newUserName joined the room!');
          
          // If I am Host, send the current room state & media payload to the new guest
          if (_isHost && _mediaPayload != null) {
            _sendPayload({
              'type': 'ROOM_STATE',
              'roomCode': _roomCode,
              'senderId': _myId,
              'media': _mediaPayload!.toJson(),
              'positionSec': _currentPosition.inMilliseconds / 1000.0,
              'isPlaying': _isPlaying,
              'participants': _participants.map((p) => p.toJson()).toList(),
            });
          }
          break;

        case 'ROOM_STATE':
          if (!_isHost) {
            if (msg['media'] is Map) {
              _mediaPayload = WatchMediaPayload.fromJson(msg['media']);
              if (_onMediaReceived != null && _mediaPayload != null) {
                _onMediaReceived!(_mediaPayload!);
              }
            }
            final double hostPos = (msg['positionSec'] as num?)?.toDouble() ?? 0.0;
            final bool hostPlaying = msg['isPlaying'] == true;
            _applyPlaybackSync(Duration(milliseconds: (hostPos * 1000).round()), hostPlaying);
          }
          break;

        case 'PLAYBACK_STATE':
          final double posSec = (msg['positionSec'] as num?)?.toDouble() ?? 0.0;
          final bool playing = msg['isPlaying'] == true;
          _syncNotice = playing ? null : '${msg['senderName'] ?? "Host"} paused playback';
          _applyPlaybackSync(Duration(milliseconds: (posSec * 1000).round()), playing);
          break;

        case 'BUFFERING':
          final bool isBuffering = msg['isBuffering'] == true;
          final String name = msg['senderName']?.toString() ?? 'Participant';
          final p = _participants.firstWhere((element) => element.id == senderId,
              orElse: () => WatchParticipant(id: senderId, name: name, isHost: false));
          p.isBuffering = isBuffering;
          _syncNotice = isBuffering ? 'Waiting for $name to buffer...' : null;
          notifyListeners();
          break;

        case 'CHAT_MESSAGE':
          final chat = WatchChatMessage.fromJson(msg);
          _chatMessages.add(chat);
          if (!_isChatDrawerOpen) {
            _unreadChatCount++;
            _toastChatStreamController.add(chat);
          }
          notifyListeners();
          break;

        case 'EMOJI_REACTION':
          final String emoji = msg['emoji']?.toString() ?? '❤️';
          final String sender = msg['senderName']?.toString() ?? 'Friend';
          _reactionStreamController.add(WatchEmojiReaction(
            senderName: sender,
            emoji: emoji,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
          break;

        case 'HEARTBEAT':
          final String name = msg['senderName']?.toString() ?? 'Guest';
          final bool isHost = msg['isHost'] == true;
          _addParticipantIfMissing(senderId, name, isHost: isHost);
          break;

        case 'LEAVE_ROOM':
          final String leftName = msg['senderName']?.toString() ?? 'Participant';
          _participants.removeWhere((p) => p.id == senderId);
          addSystemMessage('$leftName left the room.');
          notifyListeners();
          break;
      }
    } catch (e) {
      // Ignored malformed noise
    }
  }

  void _addParticipantIfMissing(String id, String name, {required bool isHost}) {
    if (id.isEmpty) return;
    final idx = _participants.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      _participants[idx].lastSeen = DateTime.now();
    } else {
      _participants.add(WatchParticipant(id: id, name: name, isHost: isHost));
      notifyListeners();
    }
  }

  // ── Sync Callbacks & Local State Updates ──────────────────────────────────
  void setPlaybackSyncCallback(Function(Duration position, bool isPlaying) callback) {
    _onExternalPlaybackSync = callback;
  }

  void setMediaReceivedCallback(Function(WatchMediaPayload media) callback) {
    _onMediaReceived = callback;
    if (_mediaPayload != null) {
      callback(_mediaPayload!);
    }
  }

  static Future<void> resolveAndPlay(BuildContext context, WatchMediaPayload media) async {
    final String type = media.isMovie ? 'movie' : 'series';

    // 1. If videoUrl is already provided, start playback immediately!
    if (media.videoUrl != null && media.videoUrl!.isNotEmpty) {
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
      return;
    }

    // 2. If videoUrl is null, resolve streams!
    String cleanId = media.movieId;
    if (cleanId.contains(':')) {
      final parts = cleanId.split(':');
      if (parts.length > 1) {
        cleanId = parts.last;
      }
    }

    String targetId = cleanId;
    if (!media.isMovie) {
      targetId = '$cleanId:${media.season ?? 1}:${media.episodeNumber}';
    }

    // Show loading overlay
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          color: Color(0xFF141417),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.deepPurpleAccent),
                SizedBox(height: 16),
                Text(
                  'Resolving stream for room...',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final addonService = StremioAddonService();
      await addonService.init();
      final streamAddons = addonService.streamAddons
          .where((a) => a.matchesId(targetId))
          .where((a) => a.supportsType(type) || a.types.isEmpty)
          .toList();

      final List<Map<String, dynamic>> allStreams = [];
      for (final addon in streamAddons) {
        try {
          final url = '${addon.baseUrl}/stream/$type/$targetId.json';
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            final List streams = body['streams'] ?? [];
            for (final s in streams) {
              if (s is Map) {
                allStreams.add(Map<String, dynamic>.from(s));
              }
            }
          }
        } catch (_) {}
      }

      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (allStreams.isNotEmpty) {
        final bestStream = allStreams.first;
        final url = bestStream['url']?.toString() ?? bestStream['externalUrl']?.toString();
        if (url != null && url.isNotEmpty) {
          PlayerState().startPlayback(
            streamUrl: url,
            title: media.title,
            movieId: media.movieId,
            episodeNumber: media.episodeNumber,
            isMovie: media.isMovie,
            headers: (bestStream['behaviorHints'] as Map?)?['requestHeaders'] != null
                ? Map<String, String>.from((bestStream['behaviorHints']['requestHeaders'] as Map))
                : null,
            media: {
              'id': media.movieId,
              'stremioId': media.movieId,
              'title': media.title,
              'format': media.isMovie ? 'MOVIE' : 'SERIES',
            },
          );
          return;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No active streams found for ${media.title}.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error resolving stream: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void updateLocalPlaybackState({required Duration position, required bool isPlaying, bool forceBroadcast = false}) {
    _currentPosition = position;
    _isPlaying = isPlaying;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Host broadcasts state updates every 2500ms or instantly if forced (play/pause/seek)
    if (_isHost && _isActive && (forceBroadcast || (nowMs - _lastPositionBroadcastMs) > 2500)) {
      _lastPositionBroadcastMs = nowMs;
      _sendPayload({
        'type': 'PLAYBACK_STATE',
        'roomCode': _roomCode,
        'senderId': _myId,
        'senderName': _myName,
        'positionSec': position.inMilliseconds / 1000.0,
        'isPlaying': isPlaying,
      });
    }
  }

  void notifyLocalBuffering(bool isBuffering) {
    if (!_isActive) return;
    _sendPayload({
      'type': 'BUFFERING',
      'roomCode': _roomCode,
      'senderId': _myId,
      'senderName': _myName,
      'isBuffering': isBuffering,
    });
  }

  void _applyPlaybackSync(Duration targetPosition, bool targetIsPlaying) {
    _currentPosition = targetPosition;
    _isPlaying = targetIsPlaying;

    if (_onExternalPlaybackSync != null) {
      _onExternalPlaybackSync!(targetPosition, targetIsPlaying);
    }
    notifyListeners();
  }

  // ── Chat & Emoji Actions ──────────────────────────────────────────────────
  void sendChatMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !_isActive) return;

    final chat = WatchChatMessage(
      id: Random().nextInt(9999999).toString(),
      senderId: _myId,
      senderName: _myName,
      text: trimmed,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _chatMessages.add(chat);
    notifyListeners();

    _sendPayload({
      ...chat.toJson(),
      'type': 'CHAT_MESSAGE',
      'roomCode': _roomCode,
    });
  }

  void sendEmojiReaction(String emoji) {
    if (!_isActive) return;

    _reactionStreamController.add(WatchEmojiReaction(
      senderName: _myName,
      emoji: emoji,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    _sendPayload({
      'type': 'EMOJI_REACTION',
      'roomCode': _roomCode,
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
    if (isOpen) {
      _unreadChatCount = 0;
    }
    notifyListeners();
  }
}
