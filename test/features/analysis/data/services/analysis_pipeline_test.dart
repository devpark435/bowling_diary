import 'dart:ui';

import 'package:bowling_diary/features/analysis/data/services/analysis_pipeline.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/rpm_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/rpm_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
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
  BallDetection? detect(img.Image frame) =>
      _i < sequence.length ? sequence[_i++] : null;
}

class _FakeRelease implements ReleaseDetectorService {
  final ReleaseResult result;
  _FakeRelease(this.result);
  @override
  ReleaseResult findRelease(List<BallDetection?> detections) => result;
}

class _FakeImpact implements PinImpactDetectorService {
  final ImpactResult result;
  _FakeImpact(this.result);
  @override
  ImpactResult findImpact(
    List<img.Image> frames,
    List<BallDetection?> detections,
    int releaseFrame,
  ) =>
      result;
}

class _FakeRpm implements RpmEstimatorService {
  final RpmResult result;
  _FakeRpm(this.result);
  @override
  RpmResult estimate({
    required List<img.Image> frames,
    required List<BallDetection?> detections,
    required int releaseFrame,
    required int sampleFps,
  }) =>
      result;
}

void main() {
  test('정상 경로 — speed/rpm 모두 산출', () async {
    final frames = List.generate(30, (_) => img.Image(width: 10, height: 10));
    final detections = List<BallDetection?>.generate(30, (_) => null);

    final pipeline = AnalysisPipeline(
      frameExtractor: _FakeFrameExtractor(FrameExtractionResult(
          frames: frames, originalFps: 30, sampleFps: 30)),
      ballDetector: _FakeBallDetector(detections),
      releaseDetector:
          _FakeRelease(const ReleaseResult(frame: 0, confidence: 1.0)),
      impactDetector: _FakeImpact(ImpactResult(
          frame: 60, roi: const Rect.fromLTWH(0, 0, 10, 10), confidence: 1.0)),
      speedEstimator: SpeedEstimatorService(),
      rpmEstimator: _FakeRpm(RpmResult.success(280, 0.9)),
    );

    final data = await pipeline.run('dummy.mp4', 30);
    expect(data.speedKmh, isNotNull);
    expect(data.rpmEstimated, equals(280));
    expect(data.speedFailure, isNull);
    expect(data.rpmFailure, isNull);
  });

  test('동일 입력 → 동일 AnalysisData (결정성)', () async {
    final frames = List.generate(30, (_) => img.Image(width: 10, height: 10));
    final detections = List<BallDetection?>.generate(30, (_) => null);

    AnalysisPipeline build() => AnalysisPipeline(
          frameExtractor: _FakeFrameExtractor(FrameExtractionResult(
              frames: frames, originalFps: 30, sampleFps: 30)),
          ballDetector: _FakeBallDetector(detections),
          releaseDetector:
              _FakeRelease(const ReleaseResult(frame: 5, confidence: 1.0)),
          impactDetector: _FakeImpact(ImpactResult(
              frame: 25,
              roi: const Rect.fromLTWH(0, 0, 10, 10),
              confidence: 1.0)),
          speedEstimator: SpeedEstimatorService(),
          rpmEstimator: _FakeRpm(RpmResult.success(280, 0.85)),
        );

    final d1 = await build().run('dummy.mp4', 30);
    final d2 = await build().run('dummy.mp4', 30);

    expect(d1.speedKmh, equals(d2.speedKmh));
    expect(d1.rpmEstimated, equals(d2.rpmEstimated));
    expect(d1.speedConfidence, equals(d2.speedConfidence));
    expect(d1.rpmConfidence, equals(d2.rpmConfidence));
    expect(d1.framesAnalyzed, equals(d2.framesAnalyzed));
    expect(d1.fpsUsed, equals(d2.fpsUsed));
    expect(d1.speedFailure, equals(d2.speedFailure));
    expect(d1.rpmFailure, equals(d2.rpmFailure));
  });

  test('release 실패 시 speed/rpm 모두 null', () async {
    final frames = List.generate(30, (_) => img.Image(width: 10, height: 10));
    final pipeline = AnalysisPipeline(
      frameExtractor: _FakeFrameExtractor(FrameExtractionResult(
          frames: frames, originalFps: 30, sampleFps: 30)),
      ballDetector: _FakeBallDetector(List.filled(30, null)),
      releaseDetector: _FakeRelease(ReleaseResult.notFound),
      impactDetector: _FakeImpact(ImpactResult.notFound),
      speedEstimator: SpeedEstimatorService(),
      rpmEstimator: _FakeRpm(RpmResult.failed(RpmFailure.featureDetectionFailed)),
    );
    final data = await pipeline.run('dummy.mp4', 30);
    expect(data.speedKmh, isNull);
    expect(data.rpmEstimated, isNull);
    expect(data.speedFailure, equals(SpeedFailure.releaseNotFound));
    expect(data.rpmFailure, equals(RpmFailure.featureDetectionFailed));
  });
}
