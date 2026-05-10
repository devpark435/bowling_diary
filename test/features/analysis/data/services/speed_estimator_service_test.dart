import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
import 'package:bowling_diary/features/analysis/domain/services/homography_solver.dart';
import 'package:flutter_test/flutter_test.dart';

HomographyMatrix _testHomography() {
  // 정규화 (nx, ny) → (nx*1.05, ny*18.29) m 매핑
  return HomographySolver.solve4Point(
    const [
      FramePoint(nx: 0, ny: 0),
      FramePoint(nx: 1, ny: 0),
      FramePoint(nx: 1, ny: 1),
      FramePoint(nx: 0, ny: 1),
    ],
    const [
      LanePoint(xM: 0,    yM: 0),
      LanePoint(xM: 1.05, yM: 0),
      LanePoint(xM: 1.05, yM: 18.29),
      LanePoint(xM: 0,    yM: 18.29),
    ],
  );
}

void main() {
  final svc = SpeedEstimatorService();
  final h = _testHomography();

  group('SpeedEstimatorService', () {
    test('등속 25km/h 시뮬: 측정 정확', () {
      // 25km/h = 6.944 m/s. 30fps → 0.2315m/프레임.
      // y_norm 변화량 (정사각 매핑): 0.2315 / 18.29 = 0.01266 / frame
      final detections = <BallDetection?>[
        for (var i = 0; i < 60; i++)
          BallDetection(
            cx: 0.5,
            cy: 0.05 + i * 0.01266,
            bw: 0.02,
            bh: 0.02,
            confidence: 0.9,
          ),
      ];
      final r = svc.estimate(
        release: const ReleaseResult(frame: 5, confidence: 0.8),
        detections: detections,
        homography: h,
        sampleFps: 30,
      );
      expect(r.kmh, isNotNull);
      expect(r.kmh!, closeTo(25.0, 0.5));
    });

    test('release 없으면 실패', () {
      final r = svc.estimate(
        release: ReleaseResult.notFound,
        detections: const [],
        homography: h,
        sampleFps: 30,
      );
      expect(r.failure, SpeedFailure.releaseNotFound);
    });

    test('비행 윈도우 detections null이면 lowConfidence', () {
      // release+8 ~ release+24 모두 null
      final detections = <BallDetection?>[
        for (var i = 0; i < 30; i++) null,
      ];
      final r = svc.estimate(
        release: const ReleaseResult(frame: 0, confidence: 0.8),
        detections: detections,
        homography: h,
        sampleFps: 30,
      );
      expect(r.failure, SpeedFailure.lowConfidence);
    });

    test('비현실적으로 빠른 속도 outOfRange', () {
      // 100km/h 시뮬 = 27.78 m/s. y_norm 변화량 0.0506/frame
      final detections = <BallDetection?>[
        for (var i = 0; i < 60; i++)
          BallDetection(
            cx: 0.5,
            cy: 0.05 + i * 0.0506,
            bw: 0.02,
            bh: 0.02,
            confidence: 0.9,
          ),
      ];
      final r = svc.estimate(
        release: const ReleaseResult(frame: 5, confidence: 0.8),
        detections: detections,
        homography: h,
        sampleFps: 30,
      );
      expect(r.failure, SpeedFailure.outOfRange);
    });
  });
}
