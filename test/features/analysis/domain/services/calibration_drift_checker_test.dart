import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/drift_check_result.dart';
import 'package:bowling_diary/features/analysis/domain/services/calibration_drift_checker.dart';
import 'package:bowling_diary/features/analysis/domain/services/homography_solver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _refPoints = [
  FramePoint(nx: 0.2, ny: 0.2), FramePoint(nx: 0.8, ny: 0.2),
  FramePoint(nx: 0.8, ny: 0.8), FramePoint(nx: 0.2, ny: 0.8),
];
const _lanePoints = [
  LanePoint(xM: 0, yM: 0), LanePoint(xM: 1.05, yM: 0),
  LanePoint(xM: 1.05, yM: 18.29), LanePoint(xM: 0, yM: 18.29),
];

img.Image _checkerboardWithMarkers(int size, List<FramePoint> markers, {int offsetX = 0, int offsetY = 0}) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(40, 40, 40));
  for (final m in markers) {
    final cx = (m.nx * size).round() + offsetX;
    final cy = (m.ny * size).round() + offsetY;
    for (var dy = -8; dy <= 8; dy++) {
      for (var dx = -8; dx <= 8; dx++) {
        final x = cx + dx, y = cy + dy;
        if (x >= 0 && x < size && y >= 0 && y < size) {
          image.setPixelRgb(x, y, 240, 240, 240);
        }
      }
    }
  }
  return image;
}

void main() {
  group('CalibrationDriftChecker', () {
    test('동일 프레임 비교 시 drift 없음(ok)', () {
      final frame = _checkerboardWithMarkers(200, _refPoints);
      final homography = HomographySolver.solve4Point(_refPoints, _lanePoints);
      final sut = CalibrationDriftChecker();

      final result = sut.check(
        referenceFrame: frame,
        currentFrame: frame,
        referencePoints: _refPoints,
        homography: homography,
      );

      expect(result.status, DriftStatus.ok);
      expect(result.driftScoreNormalized, lessThan(0.01));
    });

    test('작은 오프셋(3px)은 자동보정(autoCorrected)', () {
      final reference = _checkerboardWithMarkers(200, _refPoints);
      final current = _checkerboardWithMarkers(200, _refPoints, offsetX: 3, offsetY: 3);
      final homography = HomographySolver.solve4Point(_refPoints, _lanePoints);
      final sut = CalibrationDriftChecker();

      final result = sut.check(
        referenceFrame: reference,
        currentFrame: current,
        referencePoints: _refPoints,
        homography: homography,
      );

      expect(result.status, DriftStatus.autoCorrected);
    });

    test('큰 오프셋(40px)은 재캘리브레이션 요구', () {
      final reference = _checkerboardWithMarkers(200, _refPoints);
      final current = _checkerboardWithMarkers(200, _refPoints, offsetX: 40, offsetY: 40);
      final homography = HomographySolver.solve4Point(_refPoints, _lanePoints);
      final sut = CalibrationDriftChecker();

      final result = sut.check(
        referenceFrame: reference,
        currentFrame: current,
        referencePoints: _refPoints,
        homography: homography,
      );

      expect(result.status, DriftStatus.recalibrationRequired);
    });
  });
}
