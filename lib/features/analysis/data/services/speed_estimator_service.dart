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
  // 파울라인 통과 프레임(foulCrossFrame)의 유효성 윈도우 — 릴리즈 프레임
  // 근방이어야 물리적으로 말이 된다(파울라인은 릴리즈 직전후에 지나간다).
  // 크게 벗어나면 회귀가 오염된 것으로 보고 이벤트-시간을 포기한다.
  static const int _foulCrossWindowBeforeRelease = 45;
  static const int _foulCrossWindowAfterRelease = 15;
  // 이벤트-시간-회귀 교차검증 허용 오차. 이 비율을 넘으면 두 방식이 유의하게
  // 어긋난 것으로 보고 confidence에 추가 페널티를 준다.
  static const double _crossCheckToleranceRatio = 0.15;
  static const double _crossCheckMismatchPenalty = 0.75;

  /// 정제 궤적([refineTrajectory] 결과 — 중앙값 필터+선두 트림+단조 필터+
  /// 스무딩 완료)에 단순 선형회귀 y = a + b·frame을 적합해 구속을 산출한다.
  /// x 방향(훅 횡이동)은 전체 이동거리의 2% 미만이라 무시하고 y(레인 진행방향)
  /// 만으로 회귀한다.
  ///
  /// **이벤트-시간 코어가 primary인 이유**: 캘리브레이션(픽셀→미터 스케일)은
  /// 시도마다 ±30% 요동해 구속 절대값의 근거로 신뢰할 수 없다. 이벤트-시간은
  /// 구속을 물리 상수(핀덱 18.29m) ÷ (핀 폭발 시각 − 파울라인 통과 시각)으로
  /// 정의해 이 문제를 수학적으로 우회한다. 파울라인 통과 시각은 회귀직선
  /// y=a+b·f의 y=0 근(f₀ = −a/b)이다. 캘리브레이션 스케일에 오류 s가 있어
  /// 측정 y'이 실제 y의 s배로 부풀거나 줄어들면(y' = s·y), 회귀는 그 스케일을
  /// 그대로 흡수해 a'=s·a, b'=s·b가 된다. 근을 다시 구하면
  /// −a'/b' = −(s·a)/(s·b) = −a/b — s가 완전히 약분되어 **근(f₀)은 스케일과
  /// 무관하게 불변**이다. 핀 폭발 시각(impact.frame)도 호모그래피 투영이 아니라
  /// 핀 자체의 시각적 변화(밝기 변화 등)로 감지하므로 마찬가지로 스케일과
  /// 무관하다. 따라서 이벤트-시간 구속 = 18.29 / ((impact.frame − f₀) / fps)은
  /// 두 항 모두 캘리브레이션 오류에 물들지 않는다. 캘리브레이션은 이제 궤적을
  /// 화면에 그리는 시각화 전용으로 강등되고, 구속 산출과는 수학적으로 분리된다.
  ///
  /// 회귀 자체(a, b, R²)는 f₀ 산출의 재료이자 이벤트-시간을 못 쓸 때의
  /// 폴백(impact.confidence가 low일 때, 또는 f₀가 물리적으로 말이 안 될 때)
  /// 으로 유지한다.
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

    // 이벤트-시간 구속: 파울라인 통과 프레임(f₀ = 회귀직선의 y=0 근)부터
    // 실제 핀 폭발 시각(impact.frame)까지 걸린 시간으로 물리 상수(핀덱
    // 18.29m)를 나눈다. impact.confidence가 low가 아닐 때만(= 핀 신호 기반
    // 프레임일 때만) 신뢰할 수 있다. 유효성 가드:
    //  - b>0: 궤적이 전진(레인 진행방향) 중이어야 근이 의미 있다.
    //  - f₀ < impact.frame: 통과가 폭발보다 앞서야 비행시간이 양수다.
    //  - f₀가 릴리즈 프레임 근방(release-45 ~ release+15)이어야 한다. 파울
    //    라인은 릴리즈 직전후에 지나가므로, 회귀가 오염돼 근이 크게 벗어나면
    //    (예: 궤적 후반 노이즈에 회귀가 끌려간 경우) 이벤트-시간을 포기한다.
    double? eventKmh;
    double? foulCrossFrame;
    if (b != 0) {
      // 진단 출력용으로 부호와 무관하게 근을 구해두되, 실제 채택(eventKmh)은
      // 아래 유효성 가드를 모두 통과한 impact.confidence != low 케이스에서만.
      foulCrossFrame = -a / b;
    }
    if (impact.confidence != ImpactConfidence.low && b > 0 && foulCrossFrame != null) {
      final flightFrames = impact.frame - foulCrossFrame;
      final windowStart = release.frame - _foulCrossWindowBeforeRelease;
      final windowEnd = release.frame + _foulCrossWindowAfterRelease;
      if (flightFrames > 0 && foulCrossFrame >= windowStart && foulCrossFrame <= windowEnd) {
        eventKmh = _pinDeckYM / (flightFrames / sampleFps) * 3.6;
      }
    }

    // 채택 규칙: 이벤트-시간을 계산할 수 있으면 primary(캘리브레이션 스케일과
    // 무관 — 클래스 docstring 참조)이고 회귀는 교차검증 신호로만 쓴다. 두
    // 값이 유의하게(15% 초과) 어긋나면 자기일관성이 없다는 뜻이므로
    // confidence에 추가 페널티를 준다. 이벤트-시간을 계산할 수 없으면(impact
    // low, 또는 f₀가 물리적으로 말이 안 됨) 회귀를 그대로 primary로 쓴다.
    final String method;
    final double adoptedKmh;
    var crossCheckPenalty = 1.0;
    if (eventKmh != null) {
      method = '이벤트시간';
      adoptedKmh = eventKmh;
      final mismatchRatio = (regressionKmh - eventKmh).abs() / eventKmh;
      if (mismatchRatio > _crossCheckToleranceRatio) {
        crossCheckPenalty = _crossCheckMismatchPenalty;
        debugPrint('[SpeedEstimator] 회귀-이벤트시간 교차검증 불일치 '
            '(회귀 ${regressionKmh.toStringAsFixed(1)}km/h vs 이벤트시간 '
            '${eventKmh.toStringAsFixed(1)}km/h, 차이 ${(mismatchRatio * 100).toStringAsFixed(1)}% > '
            '${(_crossCheckToleranceRatio * 100).toStringAsFixed(0)}%, confidence ×$_crossCheckMismatchPenalty)');
      }
    } else {
      method = '회귀';
      adoptedKmh = regressionKmh;
    }

    // 범위 가드는 최종 채택값(이벤트-시간 또는 회귀)에 적용한다.
    if (adoptedKmh < _minSpeed || adoptedKmh > _maxSpeed) {
      debugPrint('[SpeedEstimator] 측정불가: 채택 속도 범위 밖 '
          '(방식 $method, ${adoptedKmh.toStringAsFixed(1)}km/h, 허용 10~50)');
      return SpeedResult.failed(SpeedFailure.outOfRange);
    }

    // 임팩트 신호는 "분석 전반이 자기일관적인가"를 보여주는 지표다.
    // impact.confidence가 low이면 이벤트-시간 자체를 계산하지 않고 회귀로
    // 폴백하므로(위 유효성 가드), 여기서는 이벤트-시간이 채택된 경우에도
    // 그 근거(핀 감지 확실성)를 confidence에 추가로 반영한다.
    final impactPenalty = switch (impact.confidence) {
      ImpactConfidence.high => 1.0,
      ImpactConfidence.medium => 0.85,
      ImpactConfidence.low => 0.7,
    };
    final confidence =
        (rSquared * impactPenalty * release.confidence * crossCheckPenalty).clamp(0.0, 1.0);

    final rounded = double.parse(adoptedKmh.toStringAsFixed(1));
    debugPrint('[SpeedEstimator] 구속 ${rounded}km/h '
        '(방식: $method, 파울라인통과 f=${foulCrossFrame == null ? "없음" : foulCrossFrame.toStringAsFixed(1)}, '
        '폭발 f=${impact.frame}, 회귀 ${regressionKmh.toStringAsFixed(1)}, '
        'R² ${rSquared.toStringAsFixed(2)}, n=$n, impact ${impact.confidence.name}, '
        'confidence ${confidence.toStringAsFixed(2)})');
    return SpeedResult.success(rounded, confidence);
  }
}
