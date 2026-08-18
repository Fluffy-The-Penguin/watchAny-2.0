import '../models/web_stream_server.dart';

class WebStreamService {
  static final WebStreamService _instance = WebStreamService._internal();
  factory WebStreamService() => _instance;
  WebStreamService._internal();

  static final List<WebStreamServer> availableServers = [
    WebStreamServer(
      id: 'megaplay_ani',
      name: 'MegaPlay',
      badge: 'AniList Direct',
      description: 'Fast Direct Stream (1080p / 720p / Auto)',
      supportsDub: true,
      qualityLabel: '1080p / 720p / Auto',
      urlBuilder: ({required anilistId, required episode, required audioType, malId}) {
        final mode = audioType == AudioType.dub ? 'dub' : 'sub';
        return 'https://megaplay.buzz/stream/ani/$anilistId/$episode/$mode';
      },
    ),
    WebStreamServer(
      id: 'vidnest_hd',
      name: 'VidNest HD',
      badge: '1080p Ultra',
      description: '1080p Ultra HD Clean Stream',
      supportsDub: true,
      qualityLabel: '1080p Ultra HD',
      urlBuilder: ({required anilistId, required episode, required audioType, malId}) {
        final mode = audioType == AudioType.dub ? 'dub' : 'sub';
        return 'https://vidnest.fun/anime/$anilistId/$episode/$mode';
      },
    ),
    WebStreamServer(
      id: 'vidnest_pahe',
      name: 'VidNest Pahe',
      badge: 'Pahe CDN',
      description: 'High-Speed Pahe Cloud CDN Stream',
      supportsDub: true,
      qualityLabel: 'High-Speed CDN',
      urlBuilder: ({required anilistId, required episode, required audioType, malId}) {
        final mode = audioType == AudioType.dub ? 'dub' : 'sub';
        return 'https://vidnest.fun/animepahe/$anilistId/$episode/$mode';
      },
    ),
    WebStreamServer(
      id: 'megaplay_mal',
      name: 'MegaPlay MAL',
      badge: 'MAL Direct',
      description: 'MyAnimeList Direct Embed Stream',
      supportsDub: true,
      qualityLabel: 'MAL Sync Stream',
      urlBuilder: ({required anilistId, required episode, required audioType, malId}) {
        final mode = audioType == AudioType.dub ? 'dub' : 'sub';
        final targetId = (malId != null && malId > 0) ? malId : anilistId;
        return 'https://megaplay.buzz/stream/mal/$targetId/$episode/$mode';
      },
    ),
    WebStreamServer(
      id: '2embed',
      name: '2Embed',
      badge: 'Multi-Server',
      description: 'Universal Multi-Server Fallback',
      supportsDub: false,
      qualityLabel: 'Multi-Server',
      urlBuilder: ({required anilistId, required episode, required audioType, malId}) {
        return 'https://www.2embed.cc/embedtv/$anilistId&s=1&e=$episode';
      },
    ),
  ];

  static String generateEmbedHtml(String embedUrl) {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    html, body {
      width: 100%;
      height: 100%;
      background-color: #000000;
      overflow: hidden;
      display: flex;
      justify-content: center;
      align-items: center;
    }
    iframe {
      width: 100%;
      height: 100%;
      border: 0;
      display: block;
      background-color: #000000;
    }
  </style>
</head>
<body>
  <iframe
    src="$embedUrl"
    allowfullscreen="true"
    webkitallowfullscreen="true"
    mozallowfullscreen="true"
    allow="autoplay; fullscreen; encrypted-media; picture-in-picture"
    scrolling="no"
    frameborder="0">
  </iframe>
</body>
</html>
''';
  }
}
