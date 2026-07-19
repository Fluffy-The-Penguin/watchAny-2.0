import 'package:flutter_test/flutter_test.dart';
import 'package:watch_any/services/extension_service.dart';
import 'package:watch_any/services/log_service.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  test('ExtensionService Search Integration Test', () async {
    // 1. Initialize logs and extensions
    await LogService().init();
    final extService = ExtensionService();
    await extService.init();

    print("Installed Extensions: ${extService.extensions.length}");
    for (final ext in extService.extensions) {
      print(" - ${ext.name} (id: ${ext.id}, enabled: ${ext.isEnabled})");
    }

    // 2. Query Frieren Season 2 Episode 8
    final searchStream = extService.searchStreamsStream(
      anilistId: 182255,
      titles: ["Frieren: Beyond Journey’s End Season 2", "Sousou no Frieren 2nd Season", "葬送のフリーレン 第2期"],
      episodeCount: 10,
      episodeNumber: 8,
    );

    final List<TorrentStream> foundStreams = [];
    
    await for (final list in searchStream) {
      print("Stream emission received: ${list.length} streams");
      foundStreams.clear();
      foundStreams.addAll(list);
    }

    print("--- SEARCH COMPLETED ---");
    print("Found ${foundStreams.length} total streams:");
    for (final s in foundStreams.take(15)) {
      print("  [${s.extensionName}] [Seeders: ${s.seeders}] ${s.title}");
    }
  });
}
