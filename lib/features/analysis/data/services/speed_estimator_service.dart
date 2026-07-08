import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart';

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';

class SpeedEstimatorService {
  static const int _flightStartOffset = 8;
  static const int _flightEndOffset = 24;
  static const int _minSamples = 8;
  static const double _minSpeed = 10.0;
  static const double _maxSpeed = 50.0;

  SpeedResult estimate({
    required ReleaseResult release,
    required ImpactResult impact,
    required List<BallDetection?> detections,
    required HomographyMatrix homography,
    required int sampleFps,
  }) {
    if (!release.isFound) {
      return SpeedResult.failed(SpeedFailure.releaseNotFound);
    }

    if (impact.confidence == ImpactConfidence.low) {
      debugPrint('[SpeedEstimator] impact 신호 불일치(low confidence) — 강제 채택 안 함');
      return SpeedResult.failed(SpeedFailure.anchorMismatch);
    }

    final flightStart = release.frame + _flightStartOffset;
    final flightEnd = (release.frame + _flightEndOffset).clamp(0, detections.length - 1);

    if (flightStart >= flightEnd) {
      return SpeedResult.failed(SpeedFailure.outOfRange);
    }

    final samples = <double>[];
    for (var i = flightStart + 1; i <= flightEnd; i++) {
      final prev = detections[i - 1];
      final curr = detections[i];
      if (prev == null || curr == null) continue;
      final prevLane = homography.frameToLane(FramePoint(nx: prev.cx, ny: prev.cy));
      final currLane = homography.frameToLane(FramePoint(nx: curr.cx, ny: curr.cy));
      final dx = currLane.xM - prevLane.xM;
      final dy = currLane.yM - prevLane.yM;
      final distM = sqrt(dx * dx + dy * dy);
      samples.add(distM * sampleFps);
    }

    if (samples.length < _minSamples) {
      return SpeedResult.failed(SpeedFailure.lowConfidence);
    }

    samples.sort();
    final mid = samples.length ~/ 2;
    final medianMs =
        samples.length.isOdd ? samples[mid] : (samples[mid - 1] + samples[mid]) / 2.0;
    final kmh = medianMs * 3.6;

    if (kmh < _minSpeed || kmh > _maxSpeed) {
      return SpeedResult.failed(SpeedFailure.outOfRange);
    }

    final windowSize = flightEnd - flightStart;
    final sampleCoverage = (samples.length / windowSize).clamp(0.0, 1.0);
    final impactPenalty = impact.confidence == ImpactConfidence.medium ? 0.85 : 1.0;
    final confidence = (sampleCoverage * impactPenalty * release.confidence).clamp(0.0, 1.0);

    final rounded = double.parse(kmh.toStringAsFixed(1));
    return SpeedResult.success(rounded, confidence);
  }
}
