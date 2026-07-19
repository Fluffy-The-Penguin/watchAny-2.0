import 'dart:async';
import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  MediaKit.ensureInitialized();

  final player = Player();

  // Subscribe to errors
  final subError = player.stream.error.listen((error) {
    print('[Player Error] $error');
  });

  // Subscribe to log messages
  final subLog = player.stream.log.listen((log) {
    print('[Player Log] [${log.level}] ${log.prefix}: ${log.text}');
  });

  final url = 'https://imoto-str.ane-h.xyz/2023/Ano.Danchi.no.Tsumatachi.wa.The.Animation/E01/x264.720p.mp4';
  print('Loading URL with headers: $url');

  try {
    await player.open(Media(
      url,
      httpHeaders: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
        'Referer': 'https://hstream.moe/',
      },
    ));
    print('Open completed. Waiting 15 seconds...');
    
    // Periodically print player state
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final width = player.state.width ?? 0;
      final height = player.state.height ?? 0;
      print('State at $i s -> Playing: ${player.state.playing}, Buffering: ${player.state.buffering}, Position: ${player.state.position}, Width: $width, Height: $height');
      if (width > 0) {
        print('SUCCESS: Stream is playing and rendering! Dimensions: ${width}x${height}');
        break;
      }
    }
  } catch (e) {
    print('Catch Error: $e');
  } finally {
    await subError.cancel();
    await subLog.cancel();
    await player.dispose();
  }
}
