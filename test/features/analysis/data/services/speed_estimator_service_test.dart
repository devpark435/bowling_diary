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

void main() {
  final svc = SpeedEstimatorService();

  group('SpeedEstimatorService', () {
    test('정제 궤적 선형회귀: 기울기 0.25m/frame → 27.0km/h, R²≈1', () {
      final r = svc.estimate(
        release: _release,
        impact: _highConfImpact,
        refinedTrajectory: _linearTrajectory(),
        sampleFps: 30,
      );

      expect(r.failure, isNull);
      expect(r.kmh, closeTo(27.0, 0.1));
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

    test('impact confidence가 low면 anchorMismatch로 실패 (강제로 값 채택 안 함)', () {
      final r = svc.estimate(
        release: _release,
        impact: _lowConfImpact,
        refinedTrajectory: const [],
        sampleFps: 30,
      );
      expect(r.failure, SpeedFailure.anchorMismatch);
      expect(r.kmh, isNull);
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

    test('회귀 속도가 50km/h 상한을 넘으면 outOfRange', () {
      final trajectory = <TrajectorySample>[
        for (var i = 0; i <= 30; i++) (frame: i, lane: LanePoint(xM: 0.5, yM: 0.6 * i)),
      ];
      final r = svc.estimate(
        release: _release,
        impact: _highConfImpact,
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
}
