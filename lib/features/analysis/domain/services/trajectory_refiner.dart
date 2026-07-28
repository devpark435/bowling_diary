import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

/// FSM이 관측한 원시 궤적 표본 하나. frame은 분석 프레임 인덱스, lane은 그
/// 시점의 레인 실측좌표(homography.frameToLane 결과).
typedef TrajectorySample = ({int frame, LanePoint lane});

// 물리적으로 타당한 y(레인 진행방향) 속도 범위. 9~86 km/h에 해당.
const double _minYVelocityMPerFrame = 0.08;
const double _maxYVelocityMPerFrame = 0.8;

/// FSM 원시 궤적(raw)을 오버레이 렌더링용으로 정제한다. 4단계를 순서대로 적용한다:
///
/// 0) 중앙값 프리필터: 검출이 반사광 등으로 가끔 튀어 y가 프레임당 ±0.5m+
///    스파이크를 일으키면, 선두 트림의 "연속 2구간 유효 속도" 조건이 그
///    스파이크 때문에 계속 실패해 궤적 앞부분을 통째로 잘라먹는다. xM/yM
///    각각 중심 3점 이동중앙값(양 끝은 원값 유지, frame 불변)을 적용해
///    고립된 1프레임 스파이크를 제거한다. 손구간처럼 여러 프레임에 걸쳐
///    이어지는 왜곡(연속적 드리프트)은 중앙값을 그대로 통과하므로, 뒤이은
///    선두 트림이 여전히 걸러낸다.
/// 1) 선두 트림: 릴리즈 직후 공이 아직 손 근처(레인 평면 밖)에 있을 때 관측된
///    포인트는 호모그래피 투영이 왜곡돼 y가 물리적으로 말이 안 되게 튄다.
///    연속 두 구간의 y 속도(Δy/Δframe)가 모두 [0.08, 0.8] m/frame(≈9~86km/h)
///    안에 들어오는 첫 지점부터 유효 구간으로 본다. 그런 지점이 없으면
///    트림하지 않는다(원본 그대로 다음 단계로 넘어간다).
/// 2) 단조 필터: 트림 후 첫 포인트를 채택 기준점으로 삼아 순회하며, y가 직전
///    "채택된" 포인트보다 감소하는 포인트는 버린다 — 공은 레인에서 후진하지
///    않으므로 역행 관측은 오검출로 간주한다.
/// 3) x 스무딩: 채택된 포인트들의 xM에 중심 3점 이동평균(양 끝은 원값 유지)을
///    적용해 좌우 지터를 죽인다. yM/frame은 그대로 둔다.
///
/// 포인트가 2개 미만이면 그대로 반환한다.
List<TrajectorySample> refineTrajectory(List<TrajectorySample> raw) {
  if (raw.length < 2) return raw;

  final medianed = _medianPrefilter(raw);
  final trimmed = _trimLeadingDistortion(medianed);
  final monotonic = _filterMonotonic(trimmed);
  return _smoothX(monotonic);
}

/// xM/yM 각각에 중심 3점 이동중앙값을 적용한다(양 끝 점은 원값 유지, frame
/// 불변). 고립된 1프레임 스파이크는 중앙값에서 죽지만, 여러 프레임에 걸친
/// 연속 드리프트는 이웃 두 점도 같이 밀려 있어 중앙값을 통과한다.
List<TrajectorySample> _medianPrefilter(List<TrajectorySample> points) {
  if (points.length < 3) return points;
  final result = <TrajectorySample>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final medianX = _median3(
        points[i - 1].lane.xM, points[i].lane.xM, points[i + 1].lane.xM);
    final medianY = _median3(
        points[i - 1].lane.yM, points[i].lane.yM, points[i + 1].lane.yM);
    result.add((frame: points[i].frame, lane: LanePoint(xM: medianX, yM: medianY)));
  }
  result.add(points.last);
  return result;
}

double _median3(double a, double b, double c) {
  final sorted = [a, b, c]..sort();
  return sorted[1];
}

double _yVelocity(TrajectorySample a, TrajectorySample b) {
  final frameDelta = b.frame - a.frame;
  if (frameDelta <= 0) return double.nan;
  return (b.lane.yM - a.lane.yM) / frameDelta;
}

bool _inValidVelocityRange(double v) =>
    v >= _minYVelocityMPerFrame && v <= _maxYVelocityMPerFrame;

List<TrajectorySample> _trimLeadingDistortion(List<TrajectorySample> raw) {
  for (var i = 0; i + 2 < raw.length; i++) {
    final v1 = _yVelocity(raw[i], raw[i + 1]);
    final v2 = _yVelocity(raw[i + 1], raw[i + 2]);
    if (_inValidVelocityRange(v1) && _inValidVelocityRange(v2)) {
      return raw.sublist(i);
    }
  }
  return raw;
}

List<TrajectorySample> _filterMonotonic(List<TrajectorySample> points) {
  if (points.isEmpty) return points;
  final result = <TrajectorySample>[points.first];
  var lastY = points.first.lane.yM;
  for (var i = 1; i < points.length; i++) {
    final p = points[i];
    if (p.lane.yM < lastY) continue;
    result.add(p);
    lastY = p.lane.yM;
  }
  return result;
}

List<TrajectorySample> _smoothX(List<TrajectorySample> points) {
  if (points.length < 3) return points;
  final result = <TrajectorySample>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final avgX =
        (points[i - 1].lane.xM + points[i].lane.xM + points[i + 1].lane.xM) / 3;
    result.add((frame: points[i].frame, lane: LanePoint(xM: avgX, yM: points[i].lane.yM)));
  }
  result.add(points.last);
  return result;
}
