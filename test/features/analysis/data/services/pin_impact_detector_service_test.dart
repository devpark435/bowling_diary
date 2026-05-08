import 'dart:ui';

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _blackFrame(int w, int h) => img.Image(width: w, height: h);

img.Image _whiteFrame(int w, int h) => img.Image(width: w, height: h)
  ..clear(img.ColorRgb8(255, 255, 255));

BallDetection? _det(double cx, double cy) => BallDetection(
      cx: cx, cy: cy, bw: 0.05, bh: 0.05, confidence: 0.9);

void main() {
  late PinImpactDetectorService sut;
  setUp(() => sut = PinImpactDetectorService());

  test('릴리즈 직후 변화는 무시 (minTravel)', () {
    final frames = <img.Image>[
      ...List.generate(10, (_) => _blackFrame(100, 100)),
      ...List.generate(10, (_) => _whiteFrame(100, 100)),
      ...List.generate(30, (_) => _blackFrame(100, 100)),
    ];
    final detections = List<BallDetection?>.generate(50, (_) => _det(0.3, 0.3));
    final result = sut.findImpact(frames, detections, 0);
    expect(result.isFound, isFalse);
  });

  test('minTravel 이후 변화는 impact 반환', () {
    final frames = <img.Image>[
      ...List.generate(25, (_) => _blackFrame(100, 100)),
      _whiteFrame(100, 100),
      ...List.generate(10, (_) => _blackFrame(100, 100)),
    ];
    final detections =
        List<BallDetection?>.generate(36, (_) => _det(0.5, 0.3));
    final result = sut.findImpact(frames, detections, 0);
    expect(result.isFound, isTrue);
    expect(result.frame, greaterThanOrEqualTo(20));
  });

  test('YOLO 종점 위치 기반 ROI 산출 (정상 케이스)', () {
    final frames = List.generate(40, (_) => _blackFrame(100, 100));
    // 마지막 5프레임 동안 변화 발생 (오른쪽 영역)
    for (int i = 30; i < 40; i++) {
      frames[i] = _blackFrame(100, 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 70; x < 100; x++) {
          frames[i].setPixelRgb(x, y, 255, 255, 255);
        }
      }
    }
    final detections = <BallDetection?>[
      for (int i = 0; i < 25; i++) _det(0.2 + i * 0.02, 0.5),
      ...List.generate(15, (_) => null),
    ];
    final result = sut.findImpact(frames, detections, 0);
    expect(result.isFound, isTrue);
    expect(result.roi, isNot(equals(const Rect.fromLTWH(0, 0, 0, 0))));
  });

  test('프레임 부족 시 notFound', () {
    final frames = List.generate(5, (_) => _blackFrame(100, 100));
    final detections = List<BallDetection?>.generate(5, (_) => _det(0.5, 0.5));
    expect(sut.findImpact(frames, detections, 0).isFound, isFalse);
  });

  test('release 이후 탐색 가능 영역 부족 시 notFound', () {
    final frames = List.generate(25, (_) => _blackFrame(100, 100));
    final detections =
        List<BallDetection?>.generate(25, (_) => _det(0.5, 0.5));
    expect(sut.findImpact(frames, detections, 20).isFound, isFalse);
  });

  test('완전 정적 프레임 시퀀스에서는 noise floor가 false positive 방지', () {
    final frames = List.generate(50, (_) => _blackFrame(100, 100));
    final detections =
        List<BallDetection?>.generate(50, (_) => _det(0.5, 0.3));
    final result = sut.findImpact(frames, detections, 0);
    expect(result.isFound, isFalse);
  });

  test('동일 입력 5회 실행 시 동일 결과 (결정성)', () {
    final frames = <img.Image>[
      ...List.generate(25, (_) => _blackFrame(100, 100)),
      _whiteFrame(100, 100),
      ...List.generate(10, (_) => _blackFrame(100, 100)),
    ];
    final detections =
        List<BallDetection?>.generate(36, (_) => _det(0.5, 0.3));
    final results = List.generate(5, (_) => sut.findImpact(frames, detections, 0));
    expect(results.every((r) => r.frame == results.first.frame), isTrue);
  });
}
