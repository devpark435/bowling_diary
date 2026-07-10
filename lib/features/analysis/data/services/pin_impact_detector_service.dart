import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';

class PinImpactDetectorService {
  static const _pinZoneRatio = 0.20;
  static const _changeThreshold = 0.15;
  // 호모그래피 존 경로는 더 이상 프레임간(1-frame) diff의 argmax를 쓰지
  // 않는다 — 실기기 실물 판독으로 argmax(직전 프레임 대비 최대 변화율)가
  // 매번 "공이 존을 통과하는 순간"(프레임 117)을 "핀이 실제로 흩어지는
  // 순간"(프레임 ~127-129)보다 먼저/크게 잡는다는 게 확인됐다. 물리적으로
  // 공 통과와 핀 폭발은 존 면적 대비 변화율은 비슷해 보여도(공도 순간적으로
  // 큰 diff를 만든다) "지속성"이 다르다: 공은 지나가면 존이 원상복구되지만
  // 핀은 폭발하면 배치가 영구히 바뀐다.
  //
  // 그래서 두 단계로 재설계한다:
  // (1) 영구 변화 게이트 — 탐색 창 끝(마지막 5프레임) diff의 중앙값이
  //     floor(15%) 이상이어야 폭발이 실제로 일어난 것으로 본다. 공 통과는
  //     지나가면 존이 원상복구되어 끝 구간 diff가 낮게 유지되고, 1-프레임
  //     스파이크도 여기서 걸러진다. 폭발은 핀 배치가 영구히 바뀌므로
  //     (실측: 폭발 후 씨드 대비 34%로 고착) 게이트를 통과한다.
  // (2) 폭발 "시점" = 씨드 대비 diff의 최대 단일 프레임 증가(Δd) 지점.
  //     공 접근은 프레임당 +1~3%의 완만한 램프를 만들고 폭발은 뚜렷한
  //     급증을 만든다(실영상 검증: 접근 램프 +2%/frame, 폭발 프레임 +4.9%,
  //     Δd argmax = 실제 폭발 프레임 128 정확 적중). "최초로 floor를 넘는
  //     프레임" 방식은 공 접근 램프가 floor를 통과하는 지점(공)을 폭발로
  //     오인했다(실측: 119 오탐 vs 실제 128).
  static const _eruptionFloor = 0.15;
  static const _eruptionTailWindow = 5;
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
    //
    // 씨드는 공이 16m(핀 근접) 도달 시점의 존이라 아직 충돌 전 상태다. 이후
    // 모든 프레임의 존을 (직전 프레임이 아니라) 이 씨드와 비교한다 — 공이
    // 존을 통과하는 동안의 "직전 프레임 대비" 스파이크(legacy argmax의
    // 함정)를 배제하고, 씨드 상태에서 얼마나 영구적으로 달라졌는지만 본다.
    final seedFrame = frames[searchStart];
    final seedZone = img.grayscale(_cropZone(seedFrame, pinZone));

    if (pinZone == null) {
      // legacy(존 미지정) 경로는 기존 첫-돌파(직전 프레임 대비) 방식을
      // 그대로 유지한다 — 존이 상단 20%로 크고 신호도 굵어 첫 돌파로도
      // 안정적으로 잡힌다.
      img.Image prevZone = seedZone;
      double maxRatio = 0;
      int maxRatioFrame = searchStart;

      for (int i = searchStart + 1; i < frames.length; i++) {
        final grayZone = img.grayscale(_cropZone(frames[i], pinZone));
        final ratio = _changeRatio(prevZone, grayZone);
        if (ratio > maxRatio) {
          maxRatio = ratio;
          maxRatioFrame = i;
        }
        if (ratio >= _changeThreshold) {
          debugPrint('[PinImpact] 핀 충돌 프레임: $i (변화율: ${(ratio * 100).toStringAsFixed(1)}%, 존: legacy)');
          return i;
        }
        prevZone = grayZone;
      }

      debugPrint('[PinImpact] 핀 충돌 미감지 (임계값 ${(_changeThreshold * 100).toStringAsFixed(0)}%, '
          '탐색구간 최대 변화율 ${(maxRatio * 100).toStringAsFixed(1)}% @ 프레임 $maxRatioFrame, '
          '핀존 비율 ${(_pinZoneRatio * 100).toStringAsFixed(0)}%)');
      return null;
    }

    // 호모그래피 존 경로: 씨드 대비 diff를 프레임마다 계산해 저장한다.
    final diffs = <double>[];
    for (int i = searchStart + 1; i < frames.length; i++) {
      final grayZone = img.grayscale(_cropZone(frames[i], pinZone));
      diffs.add(_changeRatio(seedZone, grayZone));
    }

    double maxRatio = 0;
    int maxRatioFrame = searchStart;
    for (var idx = 0; idx < diffs.length; idx++) {
      if (diffs[idx] > maxRatio) {
        maxRatio = diffs[idx];
        maxRatioFrame = searchStart + 1 + idx;
      }
    }

    final zoneDesc = '핀존(호모그래피) LTRB(${pinZone.left.toStringAsFixed(2)},${pinZone.top.toStringAsFixed(2)},'
        '${pinZone.right.toStringAsFixed(2)},${pinZone.bottom.toStringAsFixed(2)})';

    // (1) 영구 변화 게이트: 창 끝 diff 중앙값이 floor 미만이면 폭발 없음 —
    // 공 통과/스파이크는 존이 원상복구돼 여기서 걸러진다 (클래스 doc 참조).
    if (diffs.isEmpty) {
      debugPrint('[PinImpact] 핀 폭발 미감지 (탐색 창 없음, $zoneDesc)');
      return null;
    }
    final tail = [...diffs.sublist(math.max(0, diffs.length - _eruptionTailWindow))]..sort();
    final tailMedian = tail[tail.length ~/ 2];
    if (tailMedian < _eruptionFloor) {
      debugPrint('[PinImpact] 핀 폭발 미감지 (창 끝 중앙값 ${(tailMedian * 100).toStringAsFixed(1)}% '
          '< ${(_eruptionFloor * 100).toStringAsFixed(0)}%, 씨드 대비 최대 '
          '${(maxRatio * 100).toStringAsFixed(1)}% @ 프레임 $maxRatioFrame, $zoneDesc)');
      return null;
    }

    // (2) 폭발 시점 = 씨드 대비 diff의 최대 단일 프레임 증가(Δd) 지점.
    // 첫 원소의 Δd는 씨드(=0) 대비 diffs[0] 자체.
    var bestIdx = 0;
    var bestDelta = diffs[0];
    for (var idx = 1; idx < diffs.length; idx++) {
      final delta = diffs[idx] - diffs[idx - 1];
      if (delta > bestDelta) {
        bestDelta = delta;
        bestIdx = idx;
      }
    }

    final impactFrame = searchStart + 1 + bestIdx;
    debugPrint('[PinImpact] 핀 폭발 프레임: $impactFrame '
        '(Δ${(bestDelta * 100).toStringAsFixed(1)}%p, 창 끝 중앙값 ${(tailMedian * 100).toStringAsFixed(1)}%, 존: 호모그래피)');
    return impactFrame;
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
