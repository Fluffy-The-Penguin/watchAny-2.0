import 'package:http/http.dart' as http;

Future<void> main() async {
  final url = 'https://imoto-str.ane-h.xyz/2023/Ano.Danchi.no.Tsumatachi.wa.The.Animation/E01/1080/manifest.mpd';
  print('Fetching manifest: $url');
  
  try {
    final response = await http.get(Uri.parse(url));
    print('Status: ${response.statusCode}');
    if (response.statusCode == 200) {
      final text = response.body;
      print('Manifest length: ${text.length}');
      // Print first 1500 chars to see the structure
      print(text.substring(0, text.length > 1500 ? 1500 : text.length));
    } else {
      print('Failed to fetch manifest');
    }
  } catch (e) {
    print('Error: $e');
  }
}
