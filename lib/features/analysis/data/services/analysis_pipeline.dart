import 'dart:math' as math;

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/analysis_data.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';
import 'package:bowling_diary/features/analysis/domain/services/pin_row_detector.dart';
import 'package:bowling_diary/features/analysis/domain/services/trajectory_curve.dart';
import 'package:bowling_diary/features/analysis/domain/services/trajectory_refiner.dart';
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

  /// 핀 폭발 탐색 시작 프레임 (순수 함수, 단독 유닛테스트 가능).
  ///
  /// = 궤적 소실 프레임 + (공이 핀덱(18.29m)에 도착할 때까지의 예상 프레임 수 ÷ 2).
  ///
  /// 도착 예상은 마지막 y와 마지막 구간 기울기(끝 5개 샘플)로 외삽하는데,
  /// 남은 거리와 기울기를 **같은 (왜곡됐을 수 있는) 캘리브레이션 자**로 재기
  /// 때문에 스케일 오류가 비율에서 상당 부분 약분된다 — 절대 y 게이트(구
  /// 16m 기준)와 달리 캘리브레이션이 틀어져도 동작한다. 절반만 더하는 이유:
  /// 외삽 오차(±수 프레임)로 시작점이 실제 도착 뒤로 넘어가면 폭발 자체를
  /// 놓치므로, 공 진입 Δ 스파이크만 피할 만큼 보수적으로 민다.
  ///
  /// 반환 null = 궤적 없음(탐색 시작 추정 불가 → detector가 legacy 규칙 사용).
  static int? estimatePinSearchStart(List<TrajectorySample> refined) {
    if (refined.isEmpty) return null;
    final last = refined.last;
    if (refined.length < 2) return last.frame;

    final anchorIdx = math.max(0, refined.length - 5);
    final anchor = refined[anchorIdx];
    final df = last.frame - anchor.frame;
    final dy = last.lane.yM - anchor.lane.yM;
    if (df <= 0 || dy <= 0) return last.frame;

    final slopePerFrame = dy / df;
    final remainingM = 18.29 - last.lane.yM;
    if (remainingM <= 0) return last.frame;

    final halfArrivalFrames = (remainingM / slopePerFrame / 2).round();
    return last.frame + halfArrivalFrames.clamp(0, 60);
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
      // 진단 — "검출 0건"일 때 추론이 깨진 것(최고 점수 ~0)인지 임계값 바로
      // 아래(전처리/클래스 문제)인지 즉시 구분 가능하게 한다.
      debugPrint('[BallDetection] 검출 ${detections.whereType<BallDetection>().length}'
          '/${frames.length} 프레임, 전 구간 최고 점수 '
          '${ballDetector.debugMaxScore.toStringAsFixed(3)} (임계값 0.3)');
    } finally {
      ballDetector.dispose();
    }

    final detectorRelease = releaseDetector.findRelease(detections, homography: homography);

    final fsm = AnalysisStateMachine();
    for (var i = 0; i < detections.length; i++) {
      final d = detections[i];
      final lanePos = d != null ? homography.frameToLane(d.contactPoint) : null;
      fsm.onFrame(frameIdx: i, detection: d, lanePos: lanePos);
    }

    final release = combineRelease(fsm.releaseFrame, detectorRelease);

    final refined = refineTrajectory(fsm.trajectory);
    debugPrint('[Trajectory] refined (frame:y) = ${refined.map((s) => "${s.frame}:${s.lane.yM.toStringAsFixed(1)}").join(" ")}');
    final fitted = fitAndResample(refined);
    // 엔트리 앵글은 끝 연장(extendCurveEnd) 전, 즉 실측 데이터 기반 곡선
    // 기준으로 계산한다 — 연장은 선형이라 각도 자체는 동일하지만 실측
    // 데이터 기준이 더 정직하다(연장 로직 변경에 영향받지 않음).
    final entryAngle = entryAngleDeg(fitted);
    // 정제가 초반 노이즈 구간을 잘라내도 릴리즈 직후부터 선이 보이도록,
    // 원시 궤적의 실제 시작 y(최소 2.5m)까지 곡선을 선형 연장한다.
    final started = fsm.trajectory.isEmpty
        ? fitted
        : extendCurveStart(fitted,
            targetStartY: math.max(2.5, fsm.trajectory.first.lane.yM));
    // 원거리(17m+)에서는 공이 화면상 수 픽셀이라 검출이 끊겨 곡선이 핀
    // 직전에서 멈춘다 — 핀덱(18.29m)까지 끝 기울기를 그대로 연장한다.
    final curve = extendCurveEnd(started, targetEndY: 18.29);
    const ribbonHalfWidthM = 0.11; // 볼 반경(공 지름 0.218m)
    final trajectory = curve
        .map((e) => TrajectoryRibbonPoint(
              frame: e.frame,
              left: homography.laneToFrame(LanePoint(xM: e.lane.xM - ribbonHalfWidthM, yM: e.lane.yM)),
              right: homography.laneToFrame(LanePoint(xM: e.lane.xM + ribbonHalfWidthM, yM: e.lane.yM)),
            ))
        .toList();
    debugPrint('[Trajectory] raw ${fsm.trajectory.length} → refined ${refined.length} → curve ${curve.length}개 포인트, '
        '프레임: ${refined.isEmpty ? "없음" : "${refined.first.frame}~${refined.last.frame}"}, '
        '레인 y범위(연장 후): ${curve.isEmpty ? "없음" : "${curve.first.lane.yM.toStringAsFixed(2)}~${curve.last.lane.yM.toStringAsFixed(2)}m"}');

    if (!release.isFound) {
      return AnalysisData(
        speedFailure: SpeedFailure.releaseNotFound,
        framesAnalyzed: frames.length,
        fpsUsed: extracted.sampleFps,
        trajectory: trajectory,
        entryAngleDeg: entryAngle,
      );
    }

    if (fsm.impactFrame == null) {
      debugPrint('[AnalysisPipeline] FSM 임팩트 없음 — 핀 폭발 신호 단독으로 진행');
    }

    // 핀 존 산출 3단 체인(Phase 3 존 독립화): 캘리브레이션(호모그래피)이
    // 흔들려도 핀 폭발 감지가 정확한 위치를 보도록, 릴리즈 시점 프레임(핀이
    // 온전히 서 있고 공은 아직 근거리)에서 핀 행을 직접 탐지하는 것을
    // 1순위로 한다. 실패하면 기존 호모그래피 투영, 그마저 실패하면
    // (impactDetector 내부에서) legacy 상단 20% 존으로 폴백한다.
    final releaseFrameIdx = release.frame.clamp(0, frames.length - 1);
    final pinRowZone = detectPinRowZone(frames[releaseFrameIdx]);
    final homographyZone = pinRowZone == null
        ? PinImpactDetectorService.computePinZone(
            homography,
            frameAspect: frames[0].width / frames[0].height,
          )
        : null;
    final pinZone = pinRowZone ?? homographyZone;
    final zoneSourceLabel = pinRowZone != null ? '자동탐지' : (homographyZone != null ? '호모그래피' : 'legacy');
    debugPrint('[PinZone] 소스: $zoneSourceLabel'
        '${pinZone != null ? " LTRB(${pinZone.left.toStringAsFixed(2)},${pinZone.top.toStringAsFixed(2)},${pinZone.right.toStringAsFixed(2)},${pinZone.bottom.toStringAsFixed(2)})" : ""}');

    // 핀 폭발 탐색 시작점: 궤적 소실 프레임에 "공이 핀덱에 도착할 때까지의
    // 예상 프레임의 절반"을 더한다 (estimatePinSearchStart 참조). 소실 직후를
    // 씨드로 쓰면 공이 핀존에 진입하는 순간의 날카로운 Δ가 폭발보다 먼저
    // argmax에 잡히는 오탐이 3회 연속 실측됐다(115/115/117 vs 실제 ~128).
    // 소실이 BP 등 중간 유실이어도 폭발 감지의 영구변화 게이트가 오탐을
    // 막는다(폭발 없으면 null → 정직한 실패).
    final pinSearchStart = estimatePinSearchStart(refined);

    final impact = impactDetector.detect(
      frames: frames,
      releaseFrame: release.frame,
      homographyImpactFrame: fsm.impactFrame,
      pinZone: pinZone,
      pinSearchStart: pinSearchStart,
    );

    if (impact == null) {
      return AnalysisData(
        speedFailure: SpeedFailure.impactNotFound,
        framesAnalyzed: frames.length,
        fpsUsed: extracted.sampleFps,
        trajectory: trajectory,
        entryAngleDeg: entryAngle,
      );
    }

    final speed = speedEstimator.estimate(
      release: release,
      impact: impact,
      refinedTrajectory: refined,
      sampleFps: extracted.sampleFps,
    );

    return AnalysisData(
      speedKmh: speed.kmh,
      speedConfidence: speed.confidence,
      speedFailure: speed.failure,
      framesAnalyzed: frames.length,
      fpsUsed: extracted.sampleFps,
      trajectory: trajectory,
      entryAngleDeg: entryAngle,
    );
  }
}
