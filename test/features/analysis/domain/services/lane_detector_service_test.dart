import 'dart:math' as math;

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/lane_detection_result.dart';
import 'package:bowling_diary/features/analysis/domain/services/lane_detector_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// 합성 프레임의 정답 4코너(foul-left, foul-right, pin-right, pin-left).
// 프레임 폭의 80%(하단)→20%(상단)로 좁아지는 사다리꼴 — 원근 조건을 만족.
const _groundTruthCorners = [
  FramePoint(nx: 0.10, ny: 0.88), // foul-left
  FramePoint(nx: 0.90, ny: 0.88), // foul-right
  FramePoint(nx: 0.60, ny: 0.20), // pin-right
  FramePoint(nx: 0.40, ny: 0.20), // pin-left
];

const _tinyLaneCorners = [
  FramePoint(nx: 0.45, ny: 0.88), // foul-left
  FramePoint(nx: 0.55, ny: 0.88), // foul-right
  FramePoint(nx: 0.52, ny: 0.20), // pin-right
  FramePoint(nx: 0.48, ny: 0.20), // pin-left
];

List<double> _px(FramePoint p, int width, int height) {
  return [p.nx * width, p.ny * height];
}

/// 어두운 배경 위에 밝은 사다리꼴 레인을 그린 합성 프레임.
/// [withFoulStripe]가 true면 레인 하단(파울라인 근처)에 어두운 가로 줄무늬를 추가한다.
img.Image _laneFrame({
  required int width,
  required int height,
  required List<FramePoint> corners,
  bool withFoulStripe = false,
  int backgroundLum = 40,
  int laneLum = 200,
  int stripeLum = 90,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(backgroundLum, backgroundLum, backgroundLum));

  final fl = _px(corners[0], width, height);
  final fr = _px(corners[1], width, height);
  final pr = _px(corners[2], width, height);
  final pl = _px(corners[3], width, height);

  final yTop = pl[1];
  final yBottom = fl[1];

  void fillRow(int y, int stripeLumValue) {
    if (y < 0 || y >= height) return;
    final t = ((y - yTop) / (yBottom - yTop)).clamp(0.0, 1.0);
    final xL = pl[0] + t * (fl[0] - pl[0]);
    final xR = pr[0] + t * (fr[0] - pr[0]);
    for (var x = xL.round(); x <= xR.round(); x++) {
      if (x >= 0 && x < width) {
        image.setPixelRgb(x, y, stripeLumValue, stripeLumValue, stripeLumValue);
      }
    }
  }

  for (var y = yTop.round(); y <= yBottom.round(); y++) {
    fillRow(y, laneLum);
  }

  if (withFoulStripe) {
    // 파울라인 근처(레인 영역 하단 8% 지점)에 4px 두께의 어두운 줄무늬.
    final stripeCenter = (yBottom - 0.08 * (yBottom - yTop)).round();
    for (var dy = -1; dy <= 2; dy++) {
      fillRow(stripeCenter + dy, stripeLum);
    }
  }

  return image;
}

img.Image _noiseFrame(int width, int height, {int seed = 42}) {
  final random = math.Random(seed);
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = random.nextInt(256);
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

void main() {
  group('LaneDetectorService', () {
    test('파울라인 줄무늬가 있는 깨끗한 합성 레인 -> good, 각 코너가 정답의 0.06 이내', () {
      final frame = _laneFrame(
        width: 320,
        height: 568,
        corners: _groundTruthCorners,
        withFoulStripe: true,
      );
      final sut = LaneDetectorService();

      final result = sut.detect(frame);

      expect(result.quality, LaneDetectionQuality.good);
      expect(result.corners.length, 4);
      for (var i = 0; i < 4; i++) {
        final expected = _groundTruthCorners[i];
        final actual = result.corners[i];
        expect(
          (actual.nx - expected.nx).abs(),
          lessThan(0.06),
          reason: 'corner $i nx: expected ${expected.nx}, actual ${actual.nx}',
        );
        expect(
          (actual.ny - expected.ny).abs(),
          lessThan(0.06),
          reason: 'corner $i ny: expected ${expected.ny}, actual ${actual.ny}',
        );
      }
    });

    test('파울라인 줄무늬 없는 레인 -> rough(최하단 레코드로 대체), 코너는 0.10 이내', () {
      final frame = _laneFrame(
        width: 320,
        height: 568,
        corners: _groundTruthCorners,
        withFoulStripe: false,
      );
      final sut = LaneDetectorService();

      final result = sut.detect(frame);

      expect(result.quality, LaneDetectionQuality.rough);
      for (var i = 0; i < 4; i++) {
        final expected = _groundTruthCorners[i];
        final actual = result.corners[i];
        expect((actual.nx - expected.nx).abs(), lessThan(0.10));
        expect((actual.ny - expected.ny).abs(), lessThan(0.10));
      }
    });

    test('균일 노이즈 프레임(구조 없음) -> notFound, 기본 사다리꼴 반환', () {
      final frame = _noiseFrame(320, 568);
      final sut = LaneDetectorService();

      final result = sut.detect(frame);

      expect(result.quality, LaneDetectionQuality.notFound);
      expect(result.corners, [
        const FramePoint(nx: 0.15, ny: 0.85),
        const FramePoint(nx: 0.85, ny: 0.85),
        const FramePoint(nx: 0.62, ny: 0.25),
        const FramePoint(nx: 0.38, ny: 0.25),
      ]);
    });

    test('레인 폭이 프레임의 20% 미만 -> notFound', () {
      final frame = _laneFrame(
        width: 320,
        height: 568,
        corners: _tinyLaneCorners,
        withFoulStripe: true,
      );
      final sut = LaneDetectorService();

      final result = sut.detect(frame);

      expect(result.quality, LaneDetectionQuality.notFound);
    });

    test('결정론적: 동일 프레임 두 번 검출 시 동일 결과', () {
      final frame = _laneFrame(
        width: 320,
        height: 568,
        corners: _groundTruthCorners,
        withFoulStripe: true,
      );
      final sut = LaneDetectorService();

      final first = sut.detect(frame);
      final second = sut.detect(frame);

      expect(first.quality, second.quality);
      expect(first.corners, second.corners);
    });
  });
}
