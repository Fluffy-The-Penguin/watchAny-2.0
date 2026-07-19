import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final url = 'https://hstream.moe/hentai/ano-danchi-no-tsuma-tachi-wa-the-animation-1';
  
  // Use dart:io to get individual Set-Cookie headers
  final ioClient = HttpClient();
  final req = await ioClient.getUrl(Uri.parse(url));
  req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36');
  req.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
  req.headers.set('Accept-Language', 'en-US,en;q=0.9');
  final res = await req.close();
  
  print('Status: ${res.statusCode}');
  
  // dart:io gives proper individual cookies
  final cookies = res.cookies;
  print('Cookies (${cookies.length}):');
  for (final c in cookies) {
    print('  ${c.name}=${c.value}');
  }
  
  final cookieHeader = cookies.map((c) => '${c.name}=${c.value}').join('; ');
  print('\nCookie header: $cookieHeader\n');
  
  final htmlBytes = <int>[];
  await for (final chunk in res) htmlBytes.addAll(chunk);
  final html = utf8.decode(htmlBytes);
  
  final token = RegExp(r'name="_token"\s+value="([^"]+)"', caseSensitive: false).firstMatch(html)?.group(1)
    ?? RegExp(r'name="csrf-token"\s+content="([^"]+)"', caseSensitive: false).firstMatch(html)?.group(1);
  final episodeId = RegExp(r'id="e_id"\s+type="hidden"\s+value="([^"]+)"', caseSensitive: false).firstMatch(html)?.group(1)
    ?? RegExp(r'value="([^"]+)"\s+[^>]*id="e_id"', caseSensitive: false).firstMatch(html)?.group(1);
  
  print('Token: $token');
  print('Episode ID: $episodeId');
  
  if (token == null || episodeId == null) {
    print('Missing token or episode id!');
    return;
  }
  
  // Step 2: POST to player/api using dart:io
  final apiReq = await ioClient.postUrl(Uri.parse('https://hstream.moe/player/api'));
  apiReq.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36');
  apiReq.headers.set('Accept', 'application/json');
  apiReq.headers.set('Content-Type', 'application/json');
  apiReq.headers.set('X-CSRF-TOKEN', token);
  apiReq.headers.set('X-Requested-With', 'XMLHttpRequest');
  apiReq.headers.set('Referer', url);
  apiReq.headers.set('Origin', 'https://hstream.moe');
  apiReq.headers.set('Cookie', cookieHeader);
  
  final body = jsonEncode({'episode_id': episodeId});
  apiReq.contentLength = utf8.encode(body).length;
  apiReq.write(body);
  
  final apiRes = await apiReq.close();
  final apiBytes = <int>[];
  await for (final chunk in apiRes) apiBytes.addAll(chunk);
  
  print('\nAPI Status: ${apiRes.statusCode}');
  print('API Body: ${utf8.decode(apiBytes)}');
  
  ioClient.close();
}
