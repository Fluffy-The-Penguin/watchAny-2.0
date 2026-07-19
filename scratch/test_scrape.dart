import 'dart:convert';
import 'package:http/http.dart' as http;

List<int> hexToBytes(String hex) {
  var bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}

String percentEncodeBytes(List<int> bytes) {
  return bytes.map((b) => '%' + b.toRadixString(16).padLeft(2, '0')).join();
}

void main() async {
  final hash = '1f20d43befcd464490bef52d6c66515aa85977e2';
  final encodedHash = percentEncodeBytes(hexToBytes(hash));
  final url = 'https://tracker.opentrackr.org:443/scrape?info_hash=$encodedHash';
  print('Scraping url: $url');
  
  try {
    final response = await http.get(Uri.parse(url));
    print('Status code: ${response.statusCode}');
    print('Response body length: ${response.bodyBytes.length}');
    // Let's print the string representation or hex representation of the body
    print('Response: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }
}
