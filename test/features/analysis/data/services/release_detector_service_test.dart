import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:flutter_test/flutter_test.dart';

BallDetection _det(double cx, double cy) => BallDetection(
      cx: cx, cy: cy, bw: 0.05, bh: 0.05, confidence: 0.9);

void main() {
  late ReleaseDetectorService sut;

  setUp(() => sut = ReleaseDetectorService());

  test('볼이 정지 상태면 notFound', () {
    final detections = List.generate(20, (_) => _det(0.5, 0.5));
    expect(sut.findRelease(detections).isFound, isFalse);
  });

  test('정지 후 가속 시 가속 시작 프레임 반환', () {
    final detections = <BallDetection?>[
      ...List.generate(5, (_) => _det(0.5, 0.5)),
      _det(0.505, 0.5),
      _det(0.520, 0.5),
      _det(0.545, 0.5),
      _det(0.580, 0.5),
      _det(0.625, 0.5),
      _det(0.680, 0.5),
    ];
    final result = sut.findRelease(detections);
    expect(result.isFound, isTrue);
    // 파라미터(threshold, minConsecutive) 완화로 더 일찍 감지 가능. 정지구간 이후면 충분.
    expect(result.frame, greaterThanOrEqualTo(5));
    expect(result.frame, lessThanOrEqualTo(10));
  });

  test('null 끼인 시퀀스에서 null 이후 가속 감지', () {
    final detections = <BallDetection?>[
      ...List.generate(5, (_) => null),
      _det(0.500, 0.5),
      _det(0.530, 0.5),
      _det(0.565, 0.5),
      _det(0.605, 0.5),
      _det(0.650, 0.5),
    ];
    expect(sut.findRelease(detections).isFound, isTrue);
  });

  test('팔스윙 후 정지 시 release 아님 (절대 속도 미만)', () {
    // absSpeedFloor=0.015 기준으로 dx=0.01/frame은 속도 미만 → notFound
    final detections = <BallDetection?>[
      _det(0.50, 0.5),
      _det(0.51, 0.5),
      _det(0.52, 0.5),
      _det(0.53, 0.5),
      _det(0.54, 0.5),
      _det(0.54, 0.5),
      _det(0.54, 0.5),
    ];
    expect(sut.findRelease(detections).isFound, isFalse);
  });

  test('confidence는 0.6 이상', () {
    final detections = <BallDetection?>[
      ...List.generate(5, (_) => _det(0.5, 0.5)),
      _det(0.530, 0.5),
      _det(0.565, 0.5),
      _det(0.605, 0.5),
      _det(0.650, 0.5),
      _det(0.700, 0.5),
    ];
    final result = sut.findRelease(detections);
    expect(result.isFound, isTrue);
    expect(result.confidence, greaterThanOrEqualTo(0.6));
  });

  test('동일 입력 5회 실행 시 동일 결과 (결정성)', () {
    final detections = <BallDetection?>[
      ...List.generate(5, (_) => _det(0.5, 0.5)),
      _det(0.530, 0.5),
      _det(0.565, 0.5),
      _det(0.605, 0.5),
      _det(0.650, 0.5),
    ];
    final results = List.generate(5, (_) => sut.findRelease(detections));
    expect(results.every((r) =>
        r.frame == results.first.frame && r.confidence == results.first.confidence),
        isTrue);
  });
}
