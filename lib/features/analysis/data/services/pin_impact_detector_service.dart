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
    if (releaseFrame >= frames.length) return null;

    final searchStart = releaseFrame + _minTravelFrames;
    if (searchStart >= frames.length) return null;

    // 검색 시작 프레임 자체를 씨드(기준)로 삼는다 — release~searchStart 구간의 자연스러운
    // 드리프트(카메라 미동/조명 변화)를 비교 대상에서 아예 제외해, 그 구간을 건너뛰고
    // 여기서부터의 "급격한" 변화만 감지한다. 과거(release=36, searchStart=56)에는 이 구간을
    // 넘어 release 프레임과 비교하다가, 첫 비교 자체가 20프레임 격차라 자연드리프트만으로도
    // 매번 임계값을 넘겨 검색 시작 지점에서 곧바로 오탐(핀 충돌 아님)이 발생했다.
    final seedFrame = frames[searchStart];
    final seedH = (seedFrame.height * _pinZoneRatio).round().clamp(1, seedFrame.height);
    img.Image prevZone = img.grayscale(
      img.copyCrop(seedFrame, x: 0, y: 0, width: seedFrame.width, height: seedH),
    );

    for (int i = searchStart + 1; i < frames.length; i++) {
      final frame = frames[i];
      final zoneH = (frame.height * _pinZoneRatio).round().clamp(1, frame.height);
      final zone = img.copyCrop(frame, x: 0, y: 0, width: frame.width, height: zoneH);
      final grayZone = img.grayscale(zone);

      final ratio = _changeRatio(prevZone, grayZone);
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
