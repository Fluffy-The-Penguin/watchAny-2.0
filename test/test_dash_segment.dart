import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  // Let's test the segment fetching logic exactly as the proxy does it.
  final targetUrl = 'https://imoto-str.ane-h.xyz/2023/Ano.Danchi.no.Tsumatachi.wa.The.Animation/E01/1080/manifest.mpd';
  final baseUrl = targetUrl.substring(0, targetUrl.lastIndexOf('/'));
  final segment = 'chunks/init-stream0.html';
  final segmentUrl = '$baseUrl/$segment';
  
  final clientRequest = http.Request('GET', Uri.parse(segmentUrl));
  clientRequest.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
  clientRequest.headers['Referer'] = 'https://hstream.moe/';
  
  print('Fetching segment: $segmentUrl');
  final client = http.Client();
  try {
    final response = await client.send(clientRequest);
    print('Status: ${response.statusCode}');
    print('Headers: ${response.headers}');
    
    // Read a few bytes
    int byteCount = 0;
    await for (final chunk in response.stream) {
      byteCount += chunk.length;
      if (byteCount > 1000) break;
    }
    print('Successfully read $byteCount bytes');
  } catch (e) {
    print('Error: $e');
  }
  client.close();
}
