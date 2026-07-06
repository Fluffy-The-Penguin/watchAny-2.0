import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class VideoProxyService {
  static final VideoProxyService _instance = VideoProxyService._internal();
  factory VideoProxyService() => _instance;
  VideoProxyService._internal();

  HttpServer? _server;
  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;
  
  // Cache for DASH manifests to avoid re-fetching when player asks for audio/video playlists
  final Map<String, String> _mpdCache = {};

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      debugPrint('[VideoProxyService] Started on port $port');
      _server!.listen(_handleRequest);
    } catch (e) {
      debugPrint('[VideoProxyService] Error starting: $e');
    }
  }

  void stop() {
    _server?.close(force: true);
    _server = null;
  }

  String getProxyUrl(String targetUrl, {Map<String, String>? headers, bool isDash = false}) {
    if (!isRunning) return targetUrl;
    
    if (isDash) {
      return Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        path: '/dash_proxy',
        queryParameters: {
          'url': targetUrl,
          'type': 'master',
          if (headers != null) ...headers,
        },
      ).toString();
    }
    
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      queryParameters: {
        'url': targetUrl,
        if (headers != null) ...headers,
      },
    ).toString();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.path == '/dash_proxy') {
        await _handleDashProxy(request);
        return;
      }

      final targetUrl = request.uri.queryParameters['url'];
      if (targetUrl == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Missing url parameter')
          ..close();
        return;
      }

      final targetUri = Uri.parse(targetUrl);
      // Use dart:io HttpClient with autoUncompress = false for standard proxying too
      final ioClient = HttpClient()..autoUncompress = false;
      final ioRequest = await ioClient.openUrl(request.method, targetUri);

      // Copy relevant headers from the client (media_kit) to the target request
      request.headers.forEach((name, values) {
        if (name.toLowerCase() == 'host') return;
        for (final value in values) {
          ioRequest.headers.add(name, value);
        }
      });

      // Inject custom headers passed in query parameters
      request.uri.queryParameters.forEach((key, value) {
        if (key != 'url') {
          ioRequest.headers.set(key, value);
        }
      });

      final ioResponse = await ioRequest.close();

      // Copy response headers back to the client natively
      ioResponse.headers.forEach((name, values) {
        for (final value in values) {
          request.response.headers.add(name, value);
        }
      });

      request.response.statusCode = ioResponse.statusCode;

      // Pipe the raw response stream
      await ioResponse.pipe(request.response);
    } catch (e) {
      debugPrint('[VideoProxyService] Error handling request: $e');
      if (request.response.connectionInfo != null) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.close();
      }
    }
  }

  Future<void> _handleDashProxy(HttpRequest request) async {
    final targetUrl = request.uri.queryParameters['url'];
    final type = request.uri.queryParameters['type']; // 'master', 'video', 'audio'
    final segment = request.uri.queryParameters['segment'];

    if (targetUrl == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing url parameter')
        ..close();
      return;
    }

    final baseUrl = targetUrl.substring(0, targetUrl.lastIndexOf('/'));

    // Handle fetching segment binary data
    if (segment != null) {
      final segmentUrl = '$baseUrl/$segment';
      final ioClient = HttpClient()..autoUncompress = false;
      HttpClientRequest? ioRequest;
      HttpClientResponse? ioResponse;
      try {
        ioRequest = await ioClient.getUrl(Uri.parse(segmentUrl));
        
        // Inject standard headers required by CDN
        request.uri.queryParameters.forEach((key, value) {
          if (key != 'url' && key != 'type' && key != 'segment') {
            ioRequest!.headers.set(key, value);
          }
        });
        if (request.headers.value('range') != null) {
          ioRequest.headers.set('range', request.headers.value('range')!);
        }

        ioResponse = await ioRequest.close();
        
        ioResponse.headers.forEach((name, values) {
          final lower = name.toLowerCase();
          if (lower == 'content-type') return;
          for (final value in values) {
            request.response.headers.add(name, value);
          }
        });
        if (segment.endsWith('.vtt')) {
          request.response.headers.set('Content-Type', 'text/vtt');
        } else {
          request.response.headers.set('Content-Type', 'video/mp4');
        }
        request.response.statusCode = ioResponse.statusCode;
        await ioResponse.pipe(request.response);
      } catch (_) {
        // Client disconnected (e.g. seek cancelled) — close gracefully
        request.response.close().catchError((_) {});
      } finally {
        ioClient.close(force: true);
      }
      return;
    }

    // Otherwise, handle manifest conversion (master, video, audio)
    String mpdText;
    if (_mpdCache.containsKey(targetUrl)) {
      mpdText = _mpdCache[targetUrl]!;
    } else {
      final manifestReq = http.Request('GET', Uri.parse(targetUrl));
      request.uri.queryParameters.forEach((key, value) {
        if (key != 'url' && key != 'type' && key != 'segment') {
          manifestReq.headers[key] = value;
        }
      });
      final res = await http.Client().send(manifestReq);
      if (res.statusCode != 200) {
        request.response
          ..statusCode = res.statusCode
          ..close();
        return;
      }
      mpdText = await res.stream.bytesToString();
      _mpdCache[targetUrl] = mpdText;
    }

    final adaptationSets = mpdText.split('<AdaptationSet');
    String? videoPlaylist;
    String? audioPlaylist;
    String? videoStreamLine;
    String? audioMediaLine;

    final proxyBase = 'http://127.0.0.1:$port';
    
    // Include original headers in segment requests
    String headerParams = '';
    request.uri.queryParameters.forEach((key, value) {
      if (key != 'url' && key != 'type' && key != 'segment') {
        headerParams += '&$key=${Uri.encodeComponent(value)}';
      }
    });

    for (int i = 1; i < adaptationSets.length; i++) {
      final setXml = adaptationSets[i];
      final isVideo = setXml.contains('contentType="video"');
      final isAudio = setXml.contains('contentType="audio"');

      final repMatch = RegExp(r'<Representation id="([^"]+)"[^>]*bandwidth="([^"]+)"').firstMatch(setXml);
      if (repMatch == null) continue;

      final repId = repMatch.group(1)!;
      final bandwidth = repMatch.group(2)!;

      final segMatch = RegExp(r'<SegmentTemplate timescale="([^"]+)" initialization="([^"]+)" media="([^"]+)" startNumber="([^"]+)"').firstMatch(setXml);
      if (segMatch == null) continue;

      final timescale = double.parse(segMatch.group(1)!);
      final initPath = segMatch.group(2)!.replaceAll(r'\', '/').replaceAll(r'$RepresentationID$', repId);
      final mediaPathFormat = segMatch.group(3)!.replaceAll(r'\', '/').replaceAll(r'$RepresentationID$', repId);
      final startNumber = int.parse(segMatch.group(4)!);

      final sTags = RegExp(r'<S (?:t="([^"]+)" )?d="([^"]+)"(?: r="([^"]+)")? />').allMatches(setXml);

      // #EXT-X-PLAYLIST-TYPE:VOD is critical — without it libmpv treats this as
      // a live stream and DISABLES seeking entirely, causing infinite buffering on seek.
      String playlist = '#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-ALLOW-CACHE:YES\n#EXT-X-TARGETDURATION:11\n#EXT-X-MEDIA-SEQUENCE:$startNumber\n';
      
      // Use ABSOLUTE segment URLs so libmpv can resolve them without knowing the base URL
      final proxyInitPath = '$proxyBase/dash_proxy?url=${Uri.encodeComponent(targetUrl)}&segment=${Uri.encodeComponent(initPath)}$headerParams';
      
      playlist += '#EXT-X-MAP:URI="$proxyInitPath"\n';

      int currentNum = startNumber;
      for (final s in sTags) {
        final d = double.parse(s.group(2)!);
        final r = s.group(3) != null ? int.parse(s.group(3)!) : 0;
        final duration = d / timescale;

        for (int k = 0; k <= r; k++) {
          playlist += '#EXTINF:${duration.toStringAsFixed(3)},\n';
          final numberStr = currentNum.toString().padLeft(5, '0');
          final mediaPath = mediaPathFormat.replaceAll(r'$Number%05d$', numberStr);
          final proxyMediaPath = '$proxyBase/dash_proxy?url=${Uri.encodeComponent(targetUrl)}&segment=${Uri.encodeComponent(mediaPath)}$headerParams';
          playlist += '$proxyMediaPath\n';
          currentNum++;
        }
      }
      playlist += '#EXT-X-ENDLIST\n';

      if (isVideo) {
        final codecs = RegExp(r'codecs="([^"]+)"').firstMatch(setXml)?.group(1) ?? 'av01.0.08M.08';
        videoPlaylist = playlist;
        videoStreamLine = '#EXT-X-STREAM-INF:BANDWIDTH=$bandwidth,CODECS="$codecs",AUDIO="audio",SUBTITLES="subs"\n$proxyBase/dash_proxy?url=${Uri.encodeComponent(targetUrl)}&type=video$headerParams';
      } else if (isAudio) {
        audioPlaylist = playlist;
        audioMediaLine = '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",DEFAULT=YES,URI="$proxyBase/dash_proxy?url=${Uri.encodeComponent(targetUrl)}&type=audio$headerParams"';
      }
    }

    // Build master playlist in the CORRECT order: #EXTM3U must always be line 1
    final masterPlaylist = StringBuffer('#EXTM3U\n');
    final subUri = '$proxyBase/dash_proxy?url=${Uri.encodeComponent(targetUrl)}&segment=eng.vtt$headerParams';
    final subtitleMediaLine = '#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",DEFAULT=YES,AUTOSELECT=YES,FORCED=NO,LANGUAGE="en",URI="$subUri"';
    masterPlaylist.writeln(subtitleMediaLine);
    if (audioMediaLine != null) masterPlaylist.writeln(audioMediaLine);
    if (videoStreamLine != null) masterPlaylist.writeln(videoStreamLine);

    String responseBody = '';
    if (type == 'master') {
      responseBody = masterPlaylist.toString();
    } else if (type == 'video' && videoPlaylist != null) {
      responseBody = videoPlaylist;
    } else if (type == 'audio' && audioPlaylist != null) {
      responseBody = audioPlaylist;
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set('Content-Type', 'application/vnd.apple.mpegurl')
      ..write(responseBody)
      ..close();
  }
}
