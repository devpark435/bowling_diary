import 'package:bowling_diary/features/analysis/data/services/analysis_pipeline.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/drift_check_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/services/calibration_drift_checker.dart';
import 'package:bowling_diary/features/analysis/domain/services/homography_solver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _FakeFrameExtractor implements VideoFrameExtractorService {
  final FrameExtractionResult result;
  _FakeFrameExtractor(this.result);
  @override
  Future<FrameExtractionResult> extract(String videoPath) async => result;
}

class _FakeBallDetector implements BallDetectionService {
  final List<BallDetection?> sequence;
  int _i = 0;
  _FakeBallDetector(this.sequence);
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
  @override
  BallDetection? detect(img.Image frame) => _i < sequence.length ? sequence[_i++] : null;
}

class _FakeDriftChecker implements CalibrationDriftChecker {
  final DriftCheckResult result;
  _FakeDriftChecker(this.result);
  @override
  DriftCheckResult check({
    required img.Image referenceFrame,
    required img.Image currentFrame,
    required List<FramePoint> referencePoints,
    required HomographyMatrix homography,
  }) => result;
}

img.Image _blankFrame() {
  final image = img.Image(width: 20, height: 20);
  img.fill(image, color: img.ColorRgb8(10, 10, 10));
  return image;
}

CalibrationProfile _profile(homography) => CalibrationProfile(
      id: 'p1', name: '테스트', viewpoint: CameraViewpoint.backRight,
      homography: homography, createdAt: DateTime(2026, 1, 1),
      referenceImagePath: '/tmp/ref.jpg',
      framePoints: const [
        FramePoint(nx: 0, ny: 0), FramePoint(nx: 1, ny: 0),
        FramePoint(nx: 1, ny: 1), FramePoint(nx: 0, ny: 1),
      ],
    );

void main() {
  final homography = HomographySolver.solve4Point(
    const [
      FramePoint(nx: 0, ny: 0), FramePoint(nx: 1, ny: 0),
      FramePoint(nx: 1, ny: 1), FramePoint(nx: 0, ny: 1),
    ],
    const [
      LanePoint(xM: 0, yM: 0), LanePoint(xM: 1.05, yM: 0),
      LanePoint(xM: 1.05, yM: 18.29), LanePoint(xM: 0, yM: 18.29),
    ],
  );

  test('drift가 recalibrationRequired면 파이프라인은 검출을 돌리지 않고 즉시 반환', () async {
    final frames = List.generate(5, (_) => _blankFrame());
    final pipeline = AnalysisPipeline(
      frameExtractor: _FakeFrameExtractor(
        FrameExtractionResult(frames: frames, originalFps: 30, sampleFps: 30),
      ),
      ballDetector: _FakeBallDetector(List.filled(5, null)),
      releaseDetector: ReleaseDetectorService(),
      impactDetector: ImpactDetectorService(pinImpactDetector: PinImpactDetectorService()),
      speedEstimator: SpeedEstimatorService(),
      driftChecker: _FakeDriftChecker(
        DriftCheckResult(
          status: DriftStatus.recalibrationRequired,
          homography: homography,
          driftScoreNormalized: 0.2,
        ),
      ),
    );

    final result = await pipeline.run('fake.mp4', _profile(homography), 30);

    expect(result.driftStatus, DriftStatus.recalibrationRequired);
    expect(result.speedKmh, isNull);
    expect(result.framesAnalyzed, 0);
  });

  test('drift가 ok면 detection→release→impact→speed 전체 파이프라인 실행', () async {
    final detections = <BallDetection?>[
      for (var i = 0; i < 60; i++) BallDetection(cx: 0.5, cy: 0.05 + i * 0.01266, bw: 0.02 + (i < 20 ? i * 0.001 : 0), bh: 0.02, confidence: 0.9),
    ];
    final frames = List.generate(detections.length, (_) => _blankFrame());
    final pipeline = AnalysisPipeline(
      frameExtractor: _FakeFrameExtractor(
        FrameExtractionResult(frames: frames, originalFps: 30, sampleFps: 30),
      ),
      ballDetector: _FakeBallDetector(detections),
      releaseDetector: ReleaseDetectorService(),
      impactDetector: ImpactDetectorService(pinImpactDetector: PinImpactDetectorService()),
      speedEstimator: SpeedEstimatorService(),
      driftChecker: _FakeDriftChecker(
        DriftCheckResult(status: DriftStatus.ok, homography: homography, driftScoreNormalized: 0.0),
      ),
    );

    final result = await pipeline.run('fake.mp4', _profile(homography), 30);

    expect(result.driftStatus, DriftStatus.ok);
    expect(result.framesAnalyzed, detections.length);
  });
}
