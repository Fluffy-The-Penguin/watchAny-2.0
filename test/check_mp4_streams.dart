import 'package:http/http.dart' as http;

Future<void> main() async {
  final client = http.Client();
  final base = 'https://imoto-str.ane-h.xyz/2023/Ano.Danchi.no.Tsumatachi.wa.The.Animation/E01';
  
  final urls = [
    '$base/x264.1080p.mp4',
    '$base/1080p.mp4',
    '$base/x264.1080.mp4',
    '$base/1080/x264.1080p.mp4',
    '$base/x264.2160p.mp4',
    '$base/2160p.mp4',
    '$base/2160/x264.2160p.mp4',
  ];
  
  print('Checking for alternative MP4 streams...');
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
