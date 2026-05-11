import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
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

  // ── lane forward score 통합 테스트 (findRelease 경유) ──────────────────

  test('valid detection 2개 이하면 lane forward score 무효 — homography 유무 결과 동일', () {
    // valid detection이 2개(≤ 2)인 경우 _laneForwardScore는 0.0을 반환하므로
    // homography 유무가 결과에 영향을 주지 않는다.
    // 충분한 velocity 시퀀스를 만들되, release 후보 구간에서 valid detection이 2개뿐.
    final h = HomographyMatrix.identity();

    // 0~9: 정지 (null), 10~19: null, 20: valid, 21~22: null, 23: valid, 24~25: 가속 유효
    // 실제로는 velocity 계산을 위해 cx 변화가 있어야 함.
    // 간단한 구성: 정지 후 가속하되, 가속 구간(startFrame~startFrame+10)에 valid detection 2개만.
    final detections = <BallDetection?>[
      // 0~14: 정지
      ...List.generate(15, (_) => _det(0.5, 0.5)),
      // 15~19: 가속 (velocity 충분)
      _det(0.530, 0.5),
      _det(0.565, 0.5),
      _det(0.605, 0.5),
      _det(0.650, 0.5),
      _det(0.700, 0.5),
      // 20~28: null (valid detection 0개 → release 구간 합산 ≤ 2)
      null, null, null, null, null, null, null, null, null,
    ];

    final withoutH = sut.findRelease(detections);
    final withH = sut.findRelease(detections, homography: h);

    // valid detection 부족으로 lane score가 0이므로 두 결과의 frame이 일치해야 함.
    expect(withH.isFound, equals(withoutH.isFound));
    if (withoutH.isFound) {
      expect(withH.frame, equals(withoutH.frame));
    }
  });

  test('homography 있으면 lane forward score로 후보 우선순위', () {
    // 두 후보 segment:
    //   후보 A (앞쪽 프레임): 동일한 velocity 크기지만 lane y 감소 (역방향)
    //   후보 B (뒤쪽 프레임): 동일한 velocity 크기지만 lane y 증가 (정방향)
    // identity homography → lane y == frame ny
    //
    // 빌드 전략: 정지(ny=0.5) → 역방향 가속(ny 감소) → 정지 → 정방향 가속(ny 증가)
    // 역방향 가속 = 우선 충분히 긴 초반 정지 구간 필요 (searchStart = 25% 이후).
    // 간단하게: 영상 전반부 정지, 중반부 역방향 segment, 후반부 정방향 segment.

    final h = HomographyMatrix.identity();

    // 0~14: 정지 (velocity ≈ 0, no segment)
    // 15~19: ny 감소 (후보 A — 역방향, shrink 중립)
    // 20~24: 정지
    // 25~29: ny 증가 (후보 B — 정방향, shrink 중립)
    final detections = <BallDetection?>[
      // 0~14 정지
      ...List.generate(15, (_) => BallDetection(cx: 0.5, cy: 0.5, bw: 0.05, bh: 0.05, confidence: 0.9)),
      // 15~19 역방향 가속 (ny 감소: 0.48, 0.44, 0.38, 0.30, 0.20)
      BallDetection(cx: 0.5, cy: 0.48, bw: 0.05, bh: 0.05, confidence: 0.9),
      BallDetection(cx: 0.5, cy: 0.44, bw: 0.05, bh: 0.05, confidence: 0.9),
      BallDetection(cx: 0.5, cy: 0.38, bw: 0.05, bh: 0.05, confidence: 0.9),
      BallDetection(cx: 0.5, cy: 0.30, bw: 0.05, bh: 0.05, confidence: 0.9),
      BallDetection(cx: 0.5, cy: 0.20, bw: 0.05, bh: 0.05, confidence: 0.9),
      // 20~24 정지
      ...List.generate(5, (_) => BallDetection(cx: 0.5, cy: 0.5, bw: 0.05, bh: 0.05, confidence: 0.9)),
      // 25~29 정방향 가속 (ny 증가: 0.52, 0.56, 0.62, 0.70, 0.80)
      BallDetection(cx: 0.5, cy: 0.52, bw: 0.05, bh: 0.05, confidence: 0.9),
      BallDetection(cx: 0.5, cy: 0.56, bw: 0.05, bh: 0.05, confidence: 0.9),
      BallDetection(cx: 0.5, cy: 0.62, bw: 0.05, bh: 0.05, confidence: 0.9),
      BallDetection(cx: 0.5, cy: 0.70, bw: 0.05, bh: 0.05, confidence: 0.9),
      BallDetection(cx: 0.5, cy: 0.80, bw: 0.05, bh: 0.05, confidence: 0.9),
    ];

    // homography 없을 때와 있을 때의 결과가 다를 수 있음을 검증.
    // 단, 핵심은 homography 있을 때 정방향 segment(후반부)가 선택되어야 함.
    // 역방향 segment lane forward score ≈ -1, 정방향 ≈ +1 → +10점 차이.
    final withH = sut.findRelease(detections, homography: h);
    expect(withH.isFound, isTrue);
    // 정방향 가속 시작은 frame 25~29 범위
    expect(withH.frame, greaterThanOrEqualTo(25));
  });
}
