import 'dart:ui';

import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SpeedEstimatorService sut;
  setUp(() => sut = SpeedEstimatorService());

  ImpactResult impact(int frame, double conf) => ImpactResult(
      frame: frame,
      roi: const Rect.fromLTWH(0, 0, 100, 100),
      confidence: conf);

  test('정상 입력 — 속도 32.9km/h 근접 계산', () {
    final speed = sut.estimate(
      release: const ReleaseResult(frame: 0, confidence: 1.0),
      impact: impact(60, 1.0),
      sampleFps: 30,
    );
    expect(speed.kmh, closeTo(32.9, 0.5));
    expect(speed.failure, isNull);
    expect(speed.confidence, equals(1.0));
  });

  test('release 미감지 시 releaseNotFound', () {
    final speed = sut.estimate(
      release: ReleaseResult.notFound,
      impact: impact(60, 1.0),
      sampleFps: 30,
    );
    expect(speed.kmh, isNull);
    expect(speed.failure, equals(SpeedFailure.releaseNotFound));
  });

  test('impact 미감지 시 impactNotFound', () {
    final speed = sut.estimate(
      release: const ReleaseResult(frame: 0, confidence: 1.0),
      impact: ImpactResult.notFound,
      sampleFps: 30,
    );
    expect(speed.kmh, isNull);
    expect(speed.failure, equals(SpeedFailure.impactNotFound));
  });

  test('범위 초과(과속) → outOfRange', () {
    final speed = sut.estimate(
      release: const ReleaseResult(frame: 0, confidence: 1.0),
      impact: impact(10, 1.0),
      sampleFps: 30,
    );
    expect(speed.kmh, isNull);
    expect(speed.failure, equals(SpeedFailure.outOfRange));
  });

  test('범위 초과(느림) → outOfRange', () {
    final speed = sut.estimate(
      release: const ReleaseResult(frame: 0, confidence: 1.0),
      impact: impact(600, 1.0),
      sampleFps: 30,
    );
    expect(speed.failure, equals(SpeedFailure.outOfRange));
  });

  test('confidence < 0.3 → lowConfidence', () {
    final speed = sut.estimate(
      release: const ReleaseResult(frame: 0, confidence: 0.2),
      impact: impact(60, 1.0),
      sampleFps: 30,
    );
    expect(speed.kmh, isNull);
    expect(speed.failure, equals(SpeedFailure.lowConfidence));
  });

  test('confidence는 release/impact 중 작은 값', () {
    final speed = sut.estimate(
      release: const ReleaseResult(frame: 0, confidence: 0.8),
      impact: impact(60, 0.6),
      sampleFps: 30,
    );
    expect(speed.confidence, equals(0.6));
  });
}
