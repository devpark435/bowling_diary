import 'dart:ui';

import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _blackFrame(int w, int h) => img.Image(width: w, height: h);

img.Image _whiteFrame(int w, int h) => img.Image(width: w, height: h)
  ..clear(img.ColorRgb8(255, 255, 255));

/// 존(20x20=400px, LTRB(0.4,0.0,0.6,0.2) on 100x100 프레임) 안에서 지정한
/// 픽셀 수만큼 위에서부터 행(20px/행) 단위로 흰색 채운다 — 씨드(검정) 대비
/// diff 비율을 px/400으로 정밀 제어하기 위한 헬퍼.
img.Image _zoneFrame(int px) {
  final frame = img.Image(width: 100, height: 100);
  var remaining = px < 0 ? 0 : (px > 400 ? 400 : px);
  var y = 0;
  while (remaining > 0 && y < 20) {
    final int rowPx = remaining >= 20 ? 20 : remaining;
    img.fillRect(frame, x1: 40, y1: y, x2: 40 + rowPx - 1, y2: y, color: img.ColorRgb8(255, 255, 255));
    remaining -= rowPx;
    y++;
  }
  return frame;
}

void main() {
  late PinImpactDetectorService sut;
  setUp(() => sut = PinImpactDetectorService());

  test('릴리즈 직후(minTravelFrames 이내) 큰 변화는 무시', () {
    final frames = <img.Image>[
      ...List.generate(10, (_) => _blackFrame(100, 100)),
      ...List.generate(10, (_) => _whiteFrame(100, 100)),
      ...List.generate(30, (_) => _blackFrame(100, 100)),
    ];
    final result = sut.findImpactFrame(frames, 0);
    expect(result, isNull);
  });

  test('minTravelFrames 이후 큰 변화는 충돌로 감지', () {
    final frames = <img.Image>[
      ...List.generate(25, (_) => _blackFrame(100, 100)),
      _whiteFrame(100, 100),
      ...List.generate(10, (_) => _blackFrame(100, 100)),
    ];
    final result = sut.findImpactFrame(frames, 0);
    expect(result, isNotNull);
    expect(result!, greaterThanOrEqualTo(20));
  });

  test('프레임 부족 시 null', () {
    final frames = List.generate(5, (_) => _blackFrame(100, 100));
    expect(sut.findImpactFrame(frames, 0), isNull);
  });

  test('releaseFrame이 후반부라 searchStart >= frames.length 이면 null', () {
    final frames = List.generate(25, (_) => _blackFrame(100, 100));
    expect(sut.findImpactFrame(frames, 20), isNull);
  });

  test('release~searchStart 구간의 점진적 드리프트는 무시하고, 그 이후 급격한 변화만 충돌로 감지 (실기기 재현)', () {
    // 프레임 0(release)은 어둡게(luminance 10), 프레임 19(=searchStart-1)까지 서서히 밝아져
    // 프레임 20(=searchStart)에서는 luminance 120 — release 프레임과 비교하면 20프레임 격차 동안
    // 누적된 큰 차이지만, 프레임간(1-프레임) 변화는 항상 완만하다. 프레임 30에서 실제 핀 충돌을
    // 흉내낸 급격한 밝기 변화(255)가 발생한다.
    final frames = <img.Image>[
      for (var i = 0; i <= 20; i++) (img.Image(width: 100, height: 100)..clear(img.ColorRgb8(10 + i * 5, 10 + i * 5, 10 + i * 5))),
      ...List.generate(9, (i) => img.Image(width: 100, height: 100)..clear(img.ColorRgb8(120, 120, 120))),
      img.Image(width: 100, height: 100)..clear(img.ColorRgb8(255, 255, 255)), // frame 30: 실제 충돌
      ...List.generate(9, (_) => img.Image(width: 100, height: 100)..clear(img.ColorRgb8(255, 255, 255))),
    ];
    final result = sut.findImpactFrame(frames, 0);
    expect(result, 30);
  });

  group('searchStartOverride', () {
    test('override가 주어지면 그 지점부터 탐색해 이전 구간의 변화는 무시한다', () {
      // 프레임 25와 45가 모두 흰색. override 없이(legacy) 탐색하면 searchStart=20이라
      // 먼저 만나는 25를 반환하지만, override=40을 주면 25는 이미 지나버린 구간이라
      // 무시하고 45를 반환한다.
      final frames = <img.Image>[
        for (var i = 0; i < 60; i++) i == 25 || i == 45 ? _whiteFrame(100, 100) : _blackFrame(100, 100),
      ];

      expect(sut.findImpactFrame(frames, 0), 25);
      expect(sut.findImpactFrame(frames, 0, searchStartOverride: 40), 45);
    });

    test('override <= releaseFrame이면 releaseFrame + minTravelFrames로 폴백한다', () {
      // releaseFrame=30, override=10(<=releaseFrame) → 폴백 searchStart=30+20=50.
      // 프레임 55만 흰색이므로 55가 반환되어야 폴백이 실제로 적용됐음을 확인할 수 있다.
      final frames = <img.Image>[
        for (var i = 0; i < 60; i++) i == 55 ? _whiteFrame(100, 100) : _blackFrame(100, 100),
      ];

      final result = sut.findImpactFrame(frames, 30, searchStartOverride: 10);

      expect(result, 55);
    });
  });

  group('computePinZone', () {
    test('레인 평면 정사영 호모그래피에서 핀덱 상단부 존을 계산(레인 폭 기준 수직 스케일)', () {
      // laneToFrame: nx = xM/1.05, ny = 1 - yM/18.29.
      // d0=(0,0), d1=(1,0) → deckNy=0, deckWidthNx=1.
      // nyPerMeter = 1*0.5627/1.05 ≈ 0.5359, pinHeightNy ≈ 0.2036.
      // top = 0 - 0.509 → clamp 0, bottom = 0 + 0.1018 ≈ 0.1018.
      // left = -0.02 → 0, right = 1.02 → 1.
      final homography = HomographyMatrix.fromRowMajor(
        [1.05, 0, 0, 0, -18.29, 18.29, 0, 0, 1],
      );
      final zone = PinImpactDetectorService.computePinZone(homography, frameAspect: 0.5627);
      expect(zone, isNotNull);
      expect(zone!.left, closeTo(0.0, 1e-3));
      expect(zone.top, closeTo(0.0, 1e-3));
      expect(zone.right, closeTo(1.0, 1e-3));
      expect(zone.bottom, closeTo(0.1018, 1e-3));
    });

    test('퇴화 존(identity 호모그래피)은 null', () {
      final homography = HomographyMatrix.identity();
      final zone = PinImpactDetectorService.computePinZone(homography, frameAspect: 0.5627);
      expect(zone, isNull);
    });
  });

  group('findImpactFrame with pinZone (씨드 대비 + 지속성)', () {
    // 존은 20x20=400px (zone LTRB 0.4,0.0,0.6,0.2 on 100x100 프레임).
    // releaseFrame=0 → searchStart = 0 + minTravelFrames(20) = 20 → 씨드는
    // 프레임 20(검정).

    test('폭발 감지: 프레임 30부터 끝까지 지속되는 존 내부 30% 면적 흰색 변화 → 30 반환', () {
      const zone = Rect.fromLTRB(0.4, 0.0, 0.6, 0.2);
      final frames = List.generate(40, (i) {
        final frame = img.Image(width: 100, height: 100);
        // 30% = 120px. 20col(40~59) x 6row(0~5) = 120px, 프레임 30부터 끝까지 유지.
        if (i >= 30) {
          img.fillRect(frame, x1: 40, y1: 0, x2: 59, y2: 5, color: img.ColorRgb8(255, 255, 255));
        }
        return frame;
      });
      final result = sut.findImpactFrame(frames, 0, pinZone: zone);
      expect(result, 30);
    });

    test('공 접근 램프 + 폭발 점프: 폭발 시점(최대 증가 프레임)을 반환한다 (실영상 재현)', () {
      const zone = Rect.fromLTRB(0.4, 0.0, 0.6, 0.2);
      // 실영상 패턴 재현: 공이 존을 향해 접근하며 씨드 대비 diff가 프레임당
      // ~2%p씩 완만히 증가(램프)하다가, 폭발 프레임에서 30%로 점프해 고착.
      // 첫-돌파 방식은 램프가 15%를 통과하는 프레임(공)을 잡는 반면,
      // Δd argmax는 점프 프레임(진짜 폭발)을 잡아야 한다.
      // 존 400px: 프레임 21+k에서 4k px(=k%p) 변화 (k=1..12 → 1~12%),
      // 프레임 34부터 120px(30%) 고정.
      final frames = List.generate(45, (i) {
        final frame = img.Image(width: 100, height: 100);
        if (i >= 34) {
          img.fillRect(frame, x1: 40, y1: 0, x2: 59, y2: 5, color: img.ColorRgb8(255, 255, 255)); // 30%
        } else if (i >= 22) {
          final k = i - 21; // 1..12 → 4k px = k%
          img.fillRect(frame, x1: 40, y1: 0, x2: 40 + 4 * k - 1, y2: 0, color: img.ColorRgb8(255, 255, 255));
        }
        return frame;
      });
      final result = sut.findImpactFrame(frames, 0, pinZone: zone);
      // 램프 구간(22~33, 최대 12% — floor 미달이지만 설령 넘더라도 Δd는
      // 프레임당 1%p뿐)이 아니라 점프 프레임(34, Δd = 30-12 = 18%p)이어야 한다.
      expect(result, 34);
    });

    test('램프 후보가 floor(3%p)를 넘어도 지속 상승이면 기각되고, 진짜 플래토(폭발) 프레임을 채택한다', () {
      const zone = Rect.fromLTRB(0.4, 0.0, 0.6, 0.2);
      // releaseFrame=0 → searchStart=20, 씨드=프레임20(검정).
      // 프레임 22~29: 4%p/frame 램프(16px씩 증가, 4%~32%) — 매 스텝 Δ=4%p로
      // floor(3%p)는 넘지만, 8프레임 뒤에도(=폭발 프레임 70%까지) 계속
      // 오르므로 lookahead(cap 4%p)를 매번 초과해 전부 기각돼야 한다.
      // 프레임 30부터 70%(280px)로 점프해 끝까지 고착 — 이 프레임(Δ=38%p,
      // 이후 8프레임 변화 0%p)이 채택돼야 한다.
      final frames = [
        for (var i = 0; i < 50; i++)
          if (i < 22)
            _zoneFrame(0)
          else if (i < 30)
            _zoneFrame(16 * (i - 21))
          else
            _zoneFrame(280),
      ];
      final result = sut.findImpactFrame(frames, 0, pinZone: zone);
      expect(result, 30);
    });

    test('창 끝 폭발: 탐색 창 마지막 근처에서 시작된 점프는 이후 8프레임을 다 볼 수 없어도(lookahead 면제) 채택한다', () {
      const zone = Rect.fromLTRB(0.4, 0.0, 0.6, 0.2);
      // 프레임 22~28: 2.5%p/frame의 완만한 램프(floor 미달, 후보 아님).
      // 프레임 29에서 30%로 점프(Δ=12.5%p, floor 통과) — 탐색 창의 마지막
      // 프레임이 30(=searchStart+1+9)이라 이후 남은 프레임이 1개뿐이라
      // lookahead(8프레임)를 다 볼 수 없다 → 면제로 즉시 채택돼야 한다.
      // (면제가 없었다면 프레임 30의 50%까지 추가 상승해 lookahead=20%p로
      // cap을 초과, 기각됐을 것이다.)
      final frames = [
        for (var i = 0; i < 31; i++)
          if (i < 22)
            _zoneFrame(0)
          else if (i < 29)
            _zoneFrame(10 * (i - 21))
          else if (i == 29)
            _zoneFrame(120)
          else
            _zoneFrame(200),
      ];
      final result = sut.findImpactFrame(frames, 0, pinZone: zone);
      expect(result, 29);
    });

    test('전부 램프(감속하며 계속 상승만, 창 끝 중앙값은 게이트 통과) → 후보가 전부 기각돼 폴백(Δd argmax) 동작', () {
      const zone = Rect.fromLTRB(0.4, 0.0, 0.6, 0.2);
      // 프레임 21~34(diffs idx0~13): 감속하는 램프 — 초반 Δ=5%p(floor 통과,
      // 후보)가 반복되지만 8프레임 뒤에도 계속 올라 lookahead가 cap을
      // 초과해 매번 기각된다. 후반부(idx6 이후)는 Δ<3%p로 애초에 후보조차
      // 아니다. 끝까지 진짜 플래토가 없으므로(전부 램프) 채택되는 후보가
      // 없어 v2 폴백(Δd argmax)으로 넘어가야 하고, 그 최대 Δ는 idx1(첫
      // 5%p 스텝, 이후 동률은 갱신 안 됨) → 프레임 22가 반환돼야 한다.
      const pxByIdx = [0, 20, 40, 60, 76, 88, 96, 100, 102, 103, 104, 104, 105, 105];
      final frames = [
        for (var i = 0; i < 35; i++)
          if (i < 21)
            _zoneFrame(0)
          else
            _zoneFrame(pxByIdx[i - 21]),
      ];
      final result = sut.findImpactFrame(frames, 0, pinZone: zone);
      expect(result, 22);
    });

    test('공 통과 무시: 프레임 30~40에만 씨드 대비 8%짜리 흰 블롭, 41부터 원상복구 → null (floor 미달)', () {
      const zone = Rect.fromLTRB(0.4, 0.0, 0.6, 0.2);
      // 8% = 32px. 16col(40~55) x 2row(0~1) = 32px.
      final frames = List.generate(50, (i) {
        final frame = img.Image(width: 100, height: 100);
        if (i >= 30 && i <= 40) {
          img.fillRect(frame, x1: 40, y1: 0, x2: 55, y2: 1, color: img.ColorRgb8(255, 255, 255));
        }
        return frame;
      });
      final result = sut.findImpactFrame(frames, 0, pinZone: zone);
      expect(result, isNull);
    });

    test('1-프레임 스파이크 무시: 프레임 30 한 프레임만 존 50% 변화, 31부터 원상복구 → null (지속성 실패)', () {
      const zone = Rect.fromLTRB(0.4, 0.0, 0.6, 0.2);
      // 50% = 200px. 20col(40~59) x 10row(0~9) = 200px, 프레임 30에서만.
      final frames = List.generate(40, (i) {
        final frame = img.Image(width: 100, height: 100);
        if (i == 30) {
          img.fillRect(frame, x1: 40, y1: 0, x2: 59, y2: 9, color: img.ColorRgb8(255, 255, 255));
        }
        return frame;
      });
      final result = sut.findImpactFrame(frames, 0, pinZone: zone);
      expect(result, isNull);
    });

    test('경계: 변화가 마지막 3프레임에서 시작(이후 프레임 4개 미만) → 존재하는 프레임 전부 persist floor 이상이면 감지', () {
      const zone = Rect.fromLTRB(0.4, 0.0, 0.6, 0.2);
      // 총 33프레임(0~32), searchStart=20, 마지막 인덱스는 32. 변화는
      // 프레임 30부터 시작(30,31,32 — 마지막 3프레임)해 끝까지 지속되므로
      // 이후 프레임은 2개(31,32)뿐이나 전부 persist floor 이상이어야 감지된다.
      final frames = List.generate(33, (i) {
        final frame = img.Image(width: 100, height: 100);
        if (i >= 30) {
          img.fillRect(frame, x1: 40, y1: 0, x2: 59, y2: 5, color: img.ColorRgb8(255, 255, 255));
        }
        return frame;
      });
      final result = sut.findImpactFrame(frames, 0, pinZone: zone);
      expect(result, 30);
    });

    test('존 외부 변화는 무시', () {
      const zone = Rect.fromLTRB(0.4, 0.0, 0.6, 0.2);
      final frames = List.generate(40, (i) {
        final frame = img.Image(width: 100, height: 100);
        if (i >= 30) {
          img.fillRect(frame, x1: 0, y1: 50, x2: 99, y2: 99, color: img.ColorRgb8(255, 255, 255));
        }
        return frame;
      });
      final result = sut.findImpactFrame(frames, 0, pinZone: zone);
      expect(result, isNull);
    });
  });
}
