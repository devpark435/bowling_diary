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
    // 허용 창(diff<=3 high / <=12 medium)은 pinImpactDetector가 이제 "진짜
    // 핀 폭발"을 잡도록 재설계돼 호모그래피 왜곡 영향을 받는 FSM 신호와
    // 다소 벌어질 수 있다는 전제로 완화됐다(실측: FSM 118 vs 실제 폭발
    // ~127-129, 왜곡 때문에 FSM이 이르게 잡힘). pinZone을 지정하지 않으므로
    // 아래 테스트들은 pinImpactDetector의 legacy(존 미지정) 경로를 탄다 —
    // 이 경로는 Task 1에서 수정하지 않았으므로 단일 프레임 플래시로도 여전히
    // 첫 돌파 즉시 감지된다.
    test('두 신호가 3프레임 이내로 일치하면 high (경계값)', () {
      final frames = _framesWithFlashAt(30);
      final sut = ImpactDetectorService(pinImpactDetector: PinImpactDetectorService());
      final result = sut.detect(frames: frames, releaseFrame: 5, homographyImpactFrame: 33);
      expect(result.confidence, ImpactConfidence.high);
    });

    test('두 신호가 4~12프레임 차이나면 medium (경계값)', () {
      final frames = _framesWithFlashAt(30);
      final sut = ImpactDetectorService(pinImpactDetector: PinImpactDetectorService());
      final result = sut.detect(frames: frames, releaseFrame: 5, homographyImpactFrame: 42);
      expect(result.confidence, ImpactConfidence.medium);
    });

    test('두 신호가 13프레임 이상 차이나면 low, 호모그래피 값을 최종 채택', () {
      final frames = _framesWithFlashAt(30);
      final sut = ImpactDetectorService(pinImpactDetector: PinImpactDetectorService());
      final result = sut.detect(frames: frames, releaseFrame: 5, homographyImpactFrame: 43);
      expect(result.confidence, ImpactConfidence.low);
      expect(result.frame, 43);
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
