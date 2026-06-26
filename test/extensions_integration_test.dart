import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_any/services/extension_service.dart';

void main() {
  test('Verify JS Extensions and Real-time Stream Search', () async {
    final service = ExtensionService();
    await service.init();
    
    print('Available extensions: ${service.extensions.map((e) => e.name).toList()}');
    
    // Test each enabled extension
    for (var ext in service.extensions) {
      print('Testing extension: ${ext.name}');
      try {
        final success = await service.testExtension(ext);
        print('  Test result: ${success ? "SUCCESS" : "FAILURE"}');
      } catch (e) {
        print('  Test failed with error: $e');
      }
    }

    print('\nRunning search stream for Wistoria Season 2 Episode 2 (AniList ID 182300)...');
    
    final completer = Completer<void>();
    int emissionCount = 0;
    
    final subscription = service.searchStreamsStream(
      anilistId: 182300,
      titles: ['Wistoria: Wand and Sword Season 2', 'Tsue to Tsurugi no Wistoria Season 2'],
      episodeCount: 12,
      episodeNumber: 2,
    ).listen(
      (results) {
        emissionCount++;
        print('\nStream emission $emissionCount: Emitted ${results.length} results total:');
        for (var i = 0; i < results.length && i < 5; i++) {
          final s = results[i];
          print('  - [${s.extensionName}] ${s.title} (Seeders: ${s.seeders}, Size: ${(s.size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB)');
        }
      },
      onError: (e) {
        print('Stream encountered error: $e');
      },
      onDone: () {
        print('\nStream search completed.');
        completer.complete();
      },
    );

    // Wait for the stream search to finish or timeout after 20 seconds
    await completer.future.timeout(const Duration(seconds: 20), onTimeout: () {
      print('\nSearch timed out after 20 seconds.');
      subscription.cancel();
    });
  });
}
