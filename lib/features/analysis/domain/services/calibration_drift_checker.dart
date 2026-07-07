import 'dart:math' show sqrt;

import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/drift_check_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/services/homography_solver.dart';

class CalibrationDriftChecker {
  static const int _patchHalf = 15; // 31x31 패치
  static const int _searchRadius = 12;
  static const double _autoCorrectThreshold = 0.01; // 프레임 대각선의 1%
  static const double _recalibrationThreshold = 0.05; // 프레임 대각선의 5%

  DriftCheckResult check({
    required img.Image referenceFrame,
    required img.Image currentFrame,
    required List<FramePoint> referencePoints,
    required HomographyMatrix homography,
  }) {
    if (referencePoints.length != 4) {
      throw ArgumentError('캘리브레이션 기준점은 4개여야 합니다. 현재: ${referencePoints.length}');
    }

    final refGray = img.grayscale(referenceFrame);
    final curGray = img.grayscale(currentFrame);
    final diagonal = sqrt(
      currentFrame.width * currentFrame.width + currentFrame.height * currentFrame.height.toDouble(),
    );

    final measuredPoints = <FramePoint>[];
    double totalOffset = 0;

    for (final refPoint in referencePoints) {
      final refX = (refPoint.nx * referenceFrame.width).round();
      final refY = (refPoint.ny * referenceFrame.height).round();

      var bestDx = 0;
      var bestDy = 0;
      var bestScore = double.negativeInfinity;

      for (var dy = -_searchRadius; dy <= _searchRadius; dy++) {
        for (var dx = -_searchRadius; dx <= _searchRadius; dx++) {
          final candX = refX + dx;
          final candY = refY + dy;
          if (!_patchFits(candX, candY, curGray.width, curGray.height)) continue;
          final score = _patchNcc(refGray, refX, refY, curGray, candX, candY);
          if (score > bestScore) {
            bestScore = score;
            bestDx = dx;
            bestDy = dy;
          }
        }
      }

      final offsetPx = sqrt((bestDx * bestDx + bestDy * bestDy).toDouble());
      totalOffset += offsetPx;

      final movedX = (refX + bestDx) / currentFrame.width;
      final movedY = (refY + bestDy) / currentFrame.height;
      measuredPoints.add(FramePoint(nx: movedX, ny: movedY));
    }

    final avgOffsetPx = totalOffset / referencePoints.length;
    final driftScoreNormalized = avgOffsetPx / diagonal;

    if (driftScoreNormalized < _autoCorrectThreshold) {
      return DriftCheckResult(
        status: DriftStatus.ok,
        homography: homography,
        driftScoreNormalized: driftScoreNormalized,
      );
    }

    if (driftScoreNormalized <= _recalibrationThreshold) {
      final laneCorners = referencePoints
          .map((p) => homography.frameToLane(p))
          .toList();
      final corrected = HomographySolver.solve4Point(measuredPoints, laneCorners);
      return DriftCheckResult(
        status: DriftStatus.autoCorrected,
        homography: corrected,
        driftScoreNormalized: driftScoreNormalized,
      );
    }

    return DriftCheckResult(
      status: DriftStatus.recalibrationRequired,
      homography: homography,
      driftScoreNormalized: driftScoreNormalized,
    );
  }

  bool _patchFits(int cx, int cy, int width, int height) {
    return cx - _patchHalf >= 0 &&
        cx + _patchHalf < width &&
        cy - _patchHalf >= 0 &&
        cy + _patchHalf < height;
  }

  double _patchNcc(img.Image a, int ax, int ay, img.Image b, int bx, int by) {
    if (!_patchFits(ax, ay, a.width, a.height)) return double.negativeInfinity;
    double sumA = 0, sumB = 0, sumAB = 0, sumA2 = 0, sumB2 = 0;
    var n = 0;
    for (var dy = -_patchHalf; dy <= _patchHalf; dy++) {
      for (var dx = -_patchHalf; dx <= _patchHalf; dx++) {
        final va = img.getLuminance(a.getPixel(ax + dx, ay + dy)).toDouble();
        final vb = img.getLuminance(b.getPixel(bx + dx, by + dy)).toDouble();
        sumA += va;
        sumB += vb;
        sumAB += va * vb;
        sumA2 += va * va;
        sumB2 += vb * vb;
        n++;
      }
    }
    final meanA = sumA / n;
    final meanB = sumB / n;
    final numerator = sumAB - n * meanA * meanB;
    final denomA = sumA2 - n * meanA * meanA;
    final denomB = sumB2 - n * meanB * meanB;
    final denom = sqrt(denomA * denomB);
    if (denom < 1e-6) return 0.0;
    return numerator / denom;
  }
}
