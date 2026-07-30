import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/arrow_detector.dart';
import 'package:bowling_diary/features/analysis/domain/services/lane_landmark_speed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 실영상에서 검출된 조준 화살표 7개의 중심(반해상도 960×540 px, 레인 가로).
/// board 5~35이 12·13·14·15·14·13·12ft로 셰브론을 이룬다.
const _measured = <(double, double)>[
  (626.3, 141.5),
  (620.4, 175.4),
  (615.2, 208.5),
  (610.4, 240.8), // 꼭짓점(board 20)
  (614.3, 274.6),
  (619.4, 309.6),
  (624.2, 345.5),
];

const _laneLuminance = 150;
const _arrowLuminance = 88;

img.Image _blank(int w, int h) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, _laneLuminance, _laneLuminance, _laneLuminance);
    }
  }
  return im;
}

void _stamp(img.Image im, double cx, double cy, {int side = 5}) {
  final half = side ~/ 2;
  for (var dy = -half; dy <= half; dy++) {
    for (var dx = -half; dx <= half; dx++) {
      final x = cx.round() + dx;
      final y = cy.round() + dy;
      if (x < 0 || y < 0 || x >= im.width || y >= im.height) continue;
      im.setPixelRgb(x, y, _arrowLuminance, _arrowLuminance, _arrowLuminance);
    }
  }
}

/// 레인이 가로로 누운 프레임(계측 좌표 그대로).
img.Image _landscapeFrame(List<(double, double)> marks, {int side = 5}) {
  final im = _blank(960, 540);
  for (final m in marks) {
    _stamp(im, m.$1, m.$2, side: side);
  }
  return im;
}

/// 레인이 세로로 선 프레임(실제 파이프라인 방향 — 핀이 화면 위).
img.Image _portraitFrame(List<(double, double)> marks, {int side = 5}) {
  final im = _blank(540, 960);
  for (final m in marks) {
    _stamp(im, m.$2, m.$1, side: side); // 축 교환
  }
  return im;
}

void main() {
  group('detectArrows', () {
    test('레인 가로 프레임에서 화살표 7개를 찾는다', () {
      final found = detectArrows(_landscapeFrame(_measured));
      expect(found.length, _measured.length);
      // 중심이 실측 위치와 1px(정규화 환산) 이내로 맞아야 한다.
      for (final m in _measured) {
        final target = FramePoint(nx: m.$1 / 960, ny: m.$2 / 540);
        final hit = found.any((p) =>
            (p.nx - target.nx).abs() < 1 / 960 && (p.ny - target.ny).abs() < 1 / 540);
        expect(hit, isTrue, reason: '(${m.$1}, ${m.$2}) 미검출');
      }
    });

    test('레인 세로 프레임(실제 파이프라인 방향)에서도 찾는다', () {
      final found = detectArrows(_portraitFrame(_measured));
      expect(found.length, _measured.length);
    });

    test('검출 결과로 iso-u 선이 만들어진다', () {
      final found = detectArrows(_landscapeFrame(_measured));
      final line = arrowLineFromDetections(found);
      expect(line, isNotNull);
      expect(line!.uM, kOuterArrowUM);
      // 양 끝은 셰브론의 가장 벌어진 쌍(첫·마지막 화살표).
      final ends = [line.a.ny, line.b.ny]..sort();
      expect(ends.first, closeTo(141.5 / 540, 0.01));
      expect(ends.last, closeTo(345.5 / 540, 0.01));
    });

    test('빈 레인(표식 없음)이면 빈 리스트', () {
      expect(detectArrows(_blank(960, 540)), isEmpty);
    });

    test('일직선 표식(레인 이음매)은 셰브론 검증에서 걸러진다', () {
      final collinear = [
        for (var k = 0; k < 7; k++) (620.0, 141.5 + k * 34.0),
      ];
      expect(detectArrows(_landscapeFrame(collinear)), isEmpty);
    });

    test('개수가 범위를 벗어나면 빈 리스트', () {
      expect(detectArrows(_landscapeFrame(_measured.take(3).toList())), isEmpty);
    });

    test('크기가 다른 잡음 블롭이 섞여도 화살표 7개만 골라낸다', () {
      // 실촬영 첫 프레임 회귀 — 필터를 통과한 블롭 20개 중 화살표 7개(변 5~6)와
      // 잡음 13개(변 8~18)가 섞이자, 전체 크기 중앙값이 8로 잡혀 ±비율 창이 둘
      // 다 삼켰고 14개 → 개수 초과로 **전부** 버려졌다(검출 0개). 아래 잡음
      // 좌표/크기는 그 프레임에서 실제로 살아남던 것들이다.
      final im = _landscapeFrame(_measured);
      for (final n in <(double, double, int)>[
        (466, 441, 8),
        (445, 438, 8),
        (455, 433, 8),
        (370, 404, 14),
        (370, 362, 14),
        (371, 381, 11),
        (476, 452, 12),
      ]) {
        _stamp(im, n.$1, n.$2, side: n.$3);
      }

      final found = detectArrows(im);
      expect(found.length, _measured.length);
      for (final m in _measured) {
        final target = FramePoint(nx: m.$1 / 960, ny: m.$2 / 540);
        expect(
          found.any((p) =>
              (p.nx - target.nx).abs() < 1 / 960 * 2 &&
              (p.ny - target.ny).abs() < 1 / 540 * 2),
          isTrue,
          reason: '화살표 $m 를 못 찾음',
        );
      }
    });

    test('바깥 화살표가 빠진 5개 무리는 채택하지 않는다', () {
      // 구속 계산이 "최대분리 쌍 = board 5·35(둘 다 12ft)"를 가정하므로, 끝
      // 화살표가 빠진 무리를 받으면 기준 거리가 조용히 틀어진다.
      final inner = _measured.sublist(1, _measured.length - 1);
      expect(inner.length, 5);
      expect(detectArrows(_landscapeFrame(inner)), isEmpty);
    });

    test('탐색 영역 밖(핀덱 쪽) 표식은 무시된다', () {
      // 깊이축 nx를 0.35 미만(=336px 미만)으로 옮기면 후보에서 빠진다.
      final tooFar = _measured.map((m) => (m.$1 - 400, m.$2)).toList();
      expect(detectArrows(_landscapeFrame(tooFar)), isEmpty);
    });

    test('축소가 필요한 큰 프레임에서도 동작한다', () {
      // 1920×1080 — 실제 영상 해상도. 내부에서 장변 960으로 축소된다.
      final im = _blank(1920, 1080);
      for (final m in _measured) {
        _stamp(im, m.$1 * 2, m.$2 * 2, side: 10);
      }
      expect(detectArrows(im).length, _measured.length);
    });
  });

  group('isChevron', () {
    List<FramePoint> pts(List<(double, double)> src) =>
        [for (final m in src) FramePoint(nx: m.$1 / 960, ny: m.$2 / 540)];

    test('실측 화살표 배치는 셰브론이다', () {
      expect(isChevron(pts(_measured)), isTrue);
    });

    test('일직선은 셰브론이 아니다', () {
      expect(isChevron(pts([for (var k = 0; k < 7; k++) (620.0, 141.5 + k * 34.0)])), isFalse);
    });

    test('편차가 양쪽으로 갈리는(지그재그) 배치는 셰브론이 아니다', () {
      final zigzag = [
        for (var k = 0; k < 7; k++) (620.0 + (k.isEven ? 18.0 : -18.0), 141.5 + k * 34.0),
      ];
      expect(isChevron(pts(zigzag)), isFalse);
    });

    test('점이 3개 미만이면 false', () {
      expect(isChevron(pts(_measured.take(2).toList())), isFalse);
    });
  });
}
