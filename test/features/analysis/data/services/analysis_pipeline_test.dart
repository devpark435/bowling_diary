import 'package:bowling_diary/features/analysis/data/services/analysis_pipeline.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
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

img.Image _blankFrame() {
  final image = img.Image(width: 20, height: 20);
  img.fill(image, color: img.ColorRgb8(10, 10, 10));
  return image;
}

void main() {
  // 이 영상 전용으로 산출됐다고 가정하는 identity에 가까운 호모그래피(단위 정사각형 →
  // 레인 실측 좌표). 저장형 프로파일이 사라졌으므로 매 실행마다 이렇게 직접 구성된다.
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

  test('프레임이 하나도 추출되지 않으면 lowConfidence speedFailure로 반환', () async {
    final pipeline = AnalysisPipeline(
      frameExtractor: _FakeFrameExtractor(
        const FrameExtractionResult(frames: [], originalFps: 30, sampleFps: 30),
      ),
      ballDetector: _FakeBallDetector(const []),
      releaseDetector: ReleaseDetectorService(),
      impactDetector: ImpactDetectorService(pinImpactDetector: PinImpactDetectorService()),
      speedEstimator: SpeedEstimatorService(),
    );

    final result = await pipeline.run('fake.mp4', homography);

    expect(result.framesAnalyzed, 0);
    expect(result.speedFailure, SpeedFailure.lowConfidence);
  });

  test('알려진 호모그래피가 파이프라인 전체(검출→릴리즈→임팩트→속도)를 흘러 통과한다', () async {
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
    );

    final result = await pipeline.run('fake.mp4', homography);

    expect(result.framesAnalyzed, detections.length);
  });
}
