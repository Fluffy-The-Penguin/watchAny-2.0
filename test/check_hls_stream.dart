import 'package:http/http.dart' as http;

Future<void> main() async {
  final client = http.Client();
  final base = 'https://imoto-str.ane-h.xyz/2023/Ano.Danchi.no.Tsumatachi.wa.The.Animation/E01';
  
  final urls = [
    '$base/720/manifest.m3u8',
    '$base/720/index.m3u8',
    '$base/720/playlist.m3u8',
    '$base/hls/720/index.m3u8',
    '$base/hls/720/manifest.m3u8',
    '$base/master.m3u8',
    '$base/index.m3u8',
  ];
  
  print('Checking for HLS (.m3u8) streams...');
  for (final url in urls) {
    try {
      final request = http.Request('HEAD', Uri.parse(url));
      final response = await client.send(request);
      print('${response.statusCode} -> $url');
      await response.stream.listen((_) {}).cancel();
    } catch (e) {
      print('Error checking $url: $e');
    }
  }
  client.close();
}
