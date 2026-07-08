import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/analysis_data.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';

class AnalysisPipeline {
  final VideoFrameExtractorService frameExtractor;
  final BallDetectionService ballDetector;
  final ReleaseDetectorService releaseDetector;
  final ImpactDetectorService impactDetector;
  final SpeedEstimatorService speedEstimator;

  AnalysisPipeline({
    required this.frameExtractor,
    required this.ballDetector,
    required this.releaseDetector,
    required this.impactDetector,
    required this.speedEstimator,
  });

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

    if (!release.isFound || fsm.impactFrame == null) {
      return AnalysisData(
        speedFailure: !release.isFound ? SpeedFailure.releaseNotFound : SpeedFailure.impactNotFound,
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

    return AnalysisData(
      speedKmh: speed.kmh,
      speedConfidence: speed.confidence,
      speedFailure: speed.failure,
      framesAnalyzed: frames.length,
      fpsUsed: extracted.sampleFps,
    );
  }
}
