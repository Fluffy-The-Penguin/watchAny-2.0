import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Testing xxxClub Addon ---');
  final manifestUrl = 'https://xclub-stremio.vercel.app/manifest.json';
  final baseUrl = 'https://xclub-stremio.vercel.app';
  
  try {
    // 1. Fetch catalog first to see catalog item IDs
    final catalogUrl = '$baseUrl/catalog/movie/xxxclub_1080p.json';
    print('Fetching catalog from: $catalogUrl');
    final catRes = await http.get(Uri.parse(catalogUrl));
    if (catRes.statusCode == 200) {
      final data = jsonDecode(catRes.body);
      final List metas = data['metas'] ?? [];
      print('Found ${metas.length} items in catalog.');
      if (metas.isNotEmpty) {
        final firstItem = metas.first;
        final id = firstItem['id'];
        final title = firstItem['name'];
        print('First item: ID="$id", Title="$title"');
        
        // 2. Fetch streams for this item
        final streamUrl = '$baseUrl/stream/movie/$id.json';
        print('Fetching streams from: $streamUrl');
        final streamRes = await http.get(Uri.parse(streamUrl));
        if (streamRes.statusCode == 200) {
          final streamData = jsonDecode(streamRes.body);
          final streams = streamData['streams'] ?? [];
          print('Found ${streams.length} streams.');
          for (var s in streams) {
            print('Stream JSON: ${jsonEncode(s)}');
          }
        } else {
          print('Failed to fetch streams: HTTP ${streamRes.statusCode}');
        }
      }
    } else {
      print('Failed to fetch catalog: HTTP ${catRes.statusCode}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
