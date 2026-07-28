import 'package:bowling_diary/features/analysis/domain/services/pin_row_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const int _w = 100;
const int _h = 180;

img.Image _blackFrame() => img.Image(width: _w, height: _h)
  ..clear(img.ColorRgb8(0, 0, 0));

/// [y0]~[y1](양끝 포함) 행에 폭 [barWidth]px, 간격 [gap]px인 세로 막대
/// [count]개를 [startX]부터 그린다 — 핀 행(분리된 다수 run) 흉내용.
void _paintBars(
  img.Image frame, {
  required int y0,
  required int y1,
  required int count,
  int startX = 5,
  int barWidth = 6,
  int gap = 8,
}) {
  final stride = barWidth + gap;
  for (var i = 0; i < count; i++) {
    final x0 = startX + i * stride;
    final x1 = x0 + barWidth - 1;
    img.fillRect(frame, x1: x0, y1: y0, x2: x1, y2: y1, color: img.ColorRgb8(255, 255, 255));
  }
}

/// 하나의 통짜 흰 가로 바(run 1개)를 그린다 — 조명 패널/기계 바 흉내용.
void _paintSolidBar(img.Image frame, {required int y0, required int y1, required int x0, required int x1}) {
  img.fillRect(frame, x1: x0, y1: y0, x2: x1, y2: y1, color: img.ColorRgb8(255, 255, 255));
}

void main() {
  group('detectPinRowZone', () {
    test('검정 배경 + 밝은 세로 막대 6개(핀 흉내) → 밴드를 덮는 존, 가로 범위가 막대들을 포함', () {
      final frame = _blackFrame();
      _paintBars(frame, y0: 40, y1: 59, count: 6);

      final zone = detectPinRowZone(frame);

      expect(zone, isNotNull);
      expect(zone!.top * _h, lessThan(40));
      expect(zone.bottom * _h, greaterThan(60));
      // 첫 막대 시작(x=5) ~ 마지막 막대 끝(x=5+5*14+5=80) 포함 여부.
      expect(zone.left * _w, lessThanOrEqualTo(5));
      expect(zone.right * _w, greaterThanOrEqualTo(80));
    });

    test('같은 위치에 통짜 흰 가로 바(run 1개) → null', () {
      final frame = _blackFrame();
      // 밝은 비율은 4~60% 범위 안(36px/100=36%)으로 맞추되 run은 1개뿐.
      _paintSolidBar(frame, y0: 40, y1: 59, x0: 32, x1: 67);

      final zone = detectPinRowZone(frame);

      expect(zone, isNull);
      expect(67 - 32 + 1, 36); // 의도한 밝은 비율 확인(36%, 4~60% 범위 안)
    });

    test('막대 밴드가 두 개면 아래쪽(y가 더 큰) 밴드를 선택한다', () {
      final frame = _blackFrame();
      // 위쪽 밴드: run 3개 (조건 만족 최소치).
      _paintBars(frame, y0: 20, y1: 29, count: 3);
      // 아래쪽 밴드: run 5개.
      _paintBars(frame, y0: 50, y1: 69, count: 5);

      final zone = detectPinRowZone(frame);

      expect(zone, isNotNull);
      // 아래쪽 밴드(50~69)를 덮어야 하며, 위쪽 밴드(20~29)는 포함하지 않는다.
      expect(zone!.top * _h, lessThan(50));
      expect(zone.top * _h, greaterThan(29));
      expect(zone.bottom * _h, greaterThan(69));
    });

    test('전부 어두우면 null', () {
      final frame = _blackFrame();

      expect(detectPinRowZone(frame), isNull);
    });

    test('밴드가 과도하게 두꺼우면(프레임 40%) null', () {
      final frame = _blackFrame();
      // 높이 180의 40% = 72행. 상단 70%(126행) 스캔 범위 안에 들어가도록 배치.
      _paintBars(frame, y0: 20, y1: 91, count: 6);

      final zone = detectPinRowZone(frame);

      expect(zone, isNull);
    });

    test('레인 반사 모사(밝은 나무색 배경 위 흰 막대)는 틈 어두움 필터로 기각', () {
      // 실영상 계측 근거: 핀 행의 run 사이 틈은 피트(검정, p25 25~60)지만
      // 레인 반사/마킹의 틈은 밝은 나무색(p25 104~177). 배경을 나무색(160)으로
      // 채우고 같은 막대 패턴을 그리면 run/비율 조건은 통과해도 틈 p25(160)가
      // 필터(<60)에 걸려 null이어야 한다.
      final frame = img.Image(width: _w, height: _h)
        ..clear(img.ColorRgb8(160, 160, 160));
      _paintBars(frame, y0: 40, y1: 60, count: 6);

      expect(detectPinRowZone(frame), isNull);
    });

    test('핀 밴드(검정 틈)와 그 아래 반사 밴드(밝은 틈)가 공존하면 핀 밴드를 선택', () {
      // 실영상 재현 케이스: 반사 밴드가 더 아래(프레임 ~69%)에 있어도 틈
      // 어두움 필터로 자격을 잃으므로, "최하단" 규칙은 자격 밴드(핀)에만
      // 적용된다.
      final frame = _blackFrame();
      _paintBars(frame, y0: 40, y1: 60, count: 6);
      img.fillRect(frame, x1: 0, y1: 90, x2: _w - 1, y2: 110,
          color: img.ColorRgb8(160, 160, 160));
      _paintBars(frame, y0: 90, y1: 110, count: 6);

      final zone = detectPinRowZone(frame);

      expect(zone, isNotNull);
      expect(zone!.bottom * _h, lessThan(75)); // 반사 밴드(90~110)가 아니라 핀 밴드
      expect(zone.top * _h, lessThan(40));
    });
  });
}
