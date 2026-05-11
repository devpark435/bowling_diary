// test/features/analysis/domain/services/homography_solver_test.dart
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/homography_solver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomographySolver', () {
    test('레인 4코너 → 호모그래피, 라운드트립 정확', () {
      const framePts = [
        FramePoint(nx: 0.30, ny: 0.95),
        FramePoint(nx: 0.70, ny: 0.95),
        FramePoint(nx: 0.55, ny: 0.30),
        FramePoint(nx: 0.45, ny: 0.30),
      ];
      const lanePts = [
        LanePoint(xM: 0,    yM: 0),
        LanePoint(xM: 1.05, yM: 0),
        LanePoint(xM: 1.05, yM: 18.29),
        LanePoint(xM: 0,    yM: 18.29),
      ];
      final h = HomographySolver.solve4Point(framePts, lanePts);
      for (var i = 0; i < 4; i++) {
        final out = h.frameToLane(framePts[i]);
        expect(out.xM, closeTo(lanePts[i].xM, 1e-3));
        expect(out.yM, closeTo(lanePts[i].yM, 1e-3));
        final back = h.laneToFrame(out);
        expect(back.nx, closeTo(framePts[i].nx, 1e-6));
        expect(back.ny, closeTo(framePts[i].ny, 1e-6));
      }
    });

    test('정사각 직접 매핑', () {
      // 정규화 (nx, ny) → (nx*1.05, ny*18.29) m 매핑
      const framePts = [
        FramePoint(nx: 0, ny: 0),
        FramePoint(nx: 1, ny: 0),
        FramePoint(nx: 1, ny: 1),
        FramePoint(nx: 0, ny: 1),
      ];
      const lanePts = [
        LanePoint(xM: 0,    yM: 0),
        LanePoint(xM: 1.05, yM: 0),
        LanePoint(xM: 1.05, yM: 18.29),
        LanePoint(xM: 0,    yM: 18.29),
      ];
      final h = HomographySolver.solve4Point(framePts, lanePts);
      final mid = h.frameToLane(const FramePoint(nx: 0.5, ny: 0.5));
      expect(mid.xM, closeTo(0.525, 1e-6));
      expect(mid.yM, closeTo(9.145, 1e-6));
    });

    test('점 4개 아니면 ArgumentError', () {
      expect(
        () => HomographySolver.solve4Point(
          const [FramePoint(nx: 0, ny: 0)],
          const [LanePoint(xM: 0, yM: 0)],
        ),
        throwsArgumentError,
      );
    });

    test('공선 4점은 ArgumentError', () {
      const f = [
        FramePoint(nx: 0, ny: 0),
        FramePoint(nx: 1, ny: 0),
        FramePoint(nx: 2, ny: 0),
        FramePoint(nx: 3, ny: 0),
      ];
      const l = [
        LanePoint(xM: 0, yM: 0),
        LanePoint(xM: 1, yM: 0),
        LanePoint(xM: 2, yM: 0),
        LanePoint(xM: 3, yM: 0),
      ];
      expect(() => HomographySolver.solve4Point(f, l), throwsArgumentError);
    });
  });
}
