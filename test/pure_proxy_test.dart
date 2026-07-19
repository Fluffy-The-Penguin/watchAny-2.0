import 'dart:async';
import 'dart:io';

Future<void> main() async {
  // Start the proxy logic manually without flutter
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  print('Proxy running on ${server.port}');
  
  server.listen((HttpRequest request) async {
    try {
      final targetUrl = request.uri.queryParameters['url'];
      if (targetUrl == null) return;
      
      print('Proxy fetching: $targetUrl');
      final ioClient = HttpClient()..autoUncompress = false;
      final ioRequest = await ioClient.getUrl(Uri.parse(targetUrl));
      
      // Inject headers
      request.uri.queryParameters.forEach((key, value) {
        if (key != 'url') {
          ioRequest.headers.set(key, value);
        }
      });
      if (request.headers.value('range') != null) {
        ioRequest.headers.set('range', request.headers.value('range')!);
      }
      
      final ioResponse = await ioRequest.close();
      
      print('Proxy CDN Response: ${ioResponse.statusCode}');
      ioResponse.headers.forEach((name, values) {
        for (final value in values) {
          request.response.headers.add(name, value);
        }
      });
      
      request.response.statusCode = ioResponse.statusCode;
      await ioResponse.pipe(request.response);
      print('Proxy pipe complete');
    } catch (e) {
      print('Proxy error: $e');
    }
  });

  // Now act as ffmpeg
  final target = 'https://imoto-str.ane-h.xyz/2023/Ano.Danchi.no.Tsumatachi.wa.The.Animation/E01/1080/chunks/init-stream0.html';
  final proxyUrl = 'http://127.0.0.1:${server.port}/?url=${Uri.encodeComponent(target)}&User-Agent=test&Referer=https://hstream.moe/';
  
  print('FFmpeg requesting: $proxyUrl');
  final client = HttpClient()..autoUncompress = false; // ffmpeg doesn't auto uncompress
  final req = await client.getUrl(Uri.parse(proxyUrl));
  final res = await req.close();
  
  print('FFmpeg status: ${res.statusCode}');
  print('FFmpeg headers:');
  res.headers.forEach((name, values) {
    print('  $name: $values');
  });
  
  int bytes = 0;
  await for (final chunk in res) {
    bytes += chunk.length;
  }
  print('FFmpeg read bytes: $bytes');
  
  exit(0);
}
