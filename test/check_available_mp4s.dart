import 'dart:io';
import 'package:http/http.dart' as http;
import '../lib/services/hstream_service.dart';

void main() async {
  final service = HstreamService();
  final titles = ['Natsuzuma'];
  
  List<HstreamResult> results = [];
  for (final title in titles) {
    results = await service.search(title);
    if (results.isNotEmpty) break;
  }
  
  if (results.isEmpty) {
    print('No results found.');
    return;
  }
  
  final best = results.first;
  print('Loading streams for: ${best.title} (${best.url})');
  
  final streams = await service.getStreams(best.url);
  if (streams == null) {
    print('Failed to get streams.');
    return;
  }
  
  print('Available sources checked by HStream service:');
  for (final s in streams.sources) {
    print(' - Name: ${s.name}, Quality: ${s.quality}, URL: ${s.url}, Type: ${s.type}');
  }
}
