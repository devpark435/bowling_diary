import 'package:flutter/foundation.dart';

import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
import 'package:bowling_diary/features/analysis/domain/services/trajectory_refiner.dart';

class SpeedEstimatorService {
  static const int _minSamples = 8;
  static const double _minYSpanM = 5.0;
  static const int _minFrameSpan = 15;
  static const double _minSpeed = 10.0;
  static const double _maxSpeed = 50.0;

  /// 정제 궤적([refineTrajectory] 결과 — 중앙값 필터+선두 트림+단조 필터+
  /// 스무딩 완료)에 단순 선형회귀를 적합해 구속을 산출한다.
  ///
  /// 이전 구현은 release+8~24 프레임 구간의 원시 검출 좌표로 프레임간 이동거리
  /// 중앙값을 냈으나, 이 구간(레인 2~8m)은 검출 y 지터가 ±0.5m/frame에 달해
  /// 거리 절댓값이 부풀려지는(±노이즈가 전부 +로 합산되는) 계통적 과대추정
  /// 문제가 있었다. 회귀 기울기는 지터가 양방향으로 상쇄되므로 훨씬 강건하다.
  /// x 방향(훅 횡이동)은 전체 이동거리의 2% 미만이라 무시하고 y(레인 진행방향)
  /// 만으로 y = a + b·frame을 적합한다.
  SpeedResult estimate({
    required ReleaseResult release,
    required ImpactResult impact,
    required List<TrajectorySample> refinedTrajectory,
    required int sampleFps,
  }) {
    if (!release.isFound) {
      return SpeedResult.failed(SpeedFailure.releaseNotFound);
    }

    if (impact.confidence == ImpactConfidence.low) {
      debugPrint('[SpeedEstimator] impact 신호 불일치(low confidence) — 강제 채택 안 함');
      return SpeedResult.failed(SpeedFailure.anchorMismatch);
    }

    final n = refinedTrajectory.length;
    if (n < _minSamples) {
      debugPrint('[SpeedEstimator] 측정불가: 정제 궤적 포인트 부족 (n=$n, 최소 $_minSamples)');
      return SpeedResult.failed(SpeedFailure.lowConfidence);
    }

    final ySpan = refinedTrajectory.last.lane.yM - refinedTrajectory.first.lane.yM;
    final frameSpan = refinedTrajectory.last.frame - refinedTrajectory.first.frame;
    if (ySpan < _minYSpanM || frameSpan < _minFrameSpan) {
      debugPrint('[SpeedEstimator] 측정불가: 궤적 구간 부족 '
          '(y스팬 ${ySpan.toStringAsFixed(2)}m, 프레임스팬 $frameSpan)');
      return SpeedResult.failed(SpeedFailure.lowConfidence);
    }

    final fBar = refinedTrajectory.map((s) => s.frame).reduce((a, b) => a + b) / n;
    final yBar = refinedTrajectory.map((s) => s.lane.yM).reduce((a, b) => a + b) / n;

    var num = 0.0;
    var den = 0.0;
    for (final s in refinedTrajectory) {
      final df = s.frame - fBar;
      num += df * (s.lane.yM - yBar);
      den += df * df;
    }
    final b = den == 0.0 ? 0.0 : num / den;

    final speedMs = b * sampleFps;
    final kmh = speedMs * 3.6;

    if (kmh < _minSpeed || kmh > _maxSpeed) {
      debugPrint('[SpeedEstimator] 측정불가: 회귀 속도 범위 밖 '
          '(${kmh.toStringAsFixed(1)}km/h, 허용 10~50)');
      return SpeedResult.failed(SpeedFailure.outOfRange);
    }

    final a = yBar - b * fBar;
    var ssRes = 0.0;
    var ssTot = 0.0;
    for (final s in refinedTrajectory) {
      final predicted = a + b * s.frame;
      final residual = s.lane.yM - predicted;
      ssRes += residual * residual;
      final diff = s.lane.yM - yBar;
      ssTot += diff * diff;
    }
    final rSquared = ssTot == 0.0 ? 0.0 : (1 - ssRes / ssTot);

    final impactPenalty = impact.confidence == ImpactConfidence.medium ? 0.85 : 1.0;
    final confidence = (rSquared * impactPenalty * release.confidence).clamp(0.0, 1.0);

    final rounded = double.parse(kmh.toStringAsFixed(1));
    debugPrint('[SpeedEstimator] 구속 ${rounded}km/h '
        '(회귀 R² ${rSquared.toStringAsFixed(2)}, n=$n, confidence ${confidence.toStringAsFixed(2)})');
    return SpeedResult.success(rounded, confidence);
  }
}
