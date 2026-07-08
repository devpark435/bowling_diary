import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:flutter_test/flutter_test.dart';

BallDetection _det(double cx, double cy) =>
    BallDetection(cx: cx, cy: cy, bw: 0.05, bh: 0.05, confidence: 0.9);

BallDetection _detSized(double cx, double cy, double bw) =>
    BallDetection(cx: cx, cy: cy, bw: bw, bh: 0.05, confidence: 0.9);

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

    test('충돌 후 파편으로 인한 후반부 스퓨리어스 bbox 스파이크가 있어도 초반 release를 정확히 찾음', () {
      // 실기기 재현 시나리오: 진짜 백스윙 피크는 초반(index 5)에 있고,
      // 임팩트 이후 파편/블러로 인한 더 큰 bbox가 후반부(index 95)에 스퓨리어스하게 발생.
      // 수정 전에는 전체 스캔이라 후반 스파이크가 backswing peak로 오검출되어
      // searchStart가 뒤로 밀리고(95) 초반 release 구간(index 33 부근)을 통째로 건너뛴다.
      // 포물선 형태 속도 프로파일(가속 후 감속)로 30~50 구간에 진짜 release,
      // 90~97 구간에 미약한 후반 흔들림을 심어 두 구간 모두 후보로 만든다.
      const n = 100;
      double cyOf(int i) {
        double sum = 0.1;
        for (var j = 30; j <= i && j <= 50; j++) {
          sum += 0.001 * (j - 30) * (50 - j);
        }
        for (var j = 90; j <= i && j <= 97; j++) {
          sum += 0.01 * (j - 90) * (97 - j);
        }
        return sum;
      }

      final detections = <BallDetection?>[
        for (var i = 0; i < n; i++)
          _detSized(
            0.5,
            cyOf(i),
            i == 5
                ? 0.20 // 초반 진짜 백스윙 피크 (area 0.01)
                : i == 95
                    ? 0.40 // 후반 스퓨리어스 스파이크 (area 0.02, 진짜 피크보다 큼)
                    : 0.05, // 기본 area 0.0025
          ),
      ];

      final result = sut.findRelease(detections);

      expect(result.isFound, isTrue);
      // 후반 스파이크(index 95) 근처가 아니라 초반 가속 구간(index 33 부근)에서 검출돼야 함.
      expect(result.frame, lessThan(60));
    });

    test('유일하게 찾은 구간이 시퀀스 후반 25% 안에 있으면 notFound (안전장치)', () {
      // release는 구조상 flight/impact/settle보다 앞에 와야 하므로,
      // 제대로 트리밍된 클립 후반 25%에서 검출된 release는 신뢰할 수 없다고 보고
      // notFound로 실패를 명시한다 (조용히 틀린 프레임을 내보내지 않음).
      const n = 100;
      double cyOf(int i) {
        double sum = 0.1;
        for (var j = 80; j <= i && j <= 99; j++) {
          sum += 0.002 * (j - 80) * (99 - j);
        }
        return sum;
      }

      final detections = <BallDetection?>[
        for (var i = 0; i < n; i++) _det(0.5, cyOf(i)),
      ];

      final result = sut.findRelease(detections);

      expect(result.isFound, isFalse);
    });
  });
}
