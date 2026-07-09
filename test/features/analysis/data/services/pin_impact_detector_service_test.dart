import 'dart:ui';

import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _blackFrame(int w, int h) => img.Image(width: w, height: h);

img.Image _whiteFrame(int w, int h) => img.Image(width: w, height: h)
  ..clear(img.ColorRgb8(255, 255, 255));

void main() {
  late PinImpactDetectorService sut;
  setUp(() => sut = PinImpactDetectorService());

  test('릴리즈 직후(minTravelFrames 이내) 큰 변화는 무시', () {
    final frames = <img.Image>[
      ...List.generate(10, (_) => _blackFrame(100, 100)),
      ...List.generate(10, (_) => _whiteFrame(100, 100)),
      ...List.generate(30, (_) => _blackFrame(100, 100)),
    ];
    final result = sut.findImpactFrame(frames, 0);
    expect(result, isNull);
  });

  test('minTravelFrames 이후 큰 변화는 충돌로 감지', () {
    final frames = <img.Image>[
      ...List.generate(25, (_) => _blackFrame(100, 100)),
      _whiteFrame(100, 100),
      ...List.generate(10, (_) => _blackFrame(100, 100)),
    ];
    final result = sut.findImpactFrame(frames, 0);
    expect(result, isNotNull);
    expect(result!, greaterThanOrEqualTo(20));
  });

  test('프레임 부족 시 null', () {
    final frames = List.generate(5, (_) => _blackFrame(100, 100));
    expect(sut.findImpactFrame(frames, 0), isNull);
  });

  test('releaseFrame이 후반부라 searchStart >= frames.length 이면 null', () {
    final frames = List.generate(25, (_) => _blackFrame(100, 100));
    expect(sut.findImpactFrame(frames, 20), isNull);
  });

  test('release~searchStart 구간의 점진적 드리프트는 무시하고, 그 이후 급격한 변화만 충돌로 감지 (실기기 재현)', () {
    // 프레임 0(release)은 어둡게(luminance 10), 프레임 19(=searchStart-1)까지 서서히 밝아져
    // 프레임 20(=searchStart)에서는 luminance 120 — release 프레임과 비교하면 20프레임 격차 동안
    // 누적된 큰 차이지만, 프레임간(1-프레임) 변화는 항상 완만하다. 프레임 30에서 실제 핀 충돌을
    // 흉내낸 급격한 밝기 변화(255)가 발생한다.
    final frames = <img.Image>[
      for (var i = 0; i <= 20; i++) (img.Image(width: 100, height: 100)..clear(img.ColorRgb8(10 + i * 5, 10 + i * 5, 10 + i * 5))),
      ...List.generate(9, (i) => img.Image(width: 100, height: 100)..clear(img.ColorRgb8(120, 120, 120))),
      img.Image(width: 100, height: 100)..clear(img.ColorRgb8(255, 255, 255)), // frame 30: 실제 충돌
      ...List.generate(9, (_) => img.Image(width: 100, height: 100)..clear(img.ColorRgb8(255, 255, 255))),
    ];
    final result = sut.findImpactFrame(frames, 0);
    expect(result, 30);
  });

  group('searchStartOverride', () {
    test('override가 주어지면 그 지점부터 탐색해 이전 구간의 변화는 무시한다', () {
      // 프레임 25와 45가 모두 흰색. override 없이(legacy) 탐색하면 searchStart=20이라
      // 먼저 만나는 25를 반환하지만, override=40을 주면 25는 이미 지나버린 구간이라
      // 무시하고 45를 반환한다.
      final frames = <img.Image>[
        for (var i = 0; i < 60; i++) i == 25 || i == 45 ? _whiteFrame(100, 100) : _blackFrame(100, 100),
      ];

      expect(sut.findImpactFrame(frames, 0), 25);
      expect(sut.findImpactFrame(frames, 0, searchStartOverride: 40), 45);
    });

    test('override <= releaseFrame이면 releaseFrame + minTravelFrames로 폴백한다', () {
      // releaseFrame=30, override=10(<=releaseFrame) → 폴백 searchStart=30+20=50.
      // 프레임 55만 흰색이므로 55가 반환되어야 폴백이 실제로 적용됐음을 확인할 수 있다.
      final frames = <img.Image>[
        for (var i = 0; i < 60; i++) i == 55 ? _whiteFrame(100, 100) : _blackFrame(100, 100),
      ];

      final result = sut.findImpactFrame(frames, 30, searchStartOverride: 10);

      expect(result, 55);
    });
  });

  group('computePinZone', () {
    test('레인 평면 정사영 호모그래피에서 핀덱 상단부 존을 계산', () {
      final homography = HomographyMatrix.fromRowMajor(
        [1.05, 0, 0, 0, -18.29, 18.29, 0, 0, 1],
      );
      final zone = PinImpactDetectorService.computePinZone(homography);
      expect(zone, isNotNull);
      expect(zone!.left, closeTo(0.0, 1e-3));
      expect(zone.top, closeTo(0.0, 1e-3));
      expect(zone.right, closeTo(1.0, 1e-3));
      expect(zone.bottom, closeTo(0.0353, 1e-3));
    });

    test('퇴화 존(identity 호모그래피)은 null', () {
      final homography = HomographyMatrix.identity();
      final zone = PinImpactDetectorService.computePinZone(homography);
      expect(zone, isNull);
    });
  });

  group('findImpactFrame with pinZone', () {
    test('존 내부 변화는 충돌로 감지', () {
      const zone = Rect.fromLTRB(0.4, 0.0, 0.6, 0.2);
      final frames = List.generate(30, (i) {
        final frame = img.Image(width: 100, height: 100);
        if (i == 25) {
          img.fillRect(frame, x1: 40, y1: 0, x2: 59, y2: 19, color: img.ColorRgb8(255, 255, 255));
        }
        return frame;
      });
      final result = sut.findImpactFrame(frames, 0, pinZone: zone);
      expect(result, 25);
    });

    test('존 외부 변화는 무시', () {
      const zone = Rect.fromLTRB(0.4, 0.0, 0.6, 0.2);
      final frames = List.generate(30, (i) {
        final frame = img.Image(width: 100, height: 100);
        if (i == 25) {
          img.fillRect(frame, x1: 0, y1: 50, x2: 99, y2: 99, color: img.ColorRgb8(255, 255, 255));
        }
        return frame;
      });
      final result = sut.findImpactFrame(frames, 0, pinZone: zone);
      expect(result, isNull);
    });
  });
}
