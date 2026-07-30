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
import 'package:bowling_diary/features/analysis/domain/services/arrow_detector.dart';
import 'package:bowling_diary/features/analysis/domain/services/lane_landmark_speed.dart';
import 'package:bowling_diary/features/analysis/domain/services/pin_row_detector.dart';
import 'package:bowling_diary/features/analysis/domain/services/projective_track_model.dart';
import 'package:bowling_diary/features/analysis/domain/services/trajectory_curve.dart';
import 'package:bowling_diary/features/analysis/domain/services/trajectory_refiner.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;

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
  /// 정제 궤적이 채택한 프레임들의 **픽셀** 관측을 모은다. 레인 좌표를 거치지
  /// 않으므로 캘리브레이션과 무관하다 — 픽셀 공간 궤적 모델의 입력.
  static List<BallPixelSample> collectPixelTrack(
    List<BallDetection?> detections,
    List<TrajectorySample> refined,
  ) {
    final keep = refined.map((s) => s.frame).toSet();
    return <BallPixelSample>[
      for (var i = 0; i < detections.length; i++)
        if (keep.contains(i) && detections[i] != null)
          (frame: i, contact: detections[i]!.contactPoint, widthN: detections[i]!.bw),
    ];
  }

  /// 픽셀 공간 궤적 리본. 캘리브레이션을 전혀 쓰지 않는다.
  ///
  /// 기존 레인 좌표 경로 대비 세 가지가 고쳐진다:
  ///  1) 끝 연장이 **직선**이 아니라 투영 곡선(쌍곡선)이다. 직선 연장은 핀덱
  ///     부근에서 소실점을 넘어 발산한다(단위 테스트로 고정).
  ///  2) 연장 목표가 레인 y=18.29m(캘리브레이션 스케일에 물림)가 아니라 실측
  ///     **핀 충돌 프레임**이다.
  ///  3) 리본 폭이 고정 0.22m 환산이 아니라 공의 실측 bbox 폭 + 원근 모델이다.
  ///
  /// 적합 실패 시 null — 호출부가 기존 레인 좌표 리본으로 폴백한다.
  /// [rms]는 적합 잔차(정규화 단위)로, 내부 QA 뱃지에 노출한다.
  static ({List<TrajectoryRibbonPoint> ribbon, double rms})? buildPixelRibbon({
    required List<BallPixelSample> pixelTrack,
    required int impactFrame,
    required int releaseFrame,
  }) {
    final model = fitProjectiveTrack(pixelTrack);
    if (model == null) return null;
    final ribbon = buildProjectiveRibbon(
      track: pixelTrack,
      model: model,
      endFrame: impactFrame,
      startFrame: releaseFrame,
    );
    return ribbon.isEmpty ? null : (ribbon: ribbon, rms: model.rms);
  }

  /// 구속 채택 허용 범위(km/h). SpeedEstimatorService의 가드와 같은 값.
  static const double minPlausibleKmh = 10;
  static const double maxPlausibleKmh = 50;

  /// 랜드마크 통과-시각 구속. 캘리브레이션(호모그래피)을 쓰지 않는다.
  ///
  /// [releaseFrame] 이미지에서 조준 화살표를 찾아 iso-u 선(양 끝 화살표,
  /// 파울라인에서 12ft)을 만들고, 공이 그 선을 지난 프레임부터 핀 충돌
  /// 프레임까지의 **시간**으로 구속을 낸다. 픽셀 깊이를 재지 않으므로 소실점
  /// 근처의 원근 압축(기존 코어의 지배적 오차원)이 계산에서 빠진다.
  ///
  /// 화살표 검출·셰브론 검증 실패 시 null → 호출부가 기존 코어로 폴백한다.
  /// 화살표 검출기 임계값은 실영상 1편 기준이라 일반화가 검증되지 않았다.
  static double? estimateLandmarkSpeed({
    required img.Image releaseFrame,
    required List<BallPixelSample> pixelTrack,
    required int impactFrame,
    required int sampleFps,
  }) {
    // 실패가 "검출 0개"인지 "검출은 됐는데 선을 못 세움"인지 구분되지 않으면
    // 튜닝 방향을 정할 수 없다 — 실기기 1회 실패에 빌드 1회를 쓰게 된다.
    final arrows = detectArrows(releaseFrame);
    final line = arrowLineFromDetections(arrows);
    debugPrint('[Arrow] 입력 ${releaseFrame.width}x${releaseFrame.height}, '
        '검출 ${arrows.length}개'
        '${arrows.isEmpty ? "" : " ${arrows.map((a) => "(${a.nx.toStringAsFixed(3)},${a.ny.toStringAsFixed(3)})").join(" ")}"}, '
        '선 ${line == null ? "실패" : "성립"}');
    if (line == null) return null;
    return estimateLandmarkSpeedKmh(
      track: [for (final s in pixelTrack) (frame: s.frame, p: s.contact)],
      line: line,
      impactFrame: impactFrame.toDouble(),
      sampleFps: sampleFps,
    );
  }

  /// 두 코어의 값 중 무엇을 최종 구속으로 쓸지 정한다.
  ///
  /// 랜드마크 코어가 물리적으로 말이 되는 값을 냈으면 그것을 채택한다 —
  /// 조건수가 기존 코어보다 두 자릿수 좋기 때문(에로우 선 ±15px → ±0.4km/h vs
  /// 기존 방식의 원근 압축 민감도). 못 냈거나 범위를 벗어나면 기존 코어로 폴백.
  static ({double kmh, SpeedSource source})? adoptSpeed({
    required double? landmarkKmh,
    required double? legacyKmh,
  }) {
    if (landmarkKmh != null &&
        landmarkKmh >= minPlausibleKmh &&
        landmarkKmh <= maxPlausibleKmh) {
      return (kmh: landmarkKmh, source: SpeedSource.landmark);
    }
    if (legacyKmh != null) {
      return (kmh: legacyKmh, source: SpeedSource.legacy);
    }
    return null;
  }

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
  /// [landmarkFrame]은 조준 화살표 검출 전용 고해상도 프레임이다. 분석 프레임은
  /// 폭 480 + jpeg q5로 뽑히는데, 화살표는 그 해상도에서 뭉개져 검출이 깨진다.
  /// 화살표는 레인에 고정된 마킹이라 어느 프레임을 써도 무방하므로, 호출부가
  /// 이미 원본 해상도로 뽑아둔 첫 프레임을 그대로 넘긴다. 없으면 릴리즈 프레임
  /// 폴백.
  Future<AnalysisData> run(
    String videoPath,
    HomographyMatrix homography, {
    img.Image? landmarkFrame,
  }) async {
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
    final pixelTrack = collectPixelTrack(detections, refined);
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

    // 궤적 리본은 픽셀 공간 모델을 1순위로 쓴다(캘리브레이션 무관, 핀 충돌
    // 프레임까지 투영 곡선으로 연장). 적합 실패 시 레인 좌표 리본으로 폴백.
    final pixelRibbon = buildPixelRibbon(
      pixelTrack: pixelTrack,
      impactFrame: impact.frame,
      releaseFrame: release.frame,
    );
    final finalTrajectory = pixelRibbon?.ribbon ?? trajectory;
    final trajectorySource =
        pixelRibbon != null ? TrajectorySource.projective : TrajectorySource.laneFallback;
    debugPrint('[Trajectory] 리본 소스: ${trajectorySource.label} '
        '(${finalTrajectory.length}개 단면, 픽셀관측 ${pixelTrack.length}개'
        '${pixelRibbon != null ? ", rms ${pixelRibbon.rms.toStringAsFixed(5)}" : ""})');
    // 리본이 핀까지 닿는지는 끝점 ny를 핀존 ny와 직접 비교해야 판정된다.
    // "선이 BP에서 끝난다"가 연장 실패인지 원근 압축인지 이 한 줄로 갈린다.
    if (finalTrajectory.isNotEmpty) {
      final head = finalTrajectory.first;
      final tail = finalTrajectory.last;
      final lastObserved = pixelTrack.isEmpty ? null : pixelTrack.last;
      debugPrint('[Trajectory] 리본 f${head.frame}~f${tail.frame} '
          'ny ${((head.left.ny + head.right.ny) / 2).toStringAsFixed(3)}'
          '→${((tail.left.ny + tail.right.ny) / 2).toStringAsFixed(3)}, '
          '마지막 관측 f${lastObserved?.frame} ny '
          '${lastObserved?.contact.ny.toStringAsFixed(3) ?? "없음"}, '
          '핀존 ny ${pinZone == null ? "없음" : "${pinZone.top.toStringAsFixed(3)}~${pinZone.bottom.toStringAsFixed(3)}"}');
    }

    final speed = speedEstimator.estimate(
      release: release,
      impact: impact,
      refinedTrajectory: refined,
      sampleFps: extracted.sampleFps,
    );

    // 랜드마크 통과-시각 구속 — 조준 화살표가 검출되면 이쪽이 1순위.
    final landmarkKmh = estimateLandmarkSpeed(
      releaseFrame: landmarkFrame ?? frames[releaseFrameIdx],
      pixelTrack: pixelTrack,
      impactFrame: impact.frame,
      sampleFps: extracted.sampleFps,
    );
    final adopted = adoptSpeed(landmarkKmh: landmarkKmh, legacyKmh: speed.kmh);
    debugPrint('[Speed] 랜드마크 ${landmarkKmh?.toStringAsFixed(1) ?? "없음"}km/h, '
        '기존 ${speed.kmh?.toStringAsFixed(1) ?? "없음"}km/h → '
        '채택 ${adopted == null ? "실패" : "${adopted.kmh.toStringAsFixed(1)}km/h(${adopted.source.label})"}');

    return AnalysisData(
      speedKmh: adopted?.kmh,
      speedConfidence: speed.confidence,
      speedFailure: adopted == null ? speed.failure : null,
      framesAnalyzed: frames.length,
      fpsUsed: extracted.sampleFps,
      trajectory: finalTrajectory,
      entryAngleDeg: entryAngle,
      trajectorySource: trajectorySource,
      trajectoryFitRms: pixelRibbon?.rms,
      speedSource: adopted?.source,
      landmarkSpeedKmh: landmarkKmh,
      legacySpeedKmh: speed.kmh,
    );
  }
}
