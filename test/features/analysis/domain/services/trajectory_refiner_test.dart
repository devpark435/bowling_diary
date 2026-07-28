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

      // 중앙값 프리필터가 먼저 적용돼 y가 [5.0, 2.55, 2.55, 2.8, 3.05, 3.3]로
      // 바뀐다. 그 결과 frame41→42 구간 속도(v1)가 0이 되어(범위 밖) 트림이
      // frame42(index2: 2.55→2.8→3.05, v1=v2=0.25로 유효)부터 시작한다.
      expect(result.first.frame, 42);
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

      // 중앙값 프리필터가 먼저 이 고립된 1프레임 역행을 흡수한다:
      // frame2 median(3.0,3.5,3.2)=3.2, frame3 median(3.5,3.2,4.0)=3.5 →
      // y가 [3.0, 3.2, 3.5, 4.0]로 이미 단조증가가 되어 단조 필터에서 드롭될
      // 포인트가 없다(중앙값이 살아남는 것은 여러 프레임에 걸친 연속 역행뿐).
      expect(result.map((e) => e.frame).toList(), [1, 2, 3, 4]);
    });

    test('x 스무딩: 중심 3점 이동평균, 양 끝은 원값 유지', () {
      final raw = [
        _s(1, 3.0, xM: 0.2),
        _s(2, 3.5, xM: 0.5),
        _s(3, 4.0, xM: 0.2),
      ];

      final result = refineTrajectory(raw);

      // 중앙값 프리필터가 먼저 middle x를 median(0.2, 0.5, 0.2)=0.2로 바꾼다
      // (y는 이미 단조증가라 무영향). smoothX는 그 뒤에 적용되므로 세 점의
      // xM이 모두 0.2가 된 상태에서 평균을 내 여전히 0.2가 나온다.
      expect(result[0].lane.xM, closeTo(0.2, 1e-9));
      expect(result[1].lane.xM, closeTo(0.2, 1e-9));
      expect(result[2].lane.xM, closeTo(0.2, 1e-9));
    });

    test('빈 리스트는 그대로 반환', () {
      expect(refineTrajectory(const []), isEmpty);
    });

    test('1개 포인트 리스트는 그대로 반환', () {
      final raw = [_s(5, 1.0)];
      expect(refineTrajectory(raw), raw);
    });

    test('중앙값 프리필터: 고립 스파이크를 흡수해 선두 트림이 과도하게 잘라내지 않는다', () {
      final raw = [
        _s(1, 2.4, xM: 0.5),
        _s(2, 2.6, xM: 0.5),
        _s(3, 5.8, xM: 0.5), // 고립 스파이크(반사광 등 오검출) — 프레임당 +3.2m
        _s(4, 2.8, xM: 0.5),
        _s(5, 3.0, xM: 0.5),
        _s(6, 3.2, xM: 0.5),
      ];

      final result = refineTrajectory(raw);

      // 중앙값 통과 후 y=[2.4, 2.6, 2.8, 3.0, 3.0, 3.2] — 스파이크가 사라지고
      // 속도가 전 구간 유효 범위 안에 들어와 트림이 발생하지 않는다.
      expect(result.length, 6);
      expect(result.first.frame, 1);
      expect(result.map((e) => e.lane.yM), isNot(contains(5.8)));
    });

    test('단조 필터: 중앙값을 살아남는 다프레임 연속 역행은 드롭한다', () {
      final raw = [
        _s(1, 2.0, xM: 0.5),
        _s(2, 2.2, xM: 0.5),
        _s(3, 2.4, xM: 0.5),
        _s(4, 2.6, xM: 0.5),
        _s(5, 2.8, xM: 0.5),
        _s(6, 2.5, xM: 0.5), // 2프레임 연속 역행 — 고립 스파이크가 아니라
        _s(7, 2.45, xM: 0.5), // 중앙값 프리필터로 흡수되지 않는다
        _s(8, 3.4, xM: 0.5),
        _s(9, 3.6, xM: 0.5),
        _s(10, 3.8, xM: 0.5),
      ];

      final result = refineTrajectory(raw);

      // 중앙값 통과 후 y=[2.0, 2.2, 2.4, 2.6, 2.6, 2.5, 2.5, 3.4, 3.6, 3.8]
      // — 역행이 여전히 남는다(2.6→2.5). 선두 트림은 v0=v1=0.2로 유효해
      // 자르지 않고, 단조 필터가 frame 6·7(2.5 < 직전 채택 2.6)을 드롭한다.
      expect(result.map((e) => e.frame).toList(), [1, 2, 3, 4, 5, 8, 9, 10]);
      final ys = result.map((e) => e.lane.yM).toList();
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThanOrEqualTo(ys[i - 1]));
      }
    });

    test('중앙값 프리필터는 궤적의 양 끝 점을 원값 그대로 유지한다', () {
      final raw = [
        _s(1, 2.4, xM: 0.5),
        _s(2, 2.6, xM: 0.5),
        _s(3, 5.8, xM: 0.5), // 고립 스파이크
        _s(4, 2.8, xM: 0.5),
        _s(5, 3.0, xM: 0.5),
        _s(6, 3.2, xM: 0.5),
      ];

      final result = refineTrajectory(raw);

      // 중앙값 필터는 이웃이 하나뿐인 양 끝 점은 건드리지 않고, 트림/단조
      // 필터도 이 데이터에서는 아무것도 버리지 않으므로 첫/마지막 점이
      // raw와 정확히 동일해야 한다(스무딩은 x에 한해 내부 점만 바꾼다).
      expect(result.first, raw.first);
      expect(result.last, raw.last);
    });
  });
}
