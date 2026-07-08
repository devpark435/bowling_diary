import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/lane_detection_result.dart';

/// 영상의 첫 프레임에서 레인 4코너(foul-left, foul-right, pin-right, pin-left)를
/// 자동 검출한다. 결과는 항상 사용자 확인/보정 UI를 거친 뒤에만 실제 분석(호모그래피)에
/// 쓰이므로, 이 서비스는 정밀도보다 recall을 우선한다 — 애매하면 "괜찮은 추정"을
/// 반환하고, 유저가 드래그로 보정하게 둔다.
///
/// 알고리즘(순수 Dart, opencv 없음):
///  1. 그레이스케일 + (필요시) 320px 폭으로 다운스케일.
///  2. 행 단위 밝은-구간 스캔: 레인(밝은 나무 바닥)은 좌우 거터(어두움)에 둘러싸인
///     밝은 연속 구간으로 나타난다. 행마다 적응형 임계값(평균 + 0.3*표준편차)으로
///     가장 넓은 연속 구간을 찾는다.
///  3. 연속성 필터: 아래→위로 훑으며 중심이 급격히 튀거나 폭이 급격히 넓어지는
///     레코드는 버린다(원근상 위로 갈수록 좁아지거나 유지되어야 함).
///  4. 좌/우 에지를 각각 x = a*y + b 형태로 최소자승 직선 피팅.
///  5. 파울라인(하단 가로줄)은 레인 영역 하단 40% 구간에서 레인 폭 내부 평균
///     휘도가 중앙값보다 뚜렷하게 어두운 행(국소최소값)으로 찾는다. 못 찾으면
///     최하단 유지 레코드의 y로 대체(품질 하향).
///  6. 핀엔드(상단 가로줄)는 최상단 유지 레코드의 y.
///  7. 두 피팅 직선을 파울라인/핀엔드 y에 대입해 4코너 산출.
///  8. 사다리꼴 유효성(볼록·상단이 하단보다 넓지 않음·최소 하단폭·파울/핀 순서)과
///     피팅 잔차/파울라인 검출 방식/유지 레코드 수로 good/rough/notFound 등급 산출.
class LaneDetectorService {
  // ── 튜닝 상수 (한 곳에 모아둠) ──────────────────────────────────────────
  /// 다운스케일 목표 폭. 원본이 이보다 넓으면 이 폭으로 줄여 그 좌표계에서 계산.
  static const int _maxWorkWidth = 320;
  /// 행 스캔 시작(하단, 프레임 높이 비율).
  static const double _rowScanStartFrac = 0.90;
  /// 행 스캔 종료(상단, 프레임 높이 비율).
  static const double _rowScanEndFrac = 0.15;
  static const int _rowScanStepPx = 2;
  /// 적응형 임계값 = 행 평균 + k * 행 표준편차.
  static const double _adaptiveThresholdK = 0.3;
  /// 유효한 밝은 연속 구간의 최소 폭(프레임 폭 대비).
  static const double _minRunWidthFrac = 0.12;
  /// 연속성 필터: 이전 유지 레코드 대비 중심 이동 허용치(프레임 폭 대비).
  static const double _maxCenterJumpFrac = 0.08;
  /// 연속성 필터: 이전 유지 레코드 대비 폭 증가 허용치(비율).
  static const double _maxWidthGrowthFrac = 0.15;
  /// 진행을 위해 필요한 최소 유지 레코드 수.
  static const int _minKeptRecords = 12;
  /// good 등급을 위한 최소 유지 레코드 수.
  static const int _goodKeptRecords = 25;
  /// 파울라인 탐색 구간 = 레인 영역 수직 범위의 하단 이 비율.
  static const double _foulSectionFrac = 0.40;
  /// 파울라인 판정: 행 평균 휘도가 (구간 중앙값 * 이 값) 미만이면 "어둡다".
  static const double _foulDarkFactor = 0.8;
  /// good 등급을 위한 최대 에지 피팅 RMS 잔차(다운스케일 픽셀 단위).
  static const double _goodRmsPx = 2.5;
  /// 유효성 검사: 최소 하단 폭(프레임 폭 대비).
  static const double _minBottomWidthFrac = 0.20;

  static const List<FramePoint> _defaultTrapezoid = [
    FramePoint(nx: 0.15, ny: 0.85), // foul-left
    FramePoint(nx: 0.85, ny: 0.85), // foul-right
    FramePoint(nx: 0.62, ny: 0.25), // pin-right
    FramePoint(nx: 0.38, ny: 0.25), // pin-left
  ];

  static const LaneDetectionResult _notFoundResult = LaneDetectionResult(
    corners: _defaultTrapezoid,
    quality: LaneDetectionQuality.notFound,
  );

  LaneDetectionResult detect(img.Image frame) {
    final gray = img.grayscale(frame);
    final work = gray.width > _maxWorkWidth ? img.copyResize(gray, width: _maxWorkWidth) : gray;

    final records = _scanRows(work);
    final kept = _filterContinuity(records, work.width.toDouble());
    if (kept.length < _minKeptRecords) return _notFoundResult;

    final ys = kept.map((r) => r.y.toDouble()).toList();
    final leftFit = _fitLine(ys, kept.map((r) => r.xL.toDouble()).toList());
    final rightFit = _fitLine(ys, kept.map((r) => r.xR.toDouble()).toList());

    final yTop = kept.map((r) => r.y).reduce(math.min).toDouble();
    final yBottom = kept.map((r) => r.y).reduce(math.max).toDouble();

    final foulRow = _findFoulRow(work, kept, yTop, yBottom);
    final pinY = yTop;

    final corners = [
      _normalize(leftFit.eval(foulRow.y), foulRow.y, work.width, work.height), // foul-left
      _normalize(rightFit.eval(foulRow.y), foulRow.y, work.width, work.height), // foul-right
      _normalize(rightFit.eval(pinY), pinY, work.width, work.height), // pin-right
      _normalize(leftFit.eval(pinY), pinY, work.width, work.height), // pin-left
    ];

    if (!_isValidQuad(corners)) return _notFoundResult;

    final isGood = leftFit.rms < _goodRmsPx &&
        rightFit.rms < _goodRmsPx &&
        foulRow.viaDarkMinimum &&
        kept.length >= _goodKeptRecords;

    return LaneDetectionResult(
      corners: corners,
      quality: isGood ? LaneDetectionQuality.good : LaneDetectionQuality.rough,
    );
  }

  List<_RowRecord> _scanRows(img.Image work) {
    final width = work.width;
    final height = work.height;
    final startY = (_rowScanStartFrac * height).round().clamp(0, height - 1);
    final endY = (_rowScanEndFrac * height).round().clamp(0, height - 1);
    final minRunWidth = _minRunWidthFrac * width;

    final records = <_RowRecord>[];
    for (var y = startY; y >= endY; y -= _rowScanStepPx) {
      final lum = List<double>.generate(width, (x) => img.getLuminance(work.getPixel(x, y)).toDouble());
      final mean = lum.reduce((a, b) => a + b) / width;
      var variance = 0.0;
      for (final v in lum) {
        variance += (v - mean) * (v - mean);
      }
      variance /= width;
      final threshold = mean + _adaptiveThresholdK * math.sqrt(variance);

      var bestL = -1, bestR = -1, bestWidth = 0;
      var runStart = -1;
      for (var x = 0; x < width; x++) {
        if (lum[x] > threshold) {
          if (runStart == -1) runStart = x;
          final runWidth = x - runStart + 1;
          if (runWidth > bestWidth) {
            bestWidth = runWidth;
            bestL = runStart;
            bestR = x;
          }
        } else {
          runStart = -1;
        }
      }
      if (bestWidth >= minRunWidth) {
        records.add(_RowRecord(y: y, xL: bestL, xR: bestR));
      }
    }
    return records;
  }

  List<_RowRecord> _filterContinuity(List<_RowRecord> records, double width) {
    if (records.isEmpty) return const [];
    final kept = <_RowRecord>[records.first];
    for (var i = 1; i < records.length; i++) {
      final prev = kept.last;
      final cur = records[i];
      final prevCenter = (prev.xL + prev.xR) / 2;
      final curCenter = (cur.xL + cur.xR) / 2;
      final prevWidth = (prev.xR - prev.xL).toDouble();
      final curWidth = (cur.xR - cur.xL).toDouble();
      if ((curCenter - prevCenter).abs() > _maxCenterJumpFrac * width) continue;
      if (curWidth > prevWidth * (1 + _maxWidthGrowthFrac)) continue;
      kept.add(cur);
    }
    return kept;
  }

  _LineFit _fitLine(List<double> ys, List<double> xs) {
    final n = ys.length;
    double sumY = 0, sumX = 0, sumYX = 0, sumYY = 0;
    for (var i = 0; i < n; i++) {
      sumY += ys[i];
      sumX += xs[i];
      sumYX += ys[i] * xs[i];
      sumYY += ys[i] * ys[i];
    }
    final denom = n * sumYY - sumY * sumY;
    double a, b;
    if (denom.abs() < 1e-9) {
      a = 0;
      b = sumX / n;
    } else {
      a = (n * sumYX - sumY * sumX) / denom;
      b = (sumX - a * sumY) / n;
    }
    var sq = 0.0;
    for (var i = 0; i < n; i++) {
      final diff = xs[i] - (a * ys[i] + b);
      sq += diff * diff;
    }
    return _LineFit(a: a, b: b, rms: math.sqrt(sq / n));
  }

  _FoulRowResult _findFoulRow(img.Image work, List<_RowRecord> kept, double yTop, double yBottom) {
    final bottommost = kept.reduce((a, b) => a.y > b.y ? a : b);
    final sectionStart = yBottom - _foulSectionFrac * (yBottom - yTop);
    final candidates = kept.where((r) => r.y >= sectionStart).toList();
    if (candidates.isEmpty) return _FoulRowResult(bottommost.y.toDouble(), false);

    final rowMean = <_RowRecord, double>{};
    for (final r in candidates) {
      double sum = 0;
      var count = 0;
      for (var x = r.xL; x <= r.xR; x++) {
        sum += img.getLuminance(work.getPixel(x, r.y)).toDouble();
        count++;
      }
      rowMean[r] = count > 0 ? sum / count : 0;
    }

    final sortedMeans = rowMean.values.toList()..sort();
    final median = sortedMeans[sortedMeans.length ~/ 2];
    final darkThreshold = median * _foulDarkFactor;

    _RowRecord? best;
    var bestMean = double.infinity;
    for (final entry in rowMean.entries) {
      if (entry.value < darkThreshold && entry.value < bestMean) {
        bestMean = entry.value;
        best = entry.key;
      }
    }

    if (best != null) return _FoulRowResult(best.y.toDouble(), true);
    return _FoulRowResult(bottommost.y.toDouble(), false);
  }

  FramePoint _normalize(double x, double y, int width, int height) {
    return FramePoint(
      nx: (x / width).clamp(0.0, 1.0),
      ny: (y / height).clamp(0.0, 1.0),
    );
  }

  bool _isValidQuad(List<FramePoint> corners) {
    final foulLeft = corners[0];
    final foulRight = corners[1];
    final pinRight = corners[2];
    final pinLeft = corners[3];

    final bottomWidth = (foulRight.nx - foulLeft.nx).abs();
    final topWidth = (pinRight.nx - pinLeft.nx).abs();

    if (bottomWidth < _minBottomWidthFrac) return false;
    if (topWidth > bottomWidth) return false;
    if (foulLeft.ny <= pinLeft.ny) return false; // 파울라인은 핀엔드보다 아래(ny가 커야) 함

    return _isConvex(corners);
  }

  bool _isConvex(List<FramePoint> pts) {
    final n = pts.length;
    double? sign;
    for (var i = 0; i < n; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % n];
      final c = pts[(i + 2) % n];
      final cross = (b.nx - a.nx) * (c.ny - b.ny) - (b.ny - a.ny) * (c.nx - b.nx);
      if (cross.abs() < 1e-12) continue;
      final crossSign = cross.sign;
      if (sign == null) {
        sign = crossSign;
      } else if (crossSign != sign) {
        return false;
      }
    }
    return true;
  }
}

class _RowRecord {
  final int y;
  final int xL;
  final int xR;
  const _RowRecord({required this.y, required this.xL, required this.xR});
}

class _LineFit {
  final double a;
  final double b;
  final double rms;
  const _LineFit({required this.a, required this.b, required this.rms});
  double eval(double y) => a * y + b;
}

class _FoulRowResult {
  final double y;
  final bool viaDarkMinimum;
  const _FoulRowResult(this.y, this.viaDarkMinimum);
}
