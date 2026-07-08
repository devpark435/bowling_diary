import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

List<img.Image> _framesWithFlashAt(int flashFrame, {int total = 40}) {
  return List.generate(total, (i) {
    final image = img.Image(width: 20, height: 20);
    final brightness = i == flashFrame ? 255 : 10;
    img.fill(image, color: img.ColorRgb8(brightness, brightness, brightness));
    return image;
  });
}

void main() {
  group('ImpactDetectorService', () {
    test('두 신호가 0~2프레임 이내로 일치하면 high', () {
      final frames = _framesWithFlashAt(30);
      final sut = ImpactDetectorService(pinImpactDetector: PinImpactDetectorService());
      final result = sut.detect(frames: frames, releaseFrame: 5, homographyImpactFrame: 31);
      expect(result.confidence, ImpactConfidence.high);
    });

    test('두 신호가 3~5프레임 차이나면 medium', () {
      final frames = _framesWithFlashAt(30);
      final sut = ImpactDetectorService(pinImpactDetector: PinImpactDetectorService());
      final result = sut.detect(frames: frames, releaseFrame: 5, homographyImpactFrame: 34);
      expect(result.confidence, ImpactConfidence.medium);
    });

    test('두 신호가 6프레임 이상 차이나면 low, 호모그래피 값을 최종 채택', () {
      final frames = _framesWithFlashAt(30);
      final sut = ImpactDetectorService(pinImpactDetector: PinImpactDetectorService());
      final result = sut.detect(frames: frames, releaseFrame: 5, homographyImpactFrame: 39);
      expect(result.confidence, ImpactConfidence.low);
      expect(result.frame, 39);
    });

    test('핀존 휘도 신호가 아예 없으면(플래시 없음) low, 호모그래피 값만 채택', () {
      final frames = List.generate(40, (i) {
        final image = img.Image(width: 20, height: 20);
        img.fill(image, color: img.ColorRgb8(10, 10, 10));
        return image;
      });
      final sut = ImpactDetectorService(pinImpactDetector: PinImpactDetectorService());
      final result = sut.detect(frames: frames, releaseFrame: 5, homographyImpactFrame: 32);
      expect(result.confidence, ImpactConfidence.low);
      expect(result.frame, 32);
    });
  });
}
