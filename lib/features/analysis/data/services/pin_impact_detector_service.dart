import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';

class PinImpactDetectorService {
  static const _pinZoneRatio = 0.20;
  static const _changeThreshold = 0.15;
  static const _homographyZoneChangeThreshold = 0.10;
  static const double _pixelDiffThreshold = 30.0;
  // 릴리즈 직후 볼 스윙 이벤트를 오탐하지 않도록 최소 탐색 시작 프레임
  // 50 km/h 기준 18.29m 이동 = 1.3s = 39프레임 → 여유분 포함 20프레임
  static const _minTravelFrames = 20;

  /// 호모그래피로 핀 영역을 프레임 정규화좌표 존으로 투영한다.
  ///
  /// 핀덱 라인(y=18.29m)의 좌우 끝과 1.29m 앞(y=17.0m)의 좌우 끝, 총 4점을
  /// laneToFrame으로 투영해 핀덱의 화면상 위치와 그 거리에서의 원근 스케일
  /// (레인 1.29m가 화면에서 차지하는 높이 = unit)을 얻는다. 핀(높이 0.38m)은
  /// 레인 평면 위로 서 있는 수직 물체라 호모그래피로 직접 투영할 수 없으므로,
  /// 핀덱 라인에서 위로 1.5*unit(서 있는 핀 + 튀어오르는 핀 여유), 아래로
  /// 0.5*unit을 존으로 잡는다. 좌우는 4점의 nx 범위 ± 0.02.
  ///
  /// 투영 결과가 화면 밖이거나(0~1 clamp 후) 존이 퇴화하면(빈 영역) null을
  /// 반환한다 — 호출부는 null이면 legacy 존으로 폴백해야 한다.
  static Rect? computePinZone(HomographyMatrix homography) {
    final d0 = homography.laneToFrame(const LanePoint(xM: 0, yM: 18.29));
    final d1 = homography.laneToFrame(const LanePoint(xM: 1.05, yM: 18.29));
    final n0 = homography.laneToFrame(const LanePoint(xM: 0, yM: 17.0));
    final n1 = homography.laneToFrame(const LanePoint(xM: 1.05, yM: 17.0));

    for (final p in [d0, d1, n0, n1]) {
      if (!p.nx.isFinite || !p.ny.isFinite) return null;
    }

    final deckNy = (d0.ny + d1.ny) / 2;
    final nearNy = (n0.ny + n1.ny) / 2;
    final unit = (nearNy - deckNy).abs();
    if (unit <= 0 || !unit.isFinite) return null;

    final xs = [d0.nx, d1.nx, n0.nx, n1.nx];
    final left = (xs.reduce(math.min) - 0.02).clamp(0.0, 1.0);
    final right = (xs.reduce(math.max) + 0.02).clamp(0.0, 1.0);
    final top = (deckNy - unit * 1.5).clamp(0.0, 1.0);
    final bottom = (deckNy + unit * 0.5).clamp(0.0, 1.0);

    if (right - left < 0.01 || bottom - top < 0.005) return null;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// [searchStartOverride]가 주어지면(예: 공이 실제로 핀 근처(≥16m)에 도달한
  /// 분석 프레임) 그 지점부터 탐색을 시작한다 — 릴리즈 직후 볼러 팔로스루 등
  /// 핀존에 걸리는 무관한 움직임의 오탐을 원천 차단하기 위함. 다만
  /// override가 releaseFrame 이하면 물리적으로 말이 안 되므로(공이 아직
  /// 핀 근처에 갈 시간이 없었다는 뜻) 무시하고 기존 releaseFrame +
  /// minTravelFrames 규칙으로 폴백한다. override가 없으면 기존 규칙 그대로.
  int? findImpactFrame(
    List<img.Image> frames,
    int releaseFrame, {
    Rect? pinZone,
    int? searchStartOverride,
  }) {
    if (frames.length < 2) return null;
    if (releaseFrame >= frames.length) return null;

    final searchStart = (searchStartOverride != null && searchStartOverride > releaseFrame)
        ? searchStartOverride
        : releaseFrame + _minTravelFrames;
    if (searchStart >= frames.length) return null;

    final threshold = pinZone != null ? _homographyZoneChangeThreshold : _changeThreshold;

    // 검색 시작 프레임 자체를 씨드(기준)로 삼는다 — release~searchStart 구간의 자연스러운
    // 드리프트(카메라 미동/조명 변화)를 비교 대상에서 아예 제외해, 그 구간을 건너뛰고
    // 여기서부터의 "급격한" 변화만 감지한다. 과거(release=36, searchStart=56)에는 이 구간을
    // 넘어 release 프레임과 비교하다가, 첫 비교 자체가 20프레임 격차라 자연드리프트만으로도
    // 매번 임계값을 넘겨 검색 시작 지점에서 곧바로 오탐(핀 충돌 아님)이 발생했다.
    final seedFrame = frames[searchStart];
    img.Image prevZone = img.grayscale(_cropZone(seedFrame, pinZone));

    // 진단용 — 탐색 전체에서 관측된 최대 변화율과 그 프레임. 임계값을 못 넘어
    // "미감지"로 끝나는 경우, 이 값으로 "핀존 자체에 변화가 거의 없었다"(존/각도
    // 문제)와 "근접했는데 문턱을 못 넘었다"(임계값 튜닝 문제)를 구분한다.
    double maxRatio = 0;
    int maxRatioFrame = searchStart;

    for (int i = searchStart + 1; i < frames.length; i++) {
      final frame = frames[i];
      final grayZone = img.grayscale(_cropZone(frame, pinZone));

      final ratio = _changeRatio(prevZone, grayZone);
      if (ratio > maxRatio) {
        maxRatio = ratio;
        maxRatioFrame = i;
      }
      if (ratio >= threshold) {
        debugPrint('[PinImpact] 핀 충돌 프레임: $i (변화율: ${(ratio * 100).toStringAsFixed(1)}%, '
            '존: ${pinZone != null ? "호모그래피" : "legacy"})');
        return i;
      }
      prevZone = grayZone;
    }
    final zoneDesc = pinZone != null
        ? '핀존(호모그래피) LTRB(${pinZone.left.toStringAsFixed(2)},${pinZone.top.toStringAsFixed(2)},'
            '${pinZone.right.toStringAsFixed(2)},${pinZone.bottom.toStringAsFixed(2)})'
        : '핀존 비율 ${(_pinZoneRatio * 100).toStringAsFixed(0)}%';
    debugPrint('[PinImpact] 핀 충돌 미감지 (임계값 ${(threshold * 100).toStringAsFixed(0)}%, '
        '탐색구간 최대 변화율 ${(maxRatio * 100).toStringAsFixed(1)}% @ 프레임 $maxRatioFrame, '
        '$zoneDesc)');
    return null;
  }

  img.Image _cropZone(img.Image frame, Rect? pinZone) {
    if (pinZone == null) {
      final zoneH = (frame.height * _pinZoneRatio).round().clamp(1, frame.height);
      return img.copyCrop(frame, x: 0, y: 0, width: frame.width, height: zoneH);
    }

    final w = frame.width;
    final h = frame.height;
    final x = (pinZone.left * w).round().clamp(0, w - 1);
    final y = (pinZone.top * h).round().clamp(0, h - 1);
    final width = (pinZone.width * w).round().clamp(1, w - x);
    final height = (pinZone.height * h).round().clamp(1, h - y);
    return img.copyCrop(frame, x: x, y: y, width: width, height: height);
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
