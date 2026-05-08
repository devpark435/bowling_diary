import 'package:flutter/foundation.dart';

import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';

class SpeedEstimatorService {
  static const double _laneLength = 18.29;
  static const double _minSpeed = 10.0;
  static const double _maxSpeed = 50.0;
  static const double _minConfidence = 0.5;

  SpeedResult estimate({
    required ReleaseResult release,
    required ImpactResult impact,
    required int sampleFps,
  }) {
    if (!release.isFound) return SpeedResult.failed(SpeedFailure.releaseNotFound);
    if (!impact.isFound) return SpeedResult.failed(SpeedFailure.impactNotFound);

    final elapsedSec = (impact.frame - release.frame) / sampleFps.toDouble();
    if (elapsedSec <= 0) return SpeedResult.failed(SpeedFailure.outOfRange);

    final rawKmh = (_laneLength / elapsedSec) * 3.6;
    final inRange = rawKmh >= _minSpeed && rawKmh <= _maxSpeed;
    if (!inRange) {
      debugPrint('[SpeedEstimator] outOfRange: ${rawKmh.toStringAsFixed(1)}km/h');
      return SpeedResult.failed(SpeedFailure.outOfRange);
    }

    final confidence = release.confidence < impact.confidence
        ? release.confidence
        : impact.confidence;
    if (confidence < _minConfidence) {
      debugPrint('[SpeedEstimator] lowConfidence: $confidence');
      return SpeedResult.failed(SpeedFailure.lowConfidence);
    }

    final rounded = double.parse(rawKmh.toStringAsFixed(1));
    debugPrint('[SpeedEstimator] $rounded km/h, conf=$confidence');
    return SpeedResult.success(rounded, confidence);
  }
}
