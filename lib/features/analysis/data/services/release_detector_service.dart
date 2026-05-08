import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart';

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';

class ReleaseDetectorService {
  static const _windowSize = 5;
  static const _minConsecutive = 3;
  static const double _absSpeedThreshold = 0.025;

  ReleaseResult findRelease(List<BallDetection?> detections) {
    final velocities = _smoothedVelocities(detections);
    if (velocities.length < _minConsecutive + 1) {
      debugPrint('[ReleaseDetector] 데이터 부족');
      return ReleaseResult.notFound;
    }

    int consecutive = 0;
    int? startFrame;
    int maxConsecutive = 0;

    for (int i = 1; i < velocities.length; i++) {
      final v = velocities[i];
      final a = v - velocities[i - 1];
      final ok = v >= _absSpeedThreshold && a > 0;

      if (ok) {
        consecutive++;
        if (consecutive == 1) startFrame = i;
        if (consecutive > maxConsecutive) maxConsecutive = consecutive;
        if (consecutive >= _minConsecutive && startFrame != null) {
          final confidence =
              (maxConsecutive / _windowSize).clamp(0.0, 1.0);
          debugPrint('[ReleaseDetector] release=$startFrame, conf=$confidence');
          return ReleaseResult(frame: startFrame, confidence: confidence);
        }
      } else {
        consecutive = 0;
        startFrame = null;
      }
    }

    debugPrint('[ReleaseDetector] release 미감지');
    return ReleaseResult.notFound;
  }

  /// 정규화 변위 시퀀스를 5프레임 이동평균 처리하여 반환.
  /// null 또는 null과 인접한 프레임은 변위 0으로 처리.
  List<double> _smoothedVelocities(List<BallDetection?> detections) {
    final raw = <double>[0.0];
    for (int i = 1; i < detections.length; i++) {
      final prev = detections[i - 1];
      final curr = detections[i];
      if (prev == null || curr == null) {
        raw.add(0.0);
      } else {
        final dx = curr.cx - prev.cx;
        final dy = curr.cy - prev.cy;
        raw.add(sqrt(dx * dx + dy * dy));
      }
    }

    final smoothed = <double>[];
    for (int i = 0; i < raw.length; i++) {
      final start = (i - _windowSize ~/ 2).clamp(0, raw.length - 1);
      final end = (i + _windowSize ~/ 2 + 1).clamp(0, raw.length);
      double sum = 0;
      for (int j = start; j < end; j++) sum += raw[j];
      smoothed.add(sum / (end - start));
    }
    return smoothed;
  }
}
