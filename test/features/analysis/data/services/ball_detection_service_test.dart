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

  group('letterbox', () {
    test('포트레이트 480x853 → 640: 세로 맞춤, 좌우 패딩', () {
      final lb = computeLetterbox(480, 853, 640);

      // scale = 640/853 ≈ 0.7503 → scaledW = 360, scaledH = 640
      expect(lb.scaledH, 640);
      expect(lb.scaledW, 360);
      expect(lb.padY, 0);
      expect(lb.padX, (640 - 360) ~/ 2); // 140
    });

    test('정사각 입력은 패딩 없음', () {
      final lb = computeLetterbox(500, 500, 640);
      expect(lb.scaledW, 640);
      expect(lb.scaledH, 640);
      expect(lb.padX, 0);
      expect(lb.padY, 0);
    });

    test('unletterbox: 캔버스 좌표를 원본 프레임 정규화 좌표로 역매핑', () {
      final lb = computeLetterbox(480, 853, 640); // scaledW 360, padX 140

      // 캔버스 중앙(0.5, 0.5)은 원본에서도 중앙이어야 한다:
      // cx: (0.5*640 - 140)/360 = 0.5, cy: (0.5*640 - 0)/640 = 0.5
      const onCanvas = BallDetection(cx: 0.5, cy: 0.5, bw: 0.1125, bh: 0.1, confidence: 0.8);
      final mapped = unletterbox(onCanvas, lb, 640);

      expect(mapped.cx, closeTo(0.5, 1e-9));
      expect(mapped.cy, closeTo(0.5, 1e-9));
      // bw: 0.1125*640/360 = 0.2, bh: 0.1*640/640 = 0.1
      expect(mapped.bw, closeTo(0.2, 1e-9));
      expect(mapped.bh, closeTo(0.1, 1e-9));
      expect(mapped.confidence, 0.8);
    });

    test('unletterbox: 패딩 영역 좌표는 0~1로 클램프된다', () {
      final lb = computeLetterbox(480, 853, 640);

      // 캔버스 x=0.1 (=64px)은 padX(140px)보다 왼쪽 = 패딩 안 → 0으로 클램프
      const inPad = BallDetection(cx: 0.1, cy: 0.5, bw: 0.05, bh: 0.05, confidence: 0.5);
      expect(unletterbox(inPad, lb, 640).cx, 0.0);
    });
  });
}
