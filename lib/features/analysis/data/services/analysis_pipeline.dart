import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/analysis_data.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/drift_check_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';
import 'package:bowling_diary/features/analysis/domain/services/calibration_drift_checker.dart';

class AnalysisPipeline {
  final VideoFrameExtractorService frameExtractor;
  final BallDetectionService ballDetector;
  final ReleaseDetectorService releaseDetector;
  final ImpactDetectorService impactDetector;
  final SpeedEstimatorService speedEstimator;
  final CalibrationDriftChecker driftChecker;

  AnalysisPipeline({
    required this.frameExtractor,
    required this.ballDetector,
    required this.releaseDetector,
    required this.impactDetector,
    required this.speedEstimator,
    required this.driftChecker,
  });

  Future<AnalysisData> run(String videoPath, CalibrationProfile profile) async {
    final extracted = await frameExtractor.extract(videoPath);
    final frames = extracted.frames;
    if (frames.isEmpty) {
      return AnalysisData(
        speedFailure: SpeedFailure.lowConfidence,
        driftStatus: DriftStatus.ok,
        framesAnalyzed: 0,
        fpsUsed: extracted.sampleFps,
      );
    }

    final referenceFrame = await _loadReferenceFrame(profile.referenceImagePath);

    final driftResult = referenceFrame != null
        ? driftChecker.check(
            referenceFrame: referenceFrame,
            currentFrame: frames.first,
            referencePoints: profile.framePoints,
            homography: profile.homography,
          )
        : DriftCheckResult(
            status: DriftStatus.recalibrationRequired,
            homography: profile.homography,
            driftScoreNormalized: 1.0,
          );

    if (driftResult.status == DriftStatus.recalibrationRequired) {
      return AnalysisData(
        driftStatus: driftResult.status,
        framesAnalyzed: 0,
        fpsUsed: extracted.sampleFps,
      );
    }

    final homography = driftResult.homography;

    List<BallDetection?> detections;
    try {
      await ballDetector.init();
      detections = frames.map((f) => ballDetector.detect(f)).toList();
    } finally {
      ballDetector.dispose();
    }

    final release = releaseDetector.findRelease(detections, homography: homography);

    final fsm = AnalysisStateMachine();
    for (var i = 0; i < detections.length; i++) {
      final d = detections[i];
      final lanePos = d != null ? homography.frameToLane(FramePoint(nx: d.cx, ny: d.cy)) : null;
      fsm.onFrame(frameIdx: i, detection: d, lanePos: lanePos);
    }

    if (fsm.impactFrame == null || !release.isFound) {
      return AnalysisData(
        speedFailure: SpeedFailure.impactNotFound,
        driftStatus: driftResult.status,
        framesAnalyzed: frames.length,
        fpsUsed: extracted.sampleFps,
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

    final driftPenalty = driftResult.status == DriftStatus.autoCorrected ? 0.9 : 1.0;
    final adjustedConfidence = (speed.confidence * driftPenalty).clamp(0.0, 1.0);

    return AnalysisData(
      speedKmh: speed.kmh,
      speedConfidence: adjustedConfidence,
      speedFailure: speed.failure,
      driftStatus: driftResult.status,
      framesAnalyzed: frames.length,
      fpsUsed: extracted.sampleFps,
    );
  }

  /// 캘리브레이션 시점 레퍼런스 이미지를 로드/디코드한다.
  /// 파일이 없거나 디코드 실패 시 null을 반환 — 호출부에서 recalibrationRequired로 처리(fail safe).
  Future<img.Image?> _loadReferenceFrame(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }
}
