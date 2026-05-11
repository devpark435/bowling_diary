import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LanePoint', () {
    test('레인 평면 좌표 (x m, y m)', () {
      const p = LanePoint(xM: 0.525, yM: 18.29);
      expect(p.xM, 0.525);
      expect(p.yM, 18.29);
    });

    test('동등성 비교', () {
      expect(const LanePoint(xM: 1.0, yM: 2.0),
          const LanePoint(xM: 1.0, yM: 2.0));
    });
  });

  group('FramePoint', () {
    test('정규화 좌표 (0~1)', () {
      const p = FramePoint(nx: 0.5, ny: 0.8);
      expect(p.nx, 0.5);
      expect(p.ny, 0.8);
    });

    test('동등성 비교', () {
      expect(const FramePoint(nx: 0.5, ny: 0.8),
          const FramePoint(nx: 0.5, ny: 0.8));
    });
  });
}
