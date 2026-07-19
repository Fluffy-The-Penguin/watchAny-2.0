import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_any/services/video_proxy_service.dart';

void main() {
  test('simulate player proxy', () async {
    // Start the proxy
    final proxy = VideoProxyService();
    await proxy.start();
    
    final targetUrl = 'https://imoto-str.ane-h.xyz/2023/Ano.Danchi.no.Tsumatachi.wa.The.Animation/E01/1080/manifest.mpd';
    final proxyMasterUrl = proxy.getProxyUrl(targetUrl, headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
      'Referer': 'https://hstream.moe/'
    }, isDash: true);
    
    print('Requesting master: $proxyMasterUrl');
    final masterRes = await http.get(Uri.parse(proxyMasterUrl));
    expect(masterRes.statusCode, 200);
    print('Master status: ${masterRes.statusCode}');
    
    // Extract video playlist URL
    final videoMatch = RegExp(r'(/dash_proxy\?url=[^\s]+type=video[^\s]+)').firstMatch(masterRes.body);
    expect(videoMatch, isNotNull);
    
    final videoUrl = 'http://127.0.0.1:${proxy.port}${videoMatch!.group(1)}';
    print('\nRequesting video playlist: $videoUrl');
    final videoRes = await http.get(Uri.parse(videoUrl));
    expect(videoRes.statusCode, 200);
    print('Video status: ${videoRes.statusCode}');
    
    // Extract init chunk URL
    final initMatch = RegExp(r'URI="([^"]*dash_proxy\?url=[^\s]+segment=[^"]+)"').firstMatch(videoRes.body);
    expect(initMatch, isNotNull);
    
    final initUrl = initMatch!.group(1)!;
    print('\nRequesting init chunk: $initUrl');
    final initRes = await http.get(Uri.parse(initUrl));
    expect(initRes.statusCode, 200);
    print('Init status: ${initRes.statusCode}');
    print('Init bytes: ${initRes.bodyBytes.length}');
    
    // Stop proxy
    proxy.stop();
  });
}
