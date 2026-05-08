import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/rpm_result.dart';

class RpmEstimatorService {
  /// Lucas-Kanade optical flow 기반 RPM 추정.
  /// Task 9에서 opencv_dart로 본 구현. 현재는 stub.
  RpmResult estimate({
    required List<img.Image> frames,
    required List<BallDetection?> detections,
    required int releaseFrame,
    required int sampleFps,
  }) {
    return RpmResult.failed(RpmFailure.featureDetectionFailed);
  }
}
