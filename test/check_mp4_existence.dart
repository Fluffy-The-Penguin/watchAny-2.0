import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  // Let's check a raw stream path on HStream's actual global domains
  // Ano Danchi no Tsumatachi wa E01 stream path:
  // 2023/Ano.Danchi.no.Tsumatachi.wa.The.Animation/E01
  
  final domains = ['https://imoto-str.ane-h.xyz', 'https://miku-str.ane-h.xyz'];
  final streamPath = '2023/Ano.Danchi.no.Tsumatachi.wa.The.Animation/E01';
  
  final candidates = [
    '360/manifest.mpd',
    '480/manifest.mpd',
    '720/manifest.mpd',
    '1080/manifest.mpd',
    '2160/manifest.mpd',
    'x264.360p.mp4',
    'x264.480p.mp4',
    'x264.720p.mp4',
    'x264.1080p.mp4',
  ];
  
  for (final domain in domains) {
    print('Testing domain: $domain');
    for (final candidate in candidates) {
      final url = '$domain/$streamPath/$candidate';
      try {
        final request = http.Request('HEAD', Uri.parse(url));
        request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
        request.headers['Referer'] = 'https://hstream.moe/';
        final response = await request.send().timeout(Duration(seconds: 3));
        await response.stream.listen((_) {}).cancel();
        print(' - $candidate: ${response.statusCode}');
      } catch (e) {
        print(' - $candidate: Error ($e)');
      }
    }
  }
}
