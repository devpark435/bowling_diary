import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';

class PinImpactDetectorService {
  static const _pinZoneRatio = 0.20;
  static const _changeThreshold = 0.15;
  // 호모그래피 존 경로는 첫-돌파 고정 임계값이 아니라 탐색창 내 최대 변화율
  // (argmax)을 채택하므로, 이 값은 "이 정도는 넘어야 노이즈가 아니라 실제
  // 충돌 신호로 본다"는 최소 바닥(floor)이다. 실기기 3연속 런에서 argmax
  // 위치는 매번 실제 충돌 프레임(107/118/118)으로 정확했고, 크기만 조명/
  // 구도에 따라 5.9~10.2%로 변동했다 — 6%는 이 변동폭 하단(5.9%)을 잘라
  // 미감지를 냈다. 탐색창이 이미 공이 핀 근접(16m 이상)에 도달한 이후로
  // 게이트돼 있어 창 내 노이즈 바닥이 낮으므로 4%로 낮춰도 오탐 위험은
  // 낮다.
  static const _homographyZoneImpactFloor = 0.04;
  static const double _pixelDiffThreshold = 30.0;
  // 릴리즈 직후 볼 스윙 이벤트를 오탐하지 않도록 최소 탐색 시작 프레임
  // 50 km/h 기준 18.29m 이동 = 1.3s = 39프레임 → 여유분 포함 20프레임
  static const _minTravelFrames = 20;

  /// 호모그래피로 핀 영역을 프레임 정규화좌표 존으로 투영한다.
  ///
  /// 핀덱 라인(y=18.29m)의 좌우 끝과 1.29m 앞(y=17.0m)의 좌우 끝, 총 4점을
  /// laneToFrame으로 투영해 핀덱의 화면상 위치(좌우 범위 산출용)를 얻는다.
  ///
  /// 수직(존 높이) 스케일은 더 이상 바닥 원근 압축(17→18.29m 투영 높이)에서
  /// 유도하지 않는다 — 낮은 카메라 각에서 바닥 깊이는 원근으로 극도로
  /// 압축되는 반면(실측 unit≈0.01) 서 있는 핀은 레인 평면 위 수직 물체라
  /// 이 압축을 받지 않으므로, 그 스케일을 그대로 쓰면 존이 핀을 못 담는다
  /// (실측 LTRB(0.50,0.41,0.75,0.43) — 높이 17px). 대신 압축 없는 **레인
  /// 폭**(핀덱 라인의 화면상 수평 폭, 실제 1.05m)에서 "이 거리에서 1m가
  /// 화면상 몇 ny인지"를 역산해 핀 높이(0.38m)를 존 높이로 환산한다.
  /// nx/ny 정규화 기준(각각 프레임 폭/높이)이 다르므로 [frameAspect](width/height)로
  /// 보정한다.
  ///
  /// 투영 결과가 화면 밖이거나(0~1 clamp 후) 존이 퇴화하면(빈 영역) null을
  /// 반환한다 — 호출부는 null이면 legacy 존으로 폴백해야 한다.
  static Rect? computePinZone(
    HomographyMatrix homography, {
    required double frameAspect,
  }) {
    final d0 = homography.laneToFrame(const LanePoint(xM: 0, yM: 18.29));
    final d1 = homography.laneToFrame(const LanePoint(xM: 1.05, yM: 18.29));
    final n0 = homography.laneToFrame(const LanePoint(xM: 0, yM: 17.0));
    final n1 = homography.laneToFrame(const LanePoint(xM: 1.05, yM: 17.0));

    for (final p in [d0, d1, n0, n1]) {
      if (!p.nx.isFinite || !p.ny.isFinite) return null;
    }
    if (frameAspect <= 0 || !frameAspect.isFinite) return null;

    final deckNy = (d0.ny + d1.ny) / 2;
    final deckWidthNx = (d1.nx - d0.nx).abs();
    if (deckWidthNx <= 0 || !deckWidthNx.isFinite) return null;

    // nx는 프레임 폭, ny는 프레임 높이로 정규화돼 있으므로 aspect로 환산해
    // 핀덱 거리에서 1m가 화면상 몇 ny인지 구한다.
    final nyPerMeter = deckWidthNx * frameAspect / 1.05;
    const pinHeightM = 0.38;
    final pinHeightNy = pinHeightM * nyPerMeter;
    if (pinHeightNy <= 0 || !pinHeightNy.isFinite) return null;

    final xs = [d0.nx, d1.nx, n0.nx, n1.nx];
    final left = (xs.reduce(math.min) - 0.02).clamp(0.0, 1.0);
    final right = (xs.reduce(math.max) + 0.02).clamp(0.0, 1.0);
    final top = (deckNy - pinHeightNy * 2.5).clamp(0.0, 1.0); // 서 있는 핀 + 튀는 핀 여유
    final bottom = (deckNy + pinHeightNy * 0.5).clamp(0.0, 1.0); // 핀 베이스 아래 약간

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

    // 검색 시작 프레임 자체를 씨드(기준)로 삼는다 — release~searchStart 구간의 자연스러운
    // 드리프트(카메라 미동/조명 변화)를 비교 대상에서 아예 제외해, 그 구간을 건너뛰고
    // 여기서부터의 "급격한" 변화만 감지한다. 과거(release=36, searchStart=56)에는 이 구간을
    // 넘어 release 프레임과 비교하다가, 첫 비교 자체가 20프레임 격차라 자연드리프트만으로도
    // 매번 임계값을 넘겨 검색 시작 지점에서 곧바로 오탐(핀 충돌 아님)이 발생했다.
    final seedFrame = frames[searchStart];
    img.Image prevZone = img.grayscale(_cropZone(seedFrame, pinZone));

    // 진단용 — 탐색 전체에서 관측된 최대 변화율과 그 프레임. 호모그래피 존
    // 경로에서는 이 값 자체가 채택 기준(argmax)이 된다. legacy 경로에서는
    // 여전히 "임계값을 못 넘어 미감지"로 끝나는 경우의 진단용으로만 쓰인다.
    double maxRatio = 0;
    int maxRatioFrame = searchStart;

    for (int i = searchStart + 1; i < frames.length; i++) {
      final frame = frames[i];
      final grayZone = img.grayscale(_cropZone(frame, pinZone));

      final ratio = _changeRatio(prevZone, grayZone);
      // strict `>` 비교이므로 동률이면 최초로 관측된 프레임을 유지한다.
      if (ratio > maxRatio) {
        maxRatio = ratio;
        maxRatioFrame = i;
      }

      // legacy(존 미지정) 경로만 첫 돌파 방식을 유지한다 — 존이 상단 20%로
      // 크고 신호도 굵어 첫 돌파로도 안정적으로 잡힌다.
      if (pinZone == null && ratio >= _changeThreshold) {
        debugPrint('[PinImpact] 핀 충돌 프레임: $i (변화율: ${(ratio * 100).toStringAsFixed(1)}%, 존: legacy)');
        return i;
      }
      prevZone = grayZone;
    }

    // 호모그래피 존 경로: 탐색은 이미 공이 핀 근접(≥16m)에 도달한 이후로
    // 게이트돼 있어 창이 충돌 근처로 좁다. 그 좁은 창 안에서 프레임간
    // 변화율이 가장 큰 지점이 곧 핀이 흩어지는(빛/그림자가 요동치는) 순간이다.
    // 첫-돌파+고정 임계값은 조명/구도별 신호 크기 편차에 취약해서 실측
    // (최대 변화율 9.4%)이 구 임계값(10%)에 못 미쳐 두 런 연속 미감지가
    // 났다 — 그래서 창 전체를 스캔한 뒤 최대값(argmax)을 채택하고, 노이즈와
    // 구분하기 위한 완화된 바닥(4%)만 넘으면 인정한다.
    if (pinZone != null && maxRatio >= _homographyZoneImpactFloor) {
      debugPrint('[PinImpact] 핀 충돌 프레임: $maxRatioFrame (최대 변화율: '
          '${(maxRatio * 100).toStringAsFixed(1)}%, 존: 호모그래피/argmax)');
      return maxRatioFrame;
    }

    final threshold = pinZone != null ? _homographyZoneImpactFloor : _changeThreshold;
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
