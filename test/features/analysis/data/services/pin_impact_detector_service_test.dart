import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
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
}
