import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart';

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';

class ReleaseDetectorService {
  static const _minConsecutive = 3;
  // 볼이 보유/arm swing 상태와 구분하는 프레임당 최소 이동 거리 (정규화 좌표 0~1)
  static const double _moveThreshold = 0.015;

  int? findReleaseFrame(List<BallDetection?> detections) {
    int consecutive = 0;
    int? start;
    BallDetection? prev;

    for (int i = 0; i < detections.length; i++) {
      final det = detections[i];
      if (det == null) {
        consecutive = 0;
        start = null;
        prev = null;
        continue;
      }

      if (prev != null && _disp(prev, det) >= _moveThreshold) {
        start ??= i - 1;
        consecutive++;
        if (consecutive >= _minConsecutive) {
          debugPrint('[ReleaseDetector] 릴리즈 프레임: $start (연속 $_minConsecutive프레임)');
          return start;
        }
      } else if (prev != null) {
        consecutive = 0;
        start = null;
      }

      prev = det;
    }

    debugPrint('[ReleaseDetector] 릴리즈 프레임 미감지');
    return null;
  }

  double _disp(BallDetection a, BallDetection b) {
    final dx = b.cx - a.cx;
    final dy = b.cy - a.cy;
    return sqrt(dx * dx + dy * dy);
  }
}
