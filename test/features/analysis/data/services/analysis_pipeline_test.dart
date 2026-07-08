import 'dart:math' show sqrt;

import 'package:bowling_diary/features/analysis/data/services/analysis_pipeline.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';
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

/// [failFrames]에 해당하는 프레임 인덱스에서 detect()가 예외를 던지는 페이크.
/// 프레임 단위 검출 실패가 파이프라인 전체를 죽이지 않는지 검증하기 위한 회귀 테스트용.
class _FlakyFakeBallDetector implements BallDetectionService {
  final List<BallDetection?> sequence;
  final Set<int> failFrames;
  int _i = 0;
  _FlakyFakeBallDetector(this.sequence, this.failFrames);
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
  @override
  BallDetection? detect(img.Image frame) {
    final i = _i++;
    if (failFrames.contains(i)) {
      throw StateError('synthetic per-frame detection failure at $i');
    }
    return i < sequence.length ? sequence[i] : null;
  }
}

img.Image _blankFrame() {
  final image = img.Image(width: 20, height: 20);
  img.fill(image, color: img.ColorRgb8(10, 10, 10));
  return image;
}

img.Image _whiteFrame() {
  final image = img.Image(width: 20, height: 20);
  img.fill(image, color: img.ColorRgb8(250, 250, 250));
  return image;
}

// --- 실기기 재현용 합성 detection 시퀀스 ---
// 150프레임 클립(실기기 클립 길이와 동일). 다음 두 신호를 동시에 만족하도록 구성:
//  1) FSM(bbox-area 피크 + lane-y 단조증가)은 정확히 frame 36에서 release를 찾는다
//     (0~35: 완만한 백스윙 증가, 35에서 area 피크, 36에서 area 감소 시작 + lane-y 점프).
//  2) ReleaseDetectorService의 속도 휴리스틱은 36 부근 신호를 threshold 미만으로 놓치고,
//     대신 frame 118~122의 스퓨리어스 스파이크(핀 파편 등)를 후보로 잡았다가
//     75% 안전장치에 걸려 notFound로 실패한다 — 실기기 run2와 동일한 실패 형태.
double _regressionArea(int i) {
  if (i < 35) return 0.01 + i * 0.0004;
  if (i == 35) return 0.025;
  final v = 0.025 - (i - 35) * 0.0004;
  return v < 0.005 ? 0.005 : v;
}

double _regressionCy(int i) {
  if (i <= 35) return 0.05 + i * 0.001;
  if (i == 36) return 0.135;
  if (i <= 60) return 0.135 + (i - 36) * 0.0125; // 릴리즈 직후 실제 비행 구간(실측 대응 속도)
  if (i <= 119) return 0.435; // 추적 신호가 평탄해지는 구간(감지기 혼란 유도)
  return 1.0; // 118~122 부근에서 핀 존까지 급점프 — 스퓨리어스 스파이크 + FSM impact 트리거
}

List<BallDetection?> _regressionDetections() => [
      for (var i = 0; i < 150; i++)
        BallDetection(
          cx: 0.5,
          cy: _regressionCy(i),
          bw: sqrt(_regressionArea(i)),
          bh: sqrt(_regressionArea(i)),
          confidence: 0.9,
        ),
    ];

List<img.Image> _regressionFrames() => [
      for (var i = 0; i < 150; i++) i == 120 ? _whiteFrame() : _blankFrame(),
    ];

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

  test(
    '특정 프레임에서 ballDetector.detect()가 예외를 던져도(예: TFLite 엣지 케이스) '
    '해당 프레임만 null로 격하되고 파이프라인 전체는 중단 없이 완주해 속도를 산출한다',
    () async {
      final detections = _regressionDetections();
      final frames = _regressionFrames();

      final pipeline = AnalysisPipeline(
        frameExtractor: _FakeFrameExtractor(
          FrameExtractionResult(frames: frames, originalFps: 30, sampleFps: 30),
        ),
        ballDetector: _FlakyFakeBallDetector(detections, const {10}),
        releaseDetector: ReleaseDetectorService(),
        impactDetector: ImpactDetectorService(pinImpactDetector: PinImpactDetectorService()),
        speedEstimator: SpeedEstimatorService(),
      );

      final result = await pipeline.run('fake.mp4', homography);

      expect(result.framesAnalyzed, detections.length);
      expect(result.speedFailure, isNull);
      expect(result.speedKmh, isNotNull);
      expect(result.speedKmh, inInclusiveRange(10.0, 50.0));
    },
  );

  group('AnalysisPipeline.combineRelease', () {
    test('FSM 찾음 + detector 근접 일치(10프레임 이내) → high confidence로 FSM 프레임 채택', () {
      final result = AnalysisPipeline.combineRelease(36, const ReleaseResult(frame: 40, confidence: 0.5));

      expect(result.frame, 36);
      expect(result.confidence, AnalysisPipeline.highAgreementConfidence);
    });

    test('FSM 찾음 + detector 크게 불일치(100프레임 차이) → FSM 프레임 유지, confidence는 낮게', () {
      final result = AnalysisPipeline.combineRelease(36, const ReleaseResult(frame: 136, confidence: 0.8));

      expect(result.frame, 36);
      expect(result.confidence, AnalysisPipeline.fsmOnlyConfidence);
    });

    test('FSM 찾음 + detector notFound → FSM 프레임 유지', () {
      final result = AnalysisPipeline.combineRelease(36, ReleaseResult.notFound);

      expect(result.frame, 36);
      expect(result.confidence, AnalysisPipeline.fsmOnlyConfidence);
    });

    test('FSM 못 찾음 + detector 찾음 → detector 프레임/confidence로 폴백', () {
      const detectorResult = ReleaseResult(frame: 50, confidence: 0.6);

      final result = AnalysisPipeline.combineRelease(null, detectorResult);

      expect(result.frame, 50);
      expect(result.confidence, 0.6);
    });

    test('둘 다 못 찾음 → notFound', () {
      final result = AnalysisPipeline.combineRelease(null, ReleaseResult.notFound);

      expect(result.isFound, isFalse);
    });
  });

  test(
    '실기기 재현: FSM은 조기(frame 36)에 정확한 release를 찾고, '
    'ReleaseDetectorService의 속도 신호는 후반 스퓨리어스 구간에 현혹돼 notFound로 실패해도 '
    '파이프라인은 FSM 신호를 채택해 성공적으로 속도를 산출한다',
    () async {
      final detections = _regressionDetections();
      final frames = _regressionFrames();

      // 전제 1: FSM 단독으로도 frame 36에서 정확히 release를, 그 이후 impact를 찾는다.
      final fsm = AnalysisStateMachine();
      for (var i = 0; i < detections.length; i++) {
        final d = detections[i];
        final lanePos = d != null ? homography.frameToLane(FramePoint(nx: d.cx, ny: d.cy)) : null;
        fsm.onFrame(frameIdx: i, detection: d, lanePos: lanePos);
      }
      expect(fsm.releaseFrame, 36);
      expect(fsm.impactFrame, isNotNull);

      // 전제 2: 같은 detections를 ReleaseDetectorService에 단독으로 넣으면
      // 후반 스퓨리어스 구간에 현혹되어(안전장치에 걸려) notFound를 반환한다 — 실기기 run2 재현.
      final detectorOnly = ReleaseDetectorService().findRelease(detections, homography: homography);
      expect(detectorOnly.isFound, isFalse);

      // 실제 검증: 파이프라인은 (더 이상 detector 단독에 의존하지 않으므로) FSM 신호를
      // 채택해 releaseNotFound/anchorMismatch 없이 성공적으로 속도를 산출한다.
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

      expect(result.speedFailure, isNull);
      expect(result.speedKmh, isNotNull);
      expect(result.speedKmh, inInclusiveRange(10.0, 50.0));
    },
  );
}
