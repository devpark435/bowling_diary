import 'dart:math' as math;

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/trajectory_refiner.dart';

/// 정제된 궤적(y 단조증가 가정)을 레인 좌표에서 3차 최소제곱 x(y) 곡선으로
/// 피팅한 뒤 [yStepM] 간격으로 균일 리샘플한다. 검출 지터로 각진 폴리라인
/// 대신 매끈한 곡선(직진 구간 + 훅)을 얻는다 — 볼링 궤적은 3차로 충분.
/// frame은 원본 포인트들의 y→frame 구간선형 보간으로 유도(진행 공개
/// 렌더링용). 포인트가 4개 미만이거나 y 범위가 [yStepM]보다 작으면
/// 피팅 없이 입력을 그대로 반환한다.
List<TrajectorySample> fitAndResample(
  List<TrajectorySample> refined, {
  double yStepM = 0.25,
}) {
  if (refined.length < 4) return refined;

  final yMin = refined.first.lane.yM;
  final yMax = refined.last.lane.yM;
  final yRange = yMax - yMin;
  if (yRange < yStepM) return refined;

  // 정규방정식(4x4) 구성: x = a0 + a1*t + a2*t^2 + a3*t^3, t = (y - yMin)/yRange.
  final ata = List.generate(4, (_) => List<double>.filled(4, 0.0));
  final atx = List<double>.filled(4, 0.0);

  for (final s in refined) {
    final t = (s.lane.yM - yMin) / yRange;
    final powers = [1.0, t, t * t, t * t * t];
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        ata[i][j] += powers[i] * powers[j];
      }
      atx[i] += powers[i] * s.lane.xM;
    }
  }

  final coeffs = _solve4x4(ata, atx);
  if (coeffs == null || coeffs.any((c) => !c.isFinite)) {
    return refined;
  }

  final ys = <double>[];
  var y = yMin;
  while (y < yMax - 1e-9) {
    ys.add(y);
    y += yStepM;
  }
  ys.add(yMax);

  final result = <TrajectorySample>[];
  for (final yy in ys) {
    final t = (yy - yMin) / yRange;
    final x = coeffs[0] + coeffs[1] * t + coeffs[2] * t * t + coeffs[3] * t * t * t;
    final frame = _interpolateFrame(refined, yy);
    result.add((frame: frame, lane: LanePoint(xM: x, yM: yy)));
  }
  return result;
}

/// 리샘플된 곡선을 시작 방향(파울라인 쪽)으로 선형 연장한다.
///
/// 정제 단계가 초반 구간의 지속적 검출 노이즈를 잘라내면 곡선이 레인
/// 중간(실측 8m대)부터 시작해 선 앞 절반이 비어 보인다. 릴리즈 직후
/// 2~8m는 스키드 구간이라 물리적으로 직선에 가깝므로, 곡선 시작점의
/// 기울기(dx/dy, dframe/dy)를 그대로 [targetStartY]까지 [yStepM] 간격으로
/// 늘린다. 3차식 자체를 데이터 범위 밖으로 외삽하면 꼬리가 요동치므로
/// 선형만 쓴다. xM은 레인 폭(0~1.05m), frame은 0 이상으로 클램프.
///
/// 곡선이 이미 [targetStartY] 이하에서 시작하거나 포인트가 2개 미만이면
/// 그대로 반환한다.
List<TrajectorySample> extendCurveStart(
  List<TrajectorySample> curve, {
  required double targetStartY,
  double yStepM = 0.25,
}) {
  if (curve.length < 2) return curve;
  final first = curve.first;
  final second = curve[1];
  final dy = second.lane.yM - first.lane.yM;
  if (dy <= 0 || first.lane.yM <= targetStartY + 1e-9) return curve;

  final dxPerY = (second.lane.xM - first.lane.xM) / dy;
  final dfPerY = (second.frame - first.frame) / dy;

  final prefix = <TrajectorySample>[];
  var y = first.lane.yM - yStepM;
  while (y > targetStartY + 1e-9) {
    prefix.add(_extrapolated(first, y, dxPerY, dfPerY));
    y -= yStepM;
  }
  prefix.add(_extrapolated(first, targetStartY, dxPerY, dfPerY));

  return [...prefix.reversed, ...curve];
}

/// 리샘플된 곡선을 끝 방향(핀덱 쪽)으로 선형 연장한다.
///
/// 원거리(17m+)에서는 공이 화면상 수 픽셀이라 검출이 끊겨 곡선이 핀
/// 직전에서 멈춘다(실측: 17.1m에서 종료 — 레인의 94%). 마지막 추적점이
/// [minLastY] 이상이면(공이 핀을 향하고 있음이 명백) 끝 기울기를
/// [targetEndY]까지 그대로 늘린다. [minLastY] 미만이면 중간 유실일 수
/// 있으므로 날조하지 않는다. 시작 연장(extendCurveStart)과 대칭.
List<TrajectorySample> extendCurveEnd(
  List<TrajectorySample> curve, {
  required double targetEndY,
  double yStepM = 0.25,
  double minLastY = 14.0,
}) {
  if (curve.length < 2) return curve;
  final last = curve.last;
  final secondLast = curve[curve.length - 2];
  if (last.lane.yM >= targetEndY - 1e-9) return curve;
  if (last.lane.yM < minLastY) return curve;

  final dy = last.lane.yM - secondLast.lane.yM;
  if (dy <= 0) return curve;

  final dxPerY = (last.lane.xM - secondLast.lane.xM) / dy;
  final dfPerY = (last.frame - secondLast.frame) / dy;

  final suffix = <TrajectorySample>[];
  var prevFrame = last.frame;
  var y = last.lane.yM + yStepM;
  while (y < targetEndY - 1e-9) {
    final sample = _extrapolatedForward(last, y, dxPerY, dfPerY, prevFrame);
    suffix.add(sample);
    prevFrame = sample.frame;
    y += yStepM;
  }
  suffix.add(_extrapolatedForward(last, targetEndY, dxPerY, dfPerY, prevFrame));

  return [...curve, ...suffix];
}

TrajectorySample _extrapolatedForward(
  TrajectorySample anchor,
  double y,
  double dxPerY,
  double dfPerY,
  int prevFrame,
) {
  final ahead = y - anchor.lane.yM;
  final x = (anchor.lane.xM + dxPerY * ahead).clamp(0.0, 1.05);
  final frame = (anchor.frame + dfPerY * ahead).round().clamp(prevFrame, 1 << 30);
  return (frame: frame, lane: LanePoint(xM: x, yM: y));
}

TrajectorySample _extrapolated(
  TrajectorySample anchor,
  double y,
  double dxPerY,
  double dfPerY,
) {
  final back = anchor.lane.yM - y;
  final x = (anchor.lane.xM - dxPerY * back).clamp(0.0, 1.05);
  final frame = (anchor.frame - dfPerY * back).round().clamp(0, 1 << 30);
  return (frame: frame, lane: LanePoint(xM: x, yM: y));
}

/// 피팅·리샘플된 곡선의 끝(핀덱 쪽) 진입각(도).
///
/// 마지막 두 샘플의 atan2(|Δx|, Δy)를 도 단위로 환산한다 — 통상 3~6°.
/// 주의: x/y가 캘리브레이션 좌표라 스케일 왜곡의 영향을 받는다. 구속
/// (이벤트-시간, 스케일 불변)과 달리 참고치 성격이다. 샘플 2개 미만이거나
/// 끝 구간이 전진(Δy>0)이 아니면 null.
double? entryAngleDeg(List<TrajectorySample> curve) {
  if (curve.length < 2) return null;
  final last = curve.last;
  final prev = curve[curve.length - 2];
  final dy = last.lane.yM - prev.lane.yM;
  if (dy <= 0) return null;
  final dx = (last.lane.xM - prev.lane.xM).abs();
  return math.atan2(dx, dy) * 180 / math.pi;
}

/// [points]는 frame 오름차순, y 단조증가로 가정. [y]를 감싸는 원본 구간을 찾아
/// frame을 구간선형 보간(round)한다. 범위 밖이면 경계값으로 클램프한다.
int _interpolateFrame(List<TrajectorySample> points, double y) {
  if (y <= points.first.lane.yM) return points.first.frame;
  if (y >= points.last.lane.yM) return points.last.frame;

  for (var i = 0; i < points.length - 1; i++) {
    final y0 = points[i].lane.yM;
    final y1 = points[i + 1].lane.yM;
    if (y >= y0 && y <= y1) {
      if (y1 == y0) return points[i].frame;
      final f0 = points[i].frame;
      final f1 = points[i + 1].frame;
      final ratio = (y - y0) / (y1 - y0);
      return (f0 + (f1 - f0) * ratio).round();
    }
  }
  return points.last.frame;
}

/// 부분 피벗을 사용한 가우스 소거로 4x4 연립방정식 a*x = b를 푼다. 특이하거나
/// 피벗이 수치적으로 0에 가까우면(계수 산출 불가) null을 반환한다.
List<double>? _solve4x4(List<List<double>> a, List<double> b) {
  final m = List.generate(4, (i) => List<double>.from(a[i]));
  final v = List<double>.from(b);

  for (var col = 0; col < 4; col++) {
    var pivotRow = col;
    var maxVal = m[col][col].abs();
    for (var row = col + 1; row < 4; row++) {
      if (m[row][col].abs() > maxVal) {
        maxVal = m[row][col].abs();
        pivotRow = row;
      }
    }
    if (maxVal < 1e-12) return null;
    if (pivotRow != col) {
      final tmpRow = m[col];
      m[col] = m[pivotRow];
      m[pivotRow] = tmpRow;
      final tmpV = v[col];
      v[col] = v[pivotRow];
      v[pivotRow] = tmpV;
    }
    for (var row = col + 1; row < 4; row++) {
      final factor = m[row][col] / m[col][col];
      if (factor == 0) continue;
      for (var k = col; k < 4; k++) {
        m[row][k] -= factor * m[col][k];
      }
      v[row] -= factor * v[col];
    }
  }

  final x = List<double>.filled(4, 0.0);
  for (var row = 3; row >= 0; row--) {
    var sum = v[row];
    for (var k = row + 1; k < 4; k++) {
      sum -= m[row][k] * x[k];
    }
    x[row] = sum / m[row][row];
  }
  return x;
}
