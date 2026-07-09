import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/trajectory_refiner.dart';
import 'package:flutter_test/flutter_test.dart';

TrajectorySample _s(int frame, double yM, {double xM = 0.0}) =>
    (frame: frame, lane: LanePoint(xM: xM, yM: yM));

void main() {
  group('refineTrajectory', () {
    test('선두 왜곡 트림: 손 근처 왜곡 포인트를 버리고 유효 구간 첫 지점부터 시작', () {
      final raw = [
        _s(40, 5.0),
        _s(41, 2.4),
        _s(42, 2.55),
        _s(43, 2.8),
        _s(44, 3.05),
        _s(45, 3.3),
      ];

      final result = refineTrajectory(raw);

      expect(result.first.frame, 41);
    });

    test('유효 지점이 없으면 트림하지 않는다(길이 보존)', () {
      final raw = [
        for (var i = 0; i < 6; i++) _s(i, i * 2.0), // 속도 2.0 m/frame, 항상 범위 밖
      ];

      final result = refineTrajectory(raw);

      expect(result.length, raw.length);
      expect(result.first.frame, 0);
    });

    test('단조 필터: 역행(y 감소) 포인트를 드롭한다', () {
      final raw = [
        _s(1, 3.0),
        _s(2, 3.5),
        _s(3, 3.2), // 역행 → 드롭
        _s(4, 4.0),
      ];

      final result = refineTrajectory(raw);

      expect(result.map((e) => e.frame).toList(), [1, 2, 4]);
    });

    test('x 스무딩: 중심 3점 이동평균, 양 끝은 원값 유지', () {
      final raw = [
        _s(1, 3.0, xM: 0.2),
        _s(2, 3.5, xM: 0.5),
        _s(3, 4.0, xM: 0.2),
      ];

      final result = refineTrajectory(raw);

      expect(result[0].lane.xM, closeTo(0.2, 1e-9));
      expect(result[1].lane.xM, closeTo((0.2 + 0.5 + 0.2) / 3, 1e-9));
      expect(result[2].lane.xM, closeTo(0.2, 1e-9));
    });

    test('빈 리스트는 그대로 반환', () {
      expect(refineTrajectory(const []), isEmpty);
    });

    test('1개 포인트 리스트는 그대로 반환', () {
      final raw = [_s(5, 1.0)];
      expect(refineTrajectory(raw), raw);
    });
  });
}
