import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:flutter_test/flutter_test.dart';

BallDetection _det(double cx, double cy) => BallDetection(
      cx: cx, cy: cy, bw: 0.05, bh: 0.05, confidence: 0.9);

void main() {
  late ReleaseDetectorService sut;

  setUp(() => sut = ReleaseDetectorService());

  test('볼이 정지 상태면 null 반환', () {
    final detections = List.generate(20, (_) => _det(0.5, 0.5));
    expect(sut.findReleaseFrame(detections), isNull);
  });

  test('초반 정지 후 빠른 이동 시 올바른 프레임 반환', () {
    final detections = <BallDetection?>[
      ...List.generate(5, (_) => _det(0.5, 0.5)),
      _det(0.52, 0.52), // disp ≈ 0.028 > 0.015
      _det(0.54, 0.54),
      _det(0.56, 0.56),
      _det(0.58, 0.58),
    ];
    final result = sut.findReleaseFrame(detections);
    expect(result, isNotNull);
    expect(result, lessThan(8));
    expect(result, greaterThanOrEqualTo(4));
  });

  test('감지 없는 구간 후 이동하면 null 아님', () {
    final detections = <BallDetection?>[
      ...List.generate(5, (_) => null),
      _det(0.5, 0.5),
      _det(0.52, 0.52),
      _det(0.54, 0.54),
      _det(0.56, 0.56),
    ];
    expect(sut.findReleaseFrame(detections), isNotNull);
  });

  test('연속 이동이 3프레임 미만이면 null', () {
    final detections = <BallDetection?>[
      _det(0.5, 0.5),
      _det(0.52, 0.52), // moving
      _det(0.5, 0.5),   // stopped → reset
      _det(0.5, 0.5),
    ];
    expect(sut.findReleaseFrame(detections), isNull);
  });
}
