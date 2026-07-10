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
