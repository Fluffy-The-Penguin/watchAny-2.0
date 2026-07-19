import 'package:media_kit/media_kit.dart';

void main() {
  try {
    final track = SubtitleTrack.uri('https://example.com/sub.vtt');
    print('SubtitleTrack.uri exists and is valid!');
  } catch (e) {
    print('Error: $e');
  }
}
