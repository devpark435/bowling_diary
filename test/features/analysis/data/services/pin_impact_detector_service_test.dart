import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _grayFrame(int w, int h, int lum) {
  final frame = img.Image(width: w, height: h);
  img.fill(frame, color: img.ColorRgb8(lum, lum, lum));
  return frame;
}

img.Image _frameWithPinExplosion(int w, int h) {
  // 상단 20%를 흰색(255)으로 → 직전 프레임 대비 급격한 변화
  final frame = img.Image(width: w, height: h);
  img.fill(frame, color: img.ColorRgb8(128, 128, 128));
  final pinZoneH = (h * 0.20).round();
  for (int y = 0; y < pinZoneH; y++) {
    for (int x = 0; x < w; x++) {
      frame.setPixelRgb(x, y, 255, 255, 255);
    }
  }
  return frame;
}

void main() {
  late PinImpactDetectorService sut;

  setUp(() => sut = PinImpactDetectorService());

  test('프레임 없으면 null', () {
    expect(sut.findImpactFrame([], 0), isNull);
  });

  test('릴리즈 프레임 이후 변화 없으면 null', () {
    final frames = List.generate(10, (_) => _grayFrame(120, 100, 128));
    expect(sut.findImpactFrame(frames, 2), isNull);
  });

  test('핀 충돌 프레임 감지', () {
    final frames = [
      _grayFrame(120, 100, 128), // 0 릴리즈 전
      _grayFrame(120, 100, 128), // 1 릴리즈
      _grayFrame(120, 100, 128), // 2 이동 중
      _grayFrame(120, 100, 128), // 3 이동 중
      _frameWithPinExplosion(120, 100), // 4 충돌!
    ];
    expect(sut.findImpactFrame(frames, 1), equals(4));
  });

  test('릴리즈 이전 충돌은 무시', () {
    final frames = [
      _frameWithPinExplosion(120, 100), // 0 (릴리즈 전)
      _grayFrame(120, 100, 128),         // 1 릴리즈
      _grayFrame(120, 100, 128),         // 2
    ];
    // releaseFrame=1 이후엔 변화 없음 → null
    expect(sut.findImpactFrame(frames, 1), isNull);
  });
}
