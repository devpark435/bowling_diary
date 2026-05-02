import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class PinImpactDetectorService {
  static const _pinZoneRatio = 0.20;
  static const _changeThreshold = 0.15;
  static const double _pixelDiffThreshold = 30.0;

  int? findImpactFrame(List<img.Image> frames, int releaseFrame) {
    if (frames.length < 2) return null;

    // releaseFrame이 기준 프레임 — 다음 프레임부터 비교 시작
    img.Image? prevZone;

    for (int i = releaseFrame; i < frames.length; i++) {
      final frame = frames[i];
      final zoneH = (frame.height * _pinZoneRatio).round().clamp(1, frame.height);
      final zone = img.copyCrop(frame, x: 0, y: 0, width: frame.width, height: zoneH);
      final grayZone = img.grayscale(zone);

      if (prevZone != null) {
        final ratio = _changeRatio(prevZone, grayZone);
        if (ratio >= _changeThreshold) {
          debugPrint('[PinImpact] 핀 충돌 프레임: $i (변화율: ${(ratio * 100).toStringAsFixed(1)}%)');
          return i;
        }
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
