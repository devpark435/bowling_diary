import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/homography_solver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomographySolver', () {
    test('레인 4코너 매핑 시 각 코너가 정확히 대응', () {
      final h = HomographySolver.solve4Point(
        const [
          FramePoint(nx: 0, ny: 0), FramePoint(nx: 1, ny: 0),
          FramePoint(nx: 1, ny: 1), FramePoint(nx: 0, ny: 1),
        ],
        const [
          LanePoint(xM: 0, yM: 0), LanePoint(xM: 1.05, yM: 0),
          LanePoint(xM: 1.05, yM: 18.29), LanePoint(xM: 0, yM: 18.29),
        ],
      );
      final topLeft = h.frameToLane(const FramePoint(nx: 0, ny: 0));
      expect(topLeft.xM, closeTo(0, 1e-6));
      expect(topLeft.yM, closeTo(0, 1e-6));
      final bottomRight = h.frameToLane(const FramePoint(nx: 1, ny: 1));
      expect(bottomRight.xM, closeTo(1.05, 1e-6));
      expect(bottomRight.yM, closeTo(18.29, 1e-6));
    });

    test('4쌍이 아니면 ArgumentError', () {
      expect(
        () => HomographySolver.solve4Point(
          const [FramePoint(nx: 0, ny: 0)],
          const [LanePoint(xM: 0, yM: 0)],
        ),
        throwsArgumentError,
      );
    });

    test('일직선 위 4점(특이 케이스)은 ArgumentError', () {
      expect(
        () => HomographySolver.solve4Point(
          const [
            FramePoint(nx: 0, ny: 0), FramePoint(nx: 0.3, ny: 0),
            FramePoint(nx: 0.6, ny: 0), FramePoint(nx: 1, ny: 0),
          ],
          const [
            LanePoint(xM: 0, yM: 0), LanePoint(xM: 0.3, yM: 0),
            LanePoint(xM: 0.6, yM: 0), LanePoint(xM: 1, yM: 0),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
