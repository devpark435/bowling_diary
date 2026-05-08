import 'package:flutter/foundation.dart';

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/rpm_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_analysis_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';

class AnalysisPipeline {
  final VideoFrameExtractorService frameExtractor;
  final BallDetectionService ballDetector;
  final ReleaseDetectorService releaseDetector;
  final PinImpactDetectorService impactDetector;
  final SpeedEstimatorService speedEstimator;
  final RpmEstimatorService rpmEstimator;

  AnalysisPipeline({
    required this.frameExtractor,
    required this.ballDetector,
    required this.releaseDetector,
    required this.impactDetector,
    required this.speedEstimator,
    required this.rpmEstimator,
  });

  Future<AnalysisData> run(String videoPath, int fpsHint) async {
    final extracted = await frameExtractor.extract(videoPath);
    final frames = extracted.frames;
    if (frames.isEmpty) {
      return AnalysisData(framesAnalyzed: 0, fpsUsed: extracted.sampleFps);
    }

    List<BallDetection?> detections;
    try {
      await ballDetector.init();
      detections = frames.map((f) => ballDetector.detect(f)).toList();
    } catch (e) {
      debugPrint('[Pipeline] YOLO 오류: $e');
      detections = List.filled(frames.length, null);
    } finally {
      ballDetector.dispose();
    }

    final release = releaseDetector.findRelease(detections);
    final impact = impactDetector.findImpact(frames, detections, release.frame);

    final speed = speedEstimator.estimate(
      release: release,
      impact: impact,
      sampleFps: extracted.sampleFps,
    );

    final rpm = rpmEstimator.estimate(
      frames: frames,
      detections: detections,
      releaseFrame: release.frame,
      sampleFps: extracted.sampleFps,
    );

    return AnalysisData(
      speedKmh: speed.kmh,
      rpmEstimated: rpm.rpm,
      framesAnalyzed: frames.length,
      fpsUsed: extracted.sampleFps,
      speedFailure: speed.failure,
      rpmFailure: rpm.failure,
      speedConfidence: speed.confidence,
      rpmConfidence: rpm.confidence,
    );
  }
}
