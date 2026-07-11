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
      expect(result!.confidence, ImpactConfidence.high);
    });

    test('두 신호가 4~12프레임 차이나면 medium (경계값)', () {
      final frames = _framesWithFlashAt(30);
      final sut = ImpactDetectorService(pinImpactDetector: PinImpactDetectorService());
      final result = sut.detect(frames: frames, releaseFrame: 5, homographyImpactFrame: 42);
      expect(result!.confidence, ImpactConfidence.medium);
    });

    test('두 신호가 13프레임 이상 차이나면 low, 호모그래피 값을 최종 채택', () {
      final frames = _framesWithFlashAt(30);
      final sut = ImpactDetectorService(pinImpactDetector: PinImpactDetectorService());
      final result = sut.detect(frames: frames, releaseFrame: 5, homographyImpactFrame: 43);
      expect(result!.confidence, ImpactConfidence.low);
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
      expect(result!.confidence, ImpactConfidence.low);
      expect(result.frame, 32);
    });

    // 캘리브레이션 스케일 오류로 FSM이 절대 y 게이트를 못 넘겨 침묵해도
    // (homographyImpactFrame == null) 핀 폭발이 픽셀 증거로 감지됐다면
    // 독립 신호 단독으로 채택한다 — 다만 교차검증이 없으므로 medium.
    test('핀 폭발은 감지됐지만 FSM 임팩트가 null이면 medium, 핀 프레임을 채택', () {
      final frames = _framesWithFlashAt(30);
      final sut = ImpactDetectorService(pinImpactDetector: PinImpactDetectorService());
      final result = sut.detect(frames: frames, releaseFrame: 5, homographyImpactFrame: null);
      expect(result, isNotNull);
      expect(result!.confidence, ImpactConfidence.medium);
      expect(result.frame, 30);
    });

    // 핀 폭발도 못 잡고 FSM도 침묵하면 임팩트 시간축을 세울 근거가 전혀
    // 없다 — 정직한 실패로 null을 반환해야 한다(과거처럼 존재하지 않는
    // homographyImpactFrame을 임의 채택하면 안 됨).
    test('핀 폭발 미감지 + FSM 임팩트도 null이면 null 반환', () {
      final frames = List.generate(40, (i) {
        final image = img.Image(width: 20, height: 20);
        img.fill(image, color: img.ColorRgb8(10, 10, 10));
        return image;
      });
      final sut = ImpactDetectorService(pinImpactDetector: PinImpactDetectorService());
      final result = sut.detect(frames: frames, releaseFrame: 5, homographyImpactFrame: null);
      expect(result, isNull);
    });
  });
}
