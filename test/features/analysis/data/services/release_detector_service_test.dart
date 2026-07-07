import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:flutter_test/flutter_test.dart';

BallDetection _det(double cx, double cy) =>
    BallDetection(cx: cx, cy: cy, bw: 0.05, bh: 0.05, confidence: 0.9);

void main() {
  late ReleaseDetectorService sut;
  setUp(() => sut = ReleaseDetectorService());

  group('ReleaseDetectorService', () {
    test('볼이 계속 정지 상태면 notFound', () {
      final detections = List.generate(20, (_) => _det(0.5, 0.5));
      expect(sut.findRelease(detections).isFound, isFalse);
    });

    test('가속 구간이 있으면 release 감지', () {
      final detections = <BallDetection?>[
        for (var i = 0; i < 30; i++) _det(0.5, 0.1 + i * 0.02),
      ];
      final result = sut.findRelease(detections);
      expect(result.isFound, isTrue);
      expect(result.confidence, greaterThan(0));
    });

    test('null gap이 섞여도 감지 유지', () {
      final detections = <BallDetection?>[
        for (var i = 0; i < 30; i++) (i % 7 == 0) ? null : _det(0.5, 0.1 + i * 0.02),
      ];
      final result = sut.findRelease(detections);
      expect(result.isFound, isTrue);
    });

    test('데이터가 너무 적으면 notFound', () {
      final detections = <BallDetection?>[_det(0.5, 0.5), _det(0.5, 0.51)];
      expect(sut.findRelease(detections).isFound, isFalse);
    });

    test('동일 입력에 대해 결정적(deterministic)', () {
      final detections = <BallDetection?>[
        for (var i = 0; i < 30; i++) _det(0.5, 0.1 + i * 0.02),
      ];
      final r1 = sut.findRelease(detections);
      final r2 = sut.findRelease(detections);
      expect(r1.frame, r2.frame);
      expect(r1.confidence, r2.confidence);
    });
  });
}
