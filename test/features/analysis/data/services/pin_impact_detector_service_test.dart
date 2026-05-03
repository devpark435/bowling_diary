import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _blackFrame(int w, int h) => img.Image(width: w, height: h)
  ..clear(img.ColorRgb8(0, 0, 0));

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
}
