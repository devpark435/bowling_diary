import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/analysis_data.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class AnalysisPipeline {
  final VideoFrameExtractorService frameExtractor;
  final BallDetectionService ballDetector;
  final ReleaseDetectorService releaseDetector;
  final ImpactDetectorService impactDetector;
  final SpeedEstimatorService speedEstimator;

  /// FSM이 찾은 release가 ReleaseDetectorService 결과와 이 프레임 수 이내로
  /// 일치하면 "교차검증됨(high agreement)"으로 취급한다.
  static const int agreementFrameTolerance = 10;

  /// FSM + ReleaseDetectorService 둘 다 일치할 때의 confidence.
  static const double highAgreementConfidence = 0.9;

  /// FSM만 release를 찾고 ReleaseDetectorService가 불일치하거나 못 찾았을 때의
  /// confidence — 실기기 2회 연속 검증에서 FSM 단독 신호가 신뢰할 만하다고
  /// 확인됐으므로, 이 경우도 실패 대신 FSM 프레임을 채택한다.
  static const double fsmOnlyConfidence = 0.7;

  AnalysisPipeline({
    required this.frameExtractor,
    required this.ballDetector,
    required this.releaseDetector,
    required this.impactDetector,
    required this.speedEstimator,
  });

  /// release 신호 결합 로직 (순수 함수, 단독 유닛테스트 가능).
  ///
  /// 우선순위: FSM(bbox-area 피크 + lane-y 단조증가, 실기기 2회 연속 정답 검증됨)이
  /// 1순위, ReleaseDetectorService(속도 휴리스틱)는 폴백/교차검증 신호.
  /// impact에 이미 적용된 것과 동일한 패턴(ImpactDetectorService 참조).
  ///
  /// - FSM이 찾음: FSM 프레임 채택. detector가 근접 일치(±[agreementFrameTolerance]
  ///   프레임 이내)하면 high confidence, 아니면(불일치하거나 detector가 못 찾았어도)
  ///   FSM 단독 confidence로 채택 — detector 프레임으로 대체하지 않는다.
  /// - FSM이 못 찾고 detector가 찾음: detector 결과를 그대로 폴백 사용.
  /// - 둘 다 못 찾음: notFound.
  static ReleaseResult combineRelease(int? fsmReleaseFrame, ReleaseResult detectorResult) {
    if (fsmReleaseFrame != null) {
      final agrees = detectorResult.isFound &&
          (detectorResult.frame - fsmReleaseFrame).abs() <= agreementFrameTolerance;
      return ReleaseResult(
        frame: fsmReleaseFrame,
        confidence: agrees ? highAgreementConfidence : fsmOnlyConfidence,
      );
    }
    if (detectorResult.isFound) {
      return detectorResult;
    }
    return ReleaseResult.notFound;
  }

  /// [homography]는 이 영상 전용으로 산출된 호모그래피다(레퍼런스 = 영상 자체이므로
  /// drift 개념이 존재하지 않는다 — spec §10 참조).
  Future<AnalysisData> run(String videoPath, HomographyMatrix homography) async {
    final extracted = await frameExtractor.extract(videoPath);
    final frames = extracted.frames;
    if (frames.isEmpty) {
      return AnalysisData(
        speedFailure: SpeedFailure.lowConfidence,
        framesAnalyzed: 0,
        fpsUsed: extracted.sampleFps,
      );
    }

    List<BallDetection?> detections;
    try {
      // 모델 로드 자체가 실패하면(GPU/CPU 둘 다 실패) 0프레임 분석은 의미가 없으므로
      // 여기서는 예외를 그대로 전파해 analysis_trim_page의 상위 핸들러가 처리하게 둔다.
      await ballDetector.init();

      // 반면 프레임 단위 검출 실패는 치명적이지 않다 — 다운스트림(release/impact/speed
      // estimator)이 이미 null 검출을 1급 케이스로 처리하도록 설계돼 있으므로, 개별
      // 프레임에서 예외가 나도 해당 프레임만 null로 격하시키고 나머지는 계속 진행한다.
      detections = <BallDetection?>[];
      for (var i = 0; i < frames.length; i++) {
        try {
          detections.add(ballDetector.detect(frames[i]));
        } catch (e) {
          debugPrint('[AnalysisPipeline] frame $i 검출 실패: $e');
          detections.add(null);
        }
      }
    } finally {
      ballDetector.dispose();
    }

    final detectorRelease = releaseDetector.findRelease(detections, homography: homography);

    final fsm = AnalysisStateMachine();
    for (var i = 0; i < detections.length; i++) {
      final d = detections[i];
      final lanePos = d != null ? homography.frameToLane(FramePoint(nx: d.cx, ny: d.cy)) : null;
      fsm.onFrame(frameIdx: i, detection: d, lanePos: lanePos);
    }

    final release = combineRelease(fsm.releaseFrame, detectorRelease);

    final trajectory = fsm.trajectory.map((e) => homography.laneToFrame(e.lane)).toList();
    debugPrint('[Trajectory] ${trajectory.length}개 포인트, fsm.trajectory 첫/끝 프레임: '
        '${fsm.trajectory.isEmpty ? "없음" : "${fsm.trajectory.first.frame}~${fsm.trajectory.last.frame}"}, '
        '레인 y범위: ${fsm.trajectory.isEmpty ? "없음" : "${fsm.trajectory.first.lane.yM.toStringAsFixed(2)}~${fsm.trajectory.last.lane.yM.toStringAsFixed(2)}m"}');

    if (!release.isFound || fsm.impactFrame == null) {
      return AnalysisData(
        speedFailure: !release.isFound ? SpeedFailure.releaseNotFound : SpeedFailure.impactNotFound,
        framesAnalyzed: frames.length,
        fpsUsed: extracted.sampleFps,
        trajectory: trajectory,
      );
    }

    final impact = impactDetector.detect(
      frames: frames,
      releaseFrame: release.frame,
      homographyImpactFrame: fsm.impactFrame!,
    );

    final speed = speedEstimator.estimate(
      release: release,
      impact: impact,
      detections: detections,
      homography: homography,
      sampleFps: extracted.sampleFps,
    );

    return AnalysisData(
      speedKmh: speed.kmh,
      speedConfidence: speed.confidence,
      speedFailure: speed.failure,
      framesAnalyzed: frames.length,
      fpsUsed: extracted.sampleFps,
      trajectory: trajectory,
    );
  }
}
