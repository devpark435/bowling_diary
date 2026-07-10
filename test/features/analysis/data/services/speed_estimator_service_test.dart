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
/// 직선을 그대로 사용한다.
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

/// 앵커 테스트 전용 궤적 생성기 — 첫 포인트 프레임/y와 회귀 기울기를 자유롭게
/// 지정한다(잡음 없는 완전 직선, refineTrajectory가 이미 처리한 결과를 흉내).
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
        '앵커(첫 프레임 40/y=3.0 → 핀덱까지 15.29m, impact 100까지 60프레임)가 채택돼 27.5km/h, '
        '회귀와 앵커 차이 1.9%<15%라 페널티 없음', () {
      final r = svc.estimate(
        release: _release,
        impact: _highConfImpact,
        refinedTrajectory: _linearTrajectory(),
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(27.5, 0.1));
      expect(r.confidence, greaterThan(0));
    });

    test('지터 강건성: y에 ±0.15 교대 노이즈를 줘도 회귀 속도는 27.0±1.0 안에 남는다 '
        '(프레임간 이동거리 중앙값 방식이었다면 노이즈가 거리 절댓값을 부풀려 과대추정했을 데이터)', () {
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

    test('impact confidence가 low여도 회귀는 임팩트 프레임을 쓰지 않으므로 성공하되 '
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
        'impact low로 앵커 없이 회귀가 그대로 채택되는 경우로 구성)', () {
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

  group('앵커 기반 구속(핀 폭발 시각 + 물리 거리)', () {
    test('앵커 primary: 회귀(37.8km/h 상당)와 15% 초과로 어긋나면 앵커(29.5km/h)가 채택되고 '
        'confidence에 교차검증 페널티(×0.75)가 적용된다', () {
      // 첫 포인트 frame=70, y=3.0m. impact.frame=126 → anchorFrames=56.
      // anchorDistM = 18.29 - 3.0 = 15.29m. anchorKmh = 15.29/(56/30)*3.6 = 29.48… → 29.5.
      const impact = ImpactResult(frame: 126, confidence: ImpactConfidence.high);
      final trajectory = _trajectoryFrom(startFrame: 70, startY: 3.0, slope: 0.35); // 회귀 37.8km/h 상당

      final r = svc.estimate(
        release: _release,
        impact: impact,
        refinedTrajectory: trajectory,
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(29.5, 0.1));

      // 페널티 없는(회귀-앵커 일치) 경우와 비교해 confidence가 ×0.75 수준으로 낮음을 확인.
      final noPenaltyTrajectory =
          _trajectoryFrom(startFrame: 70, startY: 3.0, slope: 0.2729); // 앵커와 거의 일치하는 회귀
      final noPenalty = svc.estimate(
        release: _release,
        impact: impact,
        refinedTrajectory: noPenaltyTrajectory,
        sampleFps: 30,
      );
      expect(noPenalty.failure, isNull);
      expect(r.confidence, closeTo(noPenalty.confidence * 0.75, 0.02));
    });

    test('회귀와 앵커가 일치(차이 15% 이내)하면 교차검증 페널티가 없다', () {
      const impact = ImpactResult(frame: 126, confidence: ImpactConfidence.high);
      // slope 0.2729 → 회귀 ≈29.47km/h, 앵커 29.48km/h와 거의 일치(차이 <15%).
      final trajectory = _trajectoryFrom(startFrame: 70, startY: 3.0, slope: 0.2729);

      final r = svc.estimate(
        release: _release,
        impact: impact,
        refinedTrajectory: trajectory,
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(29.5, 0.2));
      // 페널티가 없으면 confidence ≈ rSquared(≈1) * impactPenalty(high=1.0) * release.confidence(0.9).
      expect(r.confidence, closeTo(_release.confidence, 0.02));
    });

    test('impact confidence가 low면 앵커를 계산하지 않고 회귀를 그대로 채택한다(기존 동작 보존)', () {
      const impact = ImpactResult(frame: 126, confidence: ImpactConfidence.low);
      final trajectory = _trajectoryFrom(startFrame: 70, startY: 3.0, slope: 0.35); // 회귀 37.8km/h 상당

      final r = svc.estimate(
        release: _release,
        impact: impact,
        refinedTrajectory: trajectory,
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(37.8, 0.1)); // 앵커(29.5)가 아니라 회귀값 그대로.
    });

    test('앵커 분모가 0 이하(impact.frame <= 첫 프레임)이면 앵커를 포기하고 회귀로 폴백한다', () {
      // impact.frame(70) == 첫 프레임(70) → anchorFrames = 0 → 앵커 불가.
      const impact = ImpactResult(frame: 70, confidence: ImpactConfidence.high);
      final trajectory = _trajectoryFrom(startFrame: 70, startY: 3.0, slope: 0.35); // 회귀 37.8km/h 상당

      final r = svc.estimate(
        release: _release,
        impact: impact,
        refinedTrajectory: trajectory,
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(37.8, 0.1));
    });
  });
}
