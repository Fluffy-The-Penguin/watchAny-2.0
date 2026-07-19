import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final baseDomain = 'https://imoto-str.ane-h.xyz';
  final streamPath = '2023/Ano.Danchi.no.Tsumatachi.wa.The.Animation/E01';

  final qualities = {
    '360p': '$baseDomain/$streamPath/360/manifest.mpd',
    '480p': '$baseDomain/$streamPath/480/manifest.mpd',
    '720p': '$baseDomain/$streamPath/720/manifest.mpd',
    '1080p': '$baseDomain/$streamPath/1080/manifest.mpd',
    '1080p48': '$baseDomain/$streamPath/1080i/manifest.mpd',
    '2160p': '$baseDomain/$streamPath/2160/manifest.mpd',
    '2160p48': '$baseDomain/$streamPath/2160i/manifest.mpd',
    '720p MP4': '$baseDomain/$streamPath/x264.720p.mp4',
  };

  final client = http.Client();
  final futures = qualities.entries.map((entry) async {
    try {
      final request = http.Request('HEAD', Uri.parse(entry.value));
      request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
      request.headers['Referer'] = 'https://hstream.moe/';
      
      final response = await client.send(request);
      print('${entry.key}: Status ${response.statusCode}');
      // Must read and discard the response stream to free the socket
      await response.stream.listen((_) {}).cancel();
    } catch (e) {
      print('${entry.key}: Error $e');
    }
  });

  await Future.wait(futures);
  client.close();
}
