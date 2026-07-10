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
  // 핀덱 물리 상수(레인 규격) — 파울라인부터 핀덱까지의 거리.
  static const double _pinDeckYM = 18.29;
  // 회귀-앵커 교차검증 허용 오차. 이 비율을 넘으면 두 방식이 유의하게
  // 어긋난 것으로 보고 confidence에 추가 페널티를 준다.
  static const double _crossCheckToleranceRatio = 0.15;
  static const double _crossCheckMismatchPenalty = 0.75;

  /// 정제 궤적([refineTrajectory] 결과 — 중앙값 필터+선두 트림+단조 필터+
  /// 스무딩 완료)에 단순 선형회귀를 적합해 구속을 산출한다.
  ///
  /// 이전 구현은 release+8~24 프레임 구간의 원시 검출 좌표로 프레임간 이동거리
  /// 중앙값을 냈으나, 이 구간(레인 2~8m)은 검출 y 지터가 ±0.5m/frame에 달해
  /// 거리 절댓값이 부풀려지는(±노이즈가 전부 +로 합산되는) 계통적 과대추정
  /// 문제가 있었다. 회귀 기울기는 지터가 양방향으로 상쇄되므로 훨씬 강건하다.
  /// x 방향(훅 횡이동)은 전체 이동거리의 2% 미만이라 무시하고 y(레인 진행방향)
  /// 만으로 y = a + b·frame을 적합한다.
  ///
  /// **앵커 방식이 primary인 이유**: 회귀는 호모그래피가 투영한 궤적 전체의
  /// y좌표에 의존하는데, 광각 렌즈+원거리 원근 민감도 때문에 레인을 따라
  /// 갈수록 측정 y가 실제보다 늘어나는 스케일 왜곡이 존재한다(근거리 에로우
  /// 4.57m는 검증됐지만 원거리는 아니다). 이 왜곡은 회귀 기울기를 계통적으로
  /// 과대추정시킨다(실측 사례: 손계산 31km/h vs 회귀 37.8km/h). 반면 앵커는
  /// 근거리(캘리브레이션 신뢰 구간)에서 측정한 릴리즈 직후 y와, 물리
  /// 상수(핀덱 18.29m) + 실제 핀 폭발 프레임(호모그래피 왜곡과 무관하게
  /// 핀 자체의 시각적 변화로 감지)만을 쓰므로 이 왜곡에 강건하다. 그래서
  /// 앵커를 계산할 수 있을 때는(impact confidence가 low가 아닐 때) 앵커를
  /// primary로 채택하고, 회귀는 교차검증 신호로만 쓴다.
  SpeedResult estimate({
    required ReleaseResult release,
    required ImpactResult impact,
    required List<TrajectorySample> refinedTrajectory,
    required int sampleFps,
  }) {
    if (!release.isFound) {
      return SpeedResult.failed(SpeedFailure.releaseNotFound);
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
    final regressionKmh = speedMs * 3.6;

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

    // 앵커 속도: 근거리(캘리브레이션 신뢰 구간)에서 측정한 릴리즈 직후 y부터
    // 핀덱(물리 상수 18.29m)까지의 거리를, 실제 핀 폭발 시각(impact.frame)까지
    // 걸린 시간으로 나눈다. impact.confidence가 low가 아닐 때만(= 핀 신호
    // 기반 프레임일 때만) 신뢰할 수 있고, 분모(anchorFrames)나 거리
    // (anchorDistM)가 물리적으로 말이 안 되면(공이 이미 핀덱을 지났거나
    // impact가 첫 관측 프레임보다 앞이거나 같으면) 앵커를 계산하지 않는다.
    double? anchorKmh;
    if (impact.confidence != ImpactConfidence.low) {
      final firstSample = refinedTrajectory.first;
      final anchorDistM = _pinDeckYM - firstSample.lane.yM;
      final anchorFrames = impact.frame - firstSample.frame;
      if (anchorFrames > 0 && anchorDistM > 0) {
        anchorKmh = anchorDistM / (anchorFrames / sampleFps) * 3.6;
      }
    }

    // 채택 규칙: 앵커를 계산할 수 있으면 앵커가 primary(스케일 왜곡에 강건 —
    // 클래스 docstring 참조)이고 회귀는 교차검증 신호로만 쓴다. 두 값이
    // 유의하게(15% 초과) 어긋나면 자기일관성이 없다는 뜻이므로 confidence에
    // 추가 페널티를 준다. 앵커를 계산할 수 없으면(impact low 등) 회귀를
    // 그대로 primary로 쓴다(기존 동작).
    final String method;
    final double adoptedKmh;
    var crossCheckPenalty = 1.0;
    if (anchorKmh != null) {
      method = '앵커';
      adoptedKmh = anchorKmh;
      final mismatchRatio = (regressionKmh - anchorKmh).abs() / anchorKmh;
      if (mismatchRatio > _crossCheckToleranceRatio) {
        crossCheckPenalty = _crossCheckMismatchPenalty;
        debugPrint('[SpeedEstimator] 회귀-앵커 교차검증 불일치 '
            '(회귀 ${regressionKmh.toStringAsFixed(1)}km/h vs 앵커 '
            '${anchorKmh.toStringAsFixed(1)}km/h, 차이 ${(mismatchRatio * 100).toStringAsFixed(1)}% > '
            '${(_crossCheckToleranceRatio * 100).toStringAsFixed(0)}%, confidence ×$_crossCheckMismatchPenalty)');
      }
    } else {
      method = '회귀';
      adoptedKmh = regressionKmh;
    }

    // 범위 가드는 최종 채택값(앵커 또는 회귀)에 적용한다.
    if (adoptedKmh < _minSpeed || adoptedKmh > _maxSpeed) {
      debugPrint('[SpeedEstimator] 측정불가: 채택 속도 범위 밖 '
          '(방식 $method, ${adoptedKmh.toStringAsFixed(1)}km/h, 허용 10~50)');
      return SpeedResult.failed(SpeedFailure.outOfRange);
    }

    // 회귀는 정제 궤적 전체를 대상으로 하며 임팩트 프레임 자체를 계산에 쓰지
    // 않는다 — 옛 앵커 산식(release→impact 거리/시간)에서는 임팩트 프레임이
    // 계산의 필수 입력이라 confidence가 낮으면(핀 감지 불확실) 결과 자체를
    // 하드 게이트로 거부했지만, 지금은 그 이유가 사라졌다. 임팩트 신호는
    // 이제 "분석 전반이 자기일관적인가"를 보여주는 보조 지표일 뿐이므로
    // 거부 사유가 아니라 신뢰도 차감 사유로만 반영한다.
    final impactPenalty = switch (impact.confidence) {
      ImpactConfidence.high => 1.0,
      ImpactConfidence.medium => 0.85,
      ImpactConfidence.low => 0.7,
    };
    final confidence =
        (rSquared * impactPenalty * release.confidence * crossCheckPenalty).clamp(0.0, 1.0);

    final rounded = double.parse(adoptedKmh.toStringAsFixed(1));
    debugPrint('[SpeedEstimator] 구속 ${rounded}km/h '
        '(방식: $method, 회귀 ${regressionKmh.toStringAsFixed(1)}, '
        '앵커 ${anchorKmh == null ? "없음" : anchorKmh.toStringAsFixed(1)}, '
        'R² ${rSquared.toStringAsFixed(2)}, n=$n, impact ${impact.confidence.name}, '
        'confidence ${confidence.toStringAsFixed(2)})');
    return SpeedResult.success(rounded, confidence);
  }
}
