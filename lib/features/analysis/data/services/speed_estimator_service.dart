import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart';

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';

/// 볼 궤적 호모그래피 기반 속도 추정 서비스
///
/// release 프레임 이후 비행 윈도우([release+8, release+24]) 내의
/// 인접 BallDetection 쌍을 미터 공간으로 투영하여 속도를 계산한다.
class SpeedEstimatorService {
  /// release 이후 안정 구간 시작 오프셋 (프레임)
  static const int _flightStartOffset = 8;

  /// release 이후 비행 윈도우 종료 오프셋 (프레임)
  static const int _flightEndOffset = 24;

  /// 유효 샘플 최소 개수
  static const int _minSamples = 8;

  /// 허용 최소 속도 (km/h)
  static const double _minSpeed = 10.0;

  /// 허용 최대 속도 (km/h)
  static const double _maxSpeed = 50.0;

  /// 호모그래피 기반 속도 추정
  ///
  /// [release]: 릴리즈 감지 결과
  /// [detections]: 프레임별 볼 감지 결과 (null = 미감지)
  /// [homography]: 프레임→레인 좌표 변환 행렬
  /// [sampleFps]: 영상 프레임레이트 (fps)
  SpeedResult estimate({
    required ReleaseResult release,
    required List<BallDetection?> detections,
    required HomographyMatrix homography,
    required int sampleFps,
  }) {
    // 1. 릴리즈 미감지
    if (!release.isFound) {
      debugPrint('[SpeedEstimator] 릴리즈 미감지');
      return SpeedResult.failed(SpeedFailure.releaseNotFound);
    }

    // 2. 비행 윈도우 계산
    final flightStart = release.frame + _flightStartOffset;
    final flightEnd =
        (release.frame + _flightEndOffset).clamp(0, detections.length - 1);

    if (flightStart >= flightEnd) {
      debugPrint(
        '[SpeedEstimator] 비행 윈도우 범위 오류: start=$flightStart end=$flightEnd',
      );
      return SpeedResult.failed(SpeedFailure.outOfRange);
    }

    // 3. 인접 프레임 쌍으로부터 속도 샘플 수집
    final samples = <double>[];
    for (var i = flightStart + 1; i <= flightEnd; i++) {
      final prev = detections[i - 1];
      final curr = detections[i];
      if (prev == null || curr == null) continue;

      final prevLane =
          homography.frameToLane(FramePoint(nx: prev.cx, ny: prev.cy));
      final currLane =
          homography.frameToLane(FramePoint(nx: curr.cx, ny: curr.cy));

      final dx = currLane.xM - prevLane.xM;
      final dy = currLane.yM - prevLane.yM;
      final distM = sqrt(dx * dx + dy * dy);
      final speedMs = distM * sampleFps;
      samples.add(speedMs);
    }

    // 4. 샘플 부족
    if (samples.length < _minSamples) {
      debugPrint('[SpeedEstimator] 샘플 부족: ${samples.length}개');
      return SpeedResult.failed(SpeedFailure.lowConfidence);
    }

    // 5. 중앙값 계산 → km/h 변환
    samples.sort();
    final medianMs = samples[samples.length ~/ 2];
    final kmh = medianMs * 3.6;

    // 6. 속도 범위 검증
    if (kmh < _minSpeed || kmh > _maxSpeed) {
      debugPrint('[SpeedEstimator] 속도 범위 초과: ${kmh.toStringAsFixed(1)}km/h');
      return SpeedResult.failed(SpeedFailure.outOfRange);
    }

    // 7. 신뢰도 계산
    final windowSize = flightEnd - flightStart;
    final confidence = (samples.length / windowSize).clamp(0.0, 1.0);

    // 8. 소수점 1자리 반올림
    final rounded = double.parse(kmh.toStringAsFixed(1));
    debugPrint(
      '[SpeedEstimator] $rounded km/h, conf=$confidence, samples=${samples.length}',
    );
    return SpeedResult.success(rounded, confidence);
  }
}
