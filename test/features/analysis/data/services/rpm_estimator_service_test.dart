import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/rpm_estimator_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/rpm_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// LK 알고리즘 자체는 dartcv 네이티브 dylib 의존 → flutter test 환경에서
// 실행 불가. RPM 정확도/결정성 검증은 integration_test로 별도 진행.
// 여기서는 입력 검증 가드만 단위 테스트.

BallDetection _det() => const BallDetection(
      cx: 0.5,
      cy: 0.5,
      bw: 0.95,
      bh: 0.95,
      confidence: 0.95,
    );

void main() {
  late RpmEstimatorService sut;
  setUp(() => sut = RpmEstimatorService());

  test('빈 frames → featureDetectionFailed', () {
    final r = sut.estimate(
        frames: const [],
        detections: const [],
        releaseFrame: 0,
        sampleFps: 60);
    expect(r.rpm, isNull);
    expect(r.failure, equals(RpmFailure.featureDetectionFailed));
  });

  test('잘못된 releaseFrame → featureDetectionFailed', () {
    final frames =
        List.generate(10, (_) => img.Image(width: 50, height: 50));
    final detections = List<BallDetection?>.filled(10, _det());
    final r = sut.estimate(
        frames: frames,
        detections: detections,
        releaseFrame: 999,
        sampleFps: 60);
    expect(r.failure, equals(RpmFailure.featureDetectionFailed));
  });

  test('sampleFps 0 → featureDetectionFailed', () {
    final frames =
        List.generate(10, (_) => img.Image(width: 50, height: 50));
    final detections = List<BallDetection?>.filled(10, _det());
    final r = sut.estimate(
        frames: frames,
        detections: detections,
        releaseFrame: 0,
        sampleFps: 0);
    expect(r.failure, equals(RpmFailure.featureDetectionFailed));
  });
}
