import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/trajectory_curve.dart';
import 'package:bowling_diary/features/analysis/domain/services/trajectory_refiner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fitAndResample', () {
    test('직선 복원: x 고정값이면 리샘플 결과도 전부 같은 x, y 간격 0.25, frame 비내림차순', () {
      final input = <TrajectorySample>[
        for (var y = 2; y <= 18; y++) (frame: y * 5, lane: LanePoint(xM: 0.5, yM: y.toDouble())),
      ];

      final result = fitAndResample(input);

      expect(result.length, greaterThan(4));
      for (final s in result) {
        expect(s.lane.xM, closeTo(0.5, 1e-6));
      }
      for (var i = 1; i < result.length; i++) {
        final step = result[i].lane.yM - result[i - 1].lane.yM;
        expect(step, closeTo(0.25, 1e-6));
      }
      expect(result.last.lane.yM, closeTo(18.0, 1e-9));
      for (var i = 1; i < result.length; i++) {
        expect(result[i].frame, greaterThanOrEqualTo(result[i - 1].frame));
      }
    });

    test('노이즈 흡수: 지그재그 입력이 리샘플 후 0.5±0.02 안으로 스무딩된다', () {
      final input = <TrajectorySample>[
        for (var i = 0; i <= 16; i++)
          (
            frame: (i + 2) * 5,
            lane: LanePoint(xM: 0.5 + (i % 2 == 0 ? 0.03 : -0.03), yM: (i + 2).toDouble()),
          ),
      ];

      final result = fitAndResample(input);

      for (final s in result) {
        expect(s.lane.xM, closeTo(0.5, 0.02));
      }
    });

    test('훅 곡선 보존: x(y) = 0.8 - 0.002*(y-2)^2 형태가 0.01 오차 내로 유지된다', () {
      final input = <TrajectorySample>[
        for (var y = 2; y <= 18; y++)
          (
            frame: y * 5,
            lane: LanePoint(xM: 0.8 - 0.002 * (y - 2) * (y - 2), yM: y.toDouble()),
          ),
      ];

      final result = fitAndResample(input);

      for (final s in result) {
        final expectedX = 0.8 - 0.002 * (s.lane.yM - 2) * (s.lane.yM - 2);
        expect(s.lane.xM, closeTo(expectedX, 0.01));
      }
    });

    test('포인트 4개 미만 → 입력 그대로 반환', () {
      final input = <TrajectorySample>[
        (frame: 0, lane: const LanePoint(xM: 0.5, yM: 2.0)),
        (frame: 5, lane: const LanePoint(xM: 0.5, yM: 3.0)),
        (frame: 10, lane: const LanePoint(xM: 0.5, yM: 4.0)),
      ];

      final result = fitAndResample(input);

      expect(result, same(input));
    });

    test('y 범위가 yStepM보다 작으면 피팅 없이 입력 그대로 반환', () {
      final input = <TrajectorySample>[
        (frame: 0, lane: const LanePoint(xM: 0.5, yM: 2.0)),
        (frame: 1, lane: const LanePoint(xM: 0.5, yM: 2.05)),
        (frame: 2, lane: const LanePoint(xM: 0.5, yM: 2.1)),
        (frame: 3, lane: const LanePoint(xM: 0.5, yM: 2.15)),
      ];

      final result = fitAndResample(input, yStepM: 0.25);

      expect(result, same(input));
    });

    test('frame 보간: y 중간값에서 frame이 양옆 원본 frame 사이에 있다', () {
      final input = <TrajectorySample>[
        for (var y = 2; y <= 18; y++) (frame: y * 5, lane: LanePoint(xM: 0.5, yM: y.toDouble())),
      ];

      final result = fitAndResample(input);

      for (final s in result) {
        // 원본 frame 범위: 10 (y=2) ~ 90 (y=18). 대략 frame ≈ y*5 근방이어야 한다.
        expect(s.frame, inInclusiveRange(10, 90));
        final expectedFrame = s.lane.yM * 5;
        expect(s.frame.toDouble(), closeTo(expectedFrame, 1.0));
      }
    });
  });
}
