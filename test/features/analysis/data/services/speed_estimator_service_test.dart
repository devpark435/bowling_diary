import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
import 'package:bowling_diary/features/analysis/domain/services/trajectory_refiner.dart';
import 'package:flutter_test/flutter_test.dart';

const _highConfImpact = ImpactResult(frame: 100, confidence: ImpactConfidence.high);
const _mediumConfImpact = ImpactResult(frame: 100, confidence: ImpactConfidence.medium);
const _lowConfImpact = ImpactResult(frame: 100, confidence: ImpactConfidence.low);
const _release = ReleaseResult(frame: 40, confidence: 0.9);

/// y=3.0+0.25*(f-40) 직선(기울기 0.25m/frame, 30fps → 27.0km/h). 프레임
/// 40~100(61포인트, 프레임 간격 1)로 인위적으로 정제 궤적을 구성한다 —
/// refineTrajectory가 이미 처리한 결과를 흉내낸 것이므로 여기서는 잡음 없는
/// 직선을 그대로 사용한다. 이 직선의 y=0 근(f₀)은 28.0(=40-12)이며, 릴리즈
/// 프레임(40) 근방 윈도(-5~55) 안에 들어와 이벤트-시간이 채택된다.
List<TrajectorySample> _linearTrajectory({double noiseAmplitude = 0.0}) {
  final result = <TrajectorySample>[];
  for (var i = 0; i < 61; i++) {
    final frame = 40 + i;
    var y = 3.0 + 0.25 * (frame - 40);
    if (noiseAmplitude != 0.0) {
      y += i.isEven ? noiseAmplitude : -noiseAmplitude;
    }
    result.add((frame: frame, lane: LanePoint(xM: 0.5, yM: y)));
  }
  return result;
}

/// 이벤트-시간 테스트 전용 궤적 생성기 — 첫 포인트 프레임/y와 회귀 기울기를
/// 자유롭게 지정한다(잡음 없는 완전 직선, refineTrajectory가 이미 처리한
/// 결과를 흉내).
List<TrajectorySample> _trajectoryFrom({
  required int startFrame,
  required double startY,
  required double slope,
  int count = 61,
}) {
  final result = <TrajectorySample>[];
  for (var i = 0; i < count; i++) {
    result.add((frame: startFrame + i, lane: LanePoint(xM: 0.5, yM: startY + slope * i)));
  }
  return result;
}

void main() {
  final svc = SpeedEstimatorService();

  group('SpeedEstimatorService', () {
    test('정제 궤적 선형회귀: 기울기 0.25m/frame(회귀 27.0km/h) → impact가 low가 아니므로 '
        '이벤트-시간(f₀=28.0, 폭발 f=100까지 72프레임 → 18.29/(72/30)*3.6)이 채택돼 27.4km/h, '
        '회귀와 이벤트-시간 차이 1.6%<15%라 페널티 없음', () {
      final r = svc.estimate(
        release: _release,
        impact: _highConfImpact,
        refinedTrajectory: _linearTrajectory(),
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(27.4, 0.1));
      expect(r.confidence, closeTo(_release.confidence, 0.01));
    });

    test('지터 강건성: y에 ±0.15 교대 노이즈를 줘도 채택 속도는 27.0±1.0 안에 남는다 '
        '(대칭 노이즈는 회귀 a,b를 거의 왜곡하지 않으므로 f₀도, 그로부터 산출되는 '
        '이벤트-시간 구속도 강건하다)', () {
      final r = svc.estimate(
        release: _release,
        impact: _highConfImpact,
        refinedTrajectory: _linearTrajectory(noiseAmplitude: 0.15),
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(27.0, 1.0));
    });

    test('release 없으면 releaseNotFound', () {
      final r = svc.estimate(
        release: ReleaseResult.notFound,
        impact: _highConfImpact,
        refinedTrajectory: const [],
        sampleFps: 30,
      );
      expect(r.failure, SpeedFailure.releaseNotFound);
    });

    test('impact confidence가 low이면 이벤트-시간을 계산하지 않고 회귀로 폴백하되 '
        'confidence는 high 대비 0.7배', () {
      final trajectory = _linearTrajectory();
      final high = svc.estimate(
        release: _release,
        impact: _highConfImpact,
        refinedTrajectory: trajectory,
        sampleFps: 30,
      );
      final low = svc.estimate(
        release: _release,
        impact: _lowConfImpact,
        refinedTrajectory: trajectory,
        sampleFps: 30,
      );

      expect(low.failure, isNull);
      expect(low.kmh, closeTo(27.0, 0.1));
      expect(low.confidence, closeTo(high.confidence * 0.7, 0.01));
    });

    test('정제 궤적 포인트가 8개 미만이면 lowConfidence', () {
      final trajectory = <TrajectorySample>[
        for (var i = 0; i < 5; i++) (frame: 40 + i, lane: LanePoint(xM: 0.5, yM: 3.0 + i.toDouble())),
      ];
      final r = svc.estimate(
        release: _release,
        impact: _highConfImpact,
        refinedTrajectory: trajectory,
        sampleFps: 30,
      );
      expect(r.failure, SpeedFailure.lowConfidence);
    });

    test('포인트는 10개로 충분해도 y 스팬이 2m뿐이면 궤적 구간 부족으로 lowConfidence', () {
      final trajectory = <TrajectorySample>[
        for (var i = 0; i < 10; i++)
          (frame: 40 + i, lane: LanePoint(xM: 0.5, yM: 3.0 + i * (2.0 / 9))),
      ];
      final r = svc.estimate(
        release: _release,
        impact: _highConfImpact,
        refinedTrajectory: trajectory,
        sampleFps: 30,
      );
      expect(r.failure, SpeedFailure.lowConfidence);
    });

    test('회귀 속도가 50km/h 상한을 넘으면 outOfRange (범위 가드는 최종 채택값에 적용 — '
        'impact low로 이벤트-시간 없이 회귀가 그대로 채택되는 경우로 구성)', () {
      final trajectory = <TrajectorySample>[
        for (var i = 0; i <= 30; i++) (frame: i, lane: LanePoint(xM: 0.5, yM: 0.6 * i)),
      ];
      final r = svc.estimate(
        release: _release,
        impact: _lowConfImpact,
        refinedTrajectory: trajectory,
        sampleFps: 30,
      );
      expect(r.failure, SpeedFailure.outOfRange);
    });

    test('impact medium이면 confidence가 high 대비 0.85배', () {
      final trajectory = _linearTrajectory();
      final high = svc.estimate(
        release: _release,
        impact: _highConfImpact,
        refinedTrajectory: trajectory,
        sampleFps: 30,
      );
      final medium = svc.estimate(
        release: _release,
        impact: _mediumConfImpact,
        refinedTrajectory: trajectory,
        sampleFps: 30,
      );

      expect(medium.confidence, closeTo(high.confidence * 0.85, 0.01));
    });
  });

  group('이벤트-시간 코어(구속 = 18.29m ÷ (폭발 시각 − 파울라인 통과 시각))', () {
    // 공통 궤적: frame 73~113(41포인트), y=0.25*(f-70). 회귀 y=0.25*(f-70)의
    // y=0 근은 정확히 f₀=70.0 — 파울라인 통과 프레임이 정수로 딱 떨어지도록
    // 구성해 손계산 검증을 쉽게 했다. release.frame=75로 두면 유효성 윈도
    // (75-45=30 ~ 75+15=90)에 f₀=70이 들어온다.
    const release75 = ReleaseResult(frame: 75, confidence: 0.9);
    List<TrajectorySample> baseTrajectory({double scale = 1.0}) => _trajectoryFrom(
          startFrame: 73,
          startY: 0.25 * scale * 3, // f=73일 때 y = 0.25*scale*(73-70)
          slope: 0.25 * scale,
          count: 41,
        );

    test('이벤트-시간 기본: 폭발 f=149 → flight=149-70=79프레임 → '
        '18.29/(79/30)*3.6=25.0km/h (회귀값 27.0과 달라 이벤트-시간이 채택됐음을 값으로 확인)', () {
      final r = svc.estimate(
        release: release75,
        impact: const ImpactResult(frame: 149, confidence: ImpactConfidence.high),
        refinedTrajectory: baseTrajectory(),
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(25.0, 0.1));
      expect(r.kmh, isNot(closeTo(27.0, 0.3))); // 회귀값(27.0)과는 다른 값이 채택됨.
    });

    test('스케일 불변(핵심 성질 박제): 궤적 y를 전부 ×0.6 해도 구속은 동일 25.0 '
        '(회귀 a,b가 같은 비율로 스케일되어 근 f₀=-a/b가 불변 — 이 테스트가 깨지면 '
        '캘리브레이션 독립성이 깨진 것)', () {
      final r = svc.estimate(
        release: release75,
        impact: const ImpactResult(frame: 149, confidence: ImpactConfidence.high),
        refinedTrajectory: baseTrajectory(scale: 0.6),
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(25.0, 0.01));
    });

    test('impact low → 이벤트-시간을 계산하지 않고 회귀(27.0km/h)로 폴백', () {
      final r = svc.estimate(
        release: release75,
        impact: const ImpactResult(frame: 149, confidence: ImpactConfidence.low),
        refinedTrajectory: baseTrajectory(),
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(27.0, 0.1));
    });

    test('foulCross 유효성 실패(f₀=70이 release.frame=300의 윈도 255~315 밖) → '
        '회귀(27.0km/h)로 폴백', () {
      const releaseFar = ReleaseResult(frame: 300, confidence: 0.9);
      final r = svc.estimate(
        release: releaseFar,
        impact: const ImpactResult(frame: 149, confidence: ImpactConfidence.high),
        refinedTrajectory: baseTrajectory(),
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(27.0, 0.1));
    });

    test('불일치 페널티: 폭발 f=120 → flight=50프레임 → 이벤트-시간 39.5km/h vs 회귀 27.0km/h '
        '(차이 31.7%>15%) → confidence ×0.75', () {
      final withPenalty = svc.estimate(
        release: release75,
        impact: const ImpactResult(frame: 120, confidence: ImpactConfidence.high),
        refinedTrajectory: baseTrajectory(),
        sampleFps: 30,
      );
      final noPenalty = svc.estimate(
        release: release75,
        impact: const ImpactResult(frame: 149, confidence: ImpactConfidence.high),
        refinedTrajectory: baseTrajectory(),
        sampleFps: 30,
      );

      expect(withPenalty.failure, isNull);
      expect(withPenalty.kmh, closeTo(39.5, 0.1));
      expect(noPenalty.failure, isNull);
      expect(withPenalty.confidence, closeTo(noPenalty.confidence * 0.75, 0.02));
    });

    test('범위 가드: 폭발 f=106 → flight=36프레임 → 이벤트-시간 54.9km/h(50 상한 초과) → '
        'outOfRange', () {
      final r = svc.estimate(
        release: release75,
        impact: const ImpactResult(frame: 106, confidence: ImpactConfidence.high),
        refinedTrajectory: baseTrajectory(),
        sampleFps: 30,
      );

      expect(r.failure, SpeedFailure.outOfRange);
    });
  });
}
