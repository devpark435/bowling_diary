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
  // NCC 최저 기준. 이 아래면 "매칭됐다"고 볼 수 없는 잡음/오매칭 — 카메라가
  // 크게 움직였거나 장면이 바뀐 상황과 구분이 안 되므로 재캘리브레이션으로 취급한다.
  static const double _nccFloor = 0.5;
  // 탐색 범위 경계(최대 offset)에서 최적점이 나오면, 진짜 최적점이 탐색창 밖에
  // 있을 가능성이 높다는 뜻 — 이 역시 신뢰 불가로 취급한다.
  static const int _unreliablePointsForRecalibration = 2;

  DriftCheckResult check({
    required img.Image referenceFrame,
    required img.Image currentFrame,
    required List<FramePoint> referencePoints,
    required HomographyMatrix homography,
  }) {
    if (referencePoints.length != 4) {
      throw ArgumentError('캘리브레이션 기준점은 4개여야 합니다. 현재: ${referencePoints.length}');
    }

    // 레퍼런스 이미지(캘리브레이션 시점 원본, 예: 갤러리 사진 3024px 폭)와 현재 프레임
    // (ffmpeg로 추출된 분석 프레임, 예: 480px 폭)은 해상도가 다른 것이 일반적이다.
    // 기준점은 정규화 좌표(nx/ny)로 저장되므로, 두 이미지를 같은 크기로 맞춰야만
    // 픽셀 좌표가 서로 비교 가능해진다 — 여기서 리사이즈해 알고리즘 경계에서 불변식을 보장한다.
    final resizedReference = (referenceFrame.width != currentFrame.width ||
            referenceFrame.height != currentFrame.height)
        ? img.copyResize(referenceFrame, width: currentFrame.width, height: currentFrame.height)
        : referenceFrame;

    final refGray = img.grayscale(resizedReference);
    final curGray = img.grayscale(currentFrame);
    final diagonal = sqrt(
      currentFrame.width * currentFrame.width + currentFrame.height * currentFrame.height.toDouble(),
    );

    final measuredPoints = <FramePoint>[];
    double totalOffset = 0;
    var unreliableCount = 0;

    for (final refPoint in referencePoints) {
      final refX = (refPoint.nx * resizedReference.width).round();
      final refY = (refPoint.ny * resizedReference.height).round();

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

      // 최적 매칭 품질이 낮거나(NCC 바닥 미만), 탐색창 경계에서 최적점이 나온 경우
      // (=진짜 매칭이 탐색 범위 밖에 있을 가능성) 이 포인트는 신뢰할 수 없다.
      final atSearchBoundary = bestDx.abs() == _searchRadius || bestDy.abs() == _searchRadius;
      if (bestScore < _nccFloor || atSearchBoundary) {
        unreliableCount++;
      }

      final offsetPx = sqrt((bestDx * bestDx + bestDy * bestDy).toDouble());
      totalOffset += offsetPx;

      final movedX = (refX + bestDx) / currentFrame.width;
      final movedY = (refY + bestDy) / currentFrame.height;
      measuredPoints.add(FramePoint(nx: movedX, ny: movedY));
    }

    final avgOffsetPx = totalOffset / referencePoints.length;
    final driftScoreNormalized = avgOffsetPx / diagonal;

    // 측정 가능한 최대 offset은 탐색 반경(≈17px)으로 제한되므로, 그 안에서 계산된
    // driftScoreNormalized만으로는 "재캘리브레이션 필요"에 절대 도달할 수 없다.
    // 신뢰 불가 포인트가 다수면 오프셋 크기와 무관하게 재캘리브레이션으로 판단한다.
    if (unreliableCount >= _unreliablePointsForRecalibration) {
      return DriftCheckResult(
        status: DriftStatus.recalibrationRequired,
        homography: homography,
        driftScoreNormalized: driftScoreNormalized,
      );
    }

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
