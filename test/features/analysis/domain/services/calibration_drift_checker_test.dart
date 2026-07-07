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
  return _frameWithMarkers(size, size, markers, offsetX: offsetX, offsetY: offsetY);
}

img.Image _frameWithMarkers(
  int width,
  int height,
  List<FramePoint> markers, {
  int offsetX = 0,
  int offsetY = 0,
  int markerHalf = 8,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(40, 40, 40));
  for (final m in markers) {
    final cx = (m.nx * width).round() + offsetX;
    final cy = (m.ny * height).round() + offsetY;
    for (var dy = -markerHalf; dy <= markerHalf; dy++) {
      for (var dx = -markerHalf; dx <= markerHalf; dx++) {
        final x = cx + dx, y = cy + dy;
        if (x >= 0 && x < width && y >= 0 && y < height) {
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

    group('실제 파이프라인 해상도 (레퍼런스 갤러리 사진 vs ffmpeg 480px 추출 프레임)', () {
      // 캘리브레이션 레퍼런스는 고해상도 갤러리 사진(예: 3024px), 분석 프레임은
      // ffmpeg `scale=480:-1`로 추출된 저해상도 프레임 — 해상도가 완전히 다르다.
      const currentWidth = 480;
      const currentHeight = 270;
      const referenceWidth = currentWidth * 3;
      const referenceHeight = currentHeight * 3;

      test('동일 장면·다른 해상도 → 리사이즈 후 offset ≈0 (ok)', () {
        // 레퍼런스는 3배 고해상도이므로, 다운스케일 후 currentFrame과 같은 물리적
        // 크기로 보이도록 마커도 3배 크게 그린다(실제 사진 속 물체 크기 불변과 동일한 조건).
        final reference = _frameWithMarkers(referenceWidth, referenceHeight, _refPoints, markerHalf: 24);
        final current = _frameWithMarkers(currentWidth, currentHeight, _refPoints);
        final homography = HomographySolver.solve4Point(_refPoints, _lanePoints);
        final sut = CalibrationDriftChecker();

        final result = sut.check(
          referenceFrame: reference,
          currentFrame: current,
          referencePoints: _refPoints,
          homography: homography,
        );

        expect(result.status, DriftStatus.ok);
        expect(result.driftScoreNormalized, lessThan(0.01));
      });

      test('현재 프레임이 백지(마커 없음) → NCC 바닥 미달로 재캘리브레이션 요구', () {
        final reference = _frameWithMarkers(referenceWidth, referenceHeight, _refPoints);
        final blankCurrent = img.Image(width: currentWidth, height: currentHeight);
        img.fill(blankCurrent, color: img.ColorRgb8(40, 40, 40));
        final homography = HomographySolver.solve4Point(_refPoints, _lanePoints);
        final sut = CalibrationDriftChecker();

        final result = sut.check(
          referenceFrame: reference,
          currentFrame: blankCurrent,
          referencePoints: _refPoints,
          homography: homography,
        );

        expect(result.status, DriftStatus.recalibrationRequired);
      });
    });
  });
}
