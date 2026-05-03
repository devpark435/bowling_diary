import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class PinImpactDetectorService {
  static const _pinZoneRatio = 0.20;
  static const _changeThreshold = 0.15;
  static const double _pixelDiffThreshold = 30.0;
  // 릴리즈 직후 볼 스윙 이벤트를 오탐하지 않도록 최소 탐색 시작 프레임
  // 50 km/h 기준 18.29m 이동 = 1.3s = 39프레임 → 여유분 포함 20프레임
  static const _minTravelFrames = 20;

  int? findImpactFrame(List<img.Image> frames, int releaseFrame) {
    if (frames.length < 2) return null;

    final searchStart = releaseFrame + _minTravelFrames;
    if (searchStart >= frames.length) return null;

    // 릴리즈 프레임을 기준으로 prevZone 초기화 (릴리즈 이후 변화를 무시하기 위해)
    final seedFrame = frames[releaseFrame];
    final seedH = (seedFrame.height * _pinZoneRatio).round().clamp(1, seedFrame.height);
    img.Image? prevZone = img.grayscale(
      img.copyCrop(seedFrame, x: 0, y: 0, width: seedFrame.width, height: seedH),
    );

    for (int i = searchStart; i < frames.length; i++) {
      final frame = frames[i];
      final zoneH = (frame.height * _pinZoneRatio).round().clamp(1, frame.height);
      final zone = img.copyCrop(frame, x: 0, y: 0, width: frame.width, height: zoneH);
      final grayZone = img.grayscale(zone);

      final ratio = _changeRatio(prevZone!, grayZone);
      if (ratio >= _changeThreshold) {
        debugPrint('[PinImpact] 핀 충돌 프레임: $i (변화율: ${(ratio * 100).toStringAsFixed(1)}%)');
        return i;
      }
      prevZone = grayZone;
    }
    debugPrint('[PinImpact] 핀 충돌 미감지');
    return null;
  }

  double _changeRatio(img.Image prev, img.Image curr) {
    final total = curr.width * curr.height;
    if (total == 0) return 0;
    int changed = 0;

    for (int y = 0; y < curr.height; y++) {
      for (int x = 0; x < curr.width; x++) {
        final diff = (img.getLuminance(curr.getPixel(x, y)) -
                img.getLuminance(prev.getPixel(x, y)))
            .abs();
        if (diff > _pixelDiffThreshold) changed++;
      }
    }
    return changed / total;
  }
}
