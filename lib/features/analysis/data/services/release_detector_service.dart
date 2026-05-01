import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';

class ReleaseDetectorService {
  static const _minConsecutive = 3;

  int? findReleaseFrame(List<BallDetection?> detections) {
    int consecutive = 0;
    int? start;

    for (int i = 0; i < detections.length; i++) {
      if (detections[i] != null) {
        consecutive++;
        start ??= i;
        if (consecutive >= _minConsecutive) return start;
      } else {
        consecutive = 0;
        start = null;
      }
    }
    return null;
  }
}
