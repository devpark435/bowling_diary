import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BallDetection.contactPoint', () {
    test('bbox 바닥 중점(cy + bh/2)을 접점으로 반환한다', () {
      const det = BallDetection(cx: 0.4, cy: 0.5, bw: 0.1, bh: 0.2, confidence: 0.9);

      final contact = det.contactPoint;

      expect(contact.nx, 0.4);
      expect(contact.ny, closeTo(0.6, 1e-9));
    });

    test('바닥 근처에서는 1.0으로 클램프된다', () {
      const det = BallDetection(cx: 0.5, cy: 0.95, bw: 0.1, bh: 0.2, confidence: 0.9);

      final contact = det.contactPoint;

      expect(contact.ny, 1.0);
    });
  });
}
