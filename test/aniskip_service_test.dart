import 'package:flutter_test/flutter_test.dart';
import '../lib/services/aniskip_service.dart';

void main() {
  group('AniSkip Interval Parsing Tests', () {
    test('SkipInterval.fromJson parses standard OP response correctly', () {
      final json = {
        "interval": {
          "startTime": 85.5,
          "endTime": 175.0
        },
        "skipType": "op",
        "skipId": "abcdef"
      };

      final interval = SkipInterval.fromJson(json);

      expect(interval.startTime, 85.5);
      expect(interval.endTime, 175.0);
      expect(interval.skipType, "op");
    });

    test('SkipInterval.fromJson parses standard ED response correctly', () {
      final json = {
        "interval": {
          "startTime": 1200.0,
          "endTime": 1290.0
        },
        "skipType": "ed",
        "skipId": "xyz123"
      };

      final interval = SkipInterval.fromJson(json);

      expect(interval.startTime, 1200.0);
      expect(interval.endTime, 1290.0);
      expect(interval.skipType, "ed");
    });
  });
}
