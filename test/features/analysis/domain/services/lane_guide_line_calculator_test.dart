import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/lane_guide_line_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeLaneGuideLines', () {
    // foul-left, foul-right, pin-right, pin-left 순서(자동검출 코너 규약과 동일).
    // 근처(ny=0.9) 두 점 = 파울라인, 먼(ny=0.1) 두 점 = 핀덱.
    const corners = [
      FramePoint(nx: 0.2, ny: 0.9),
      FramePoint(nx: 0.8, ny: 0.9),
      FramePoint(nx: 0.7, ny: 0.1),
      FramePoint(nx: 0.3, ny: 0.1),
    ];

    test('4개 기준선(파울라인/에로우/레인지파인더/핀덱)을 순서대로 반환', () {
      final lines = computeLaneGuideLines(corners);

      expect(lines, isNotNull);
      expect(lines!.length, 4);
      expect(lines.map((l) => l.yM), [0, 4.57, 12.19, 18.29]);
      expect(lines.map((l) => l.label), ['파울라인', '에로우(화살표)', '레인지파인더', '핀덱(구석 핀 머리 높이에)']);
      expect(lines[0].drawLine, isFalse);
      expect(lines[1].drawLine, isTrue);
      expect(lines[2].drawLine, isTrue);
      expect(lines[3].drawLine, isFalse);
    });

    test('파울라인(y=0)/핀덱(y=18.29) 투영은 입력 코너와 정확히 일치', () {
      final lines = computeLaneGuideLines(corners)!;

      // 호모그래피는 4개 대응점을 정확히 통과하므로, y=0/y=18.29 투영은
      // laneToFrame 왕복 후에도 원래 코너 좌표와 일치해야 한다.
      expect(lines[0].left.nx, closeTo(corners[0].nx, 1e-9));
      expect(lines[0].left.ny, closeTo(corners[0].ny, 1e-9));
      expect(lines[0].right.nx, closeTo(corners[1].nx, 1e-9));
      expect(lines[0].right.ny, closeTo(corners[1].ny, 1e-9));

      expect(lines[3].right.nx, closeTo(corners[2].nx, 1e-9));
      expect(lines[3].right.ny, closeTo(corners[2].ny, 1e-9));
      expect(lines[3].left.nx, closeTo(corners[3].nx, 1e-9));
      expect(lines[3].left.ny, closeTo(corners[3].ny, 1e-9));
    });

    test('에로우/레인지파인더 선은 파울라인과 핀덱 사이(ny 보간)에 위치', () {
      final lines = computeLaneGuideLines(corners)!;

      final foulNy = lines[0].left.ny; // ≈0.9 (근처)
      final arrowsNy = lines[1].left.ny; // y=4.57
      final rangefinderNy = lines[2].left.ny; // y=12.19
      final pinNy = lines[3].left.ny; // ≈0.1 (먼 쪽)

      // yM이 클수록 화면상 더 위(ny 작음)로 이동해야 한다 — 근→원 단조감소.
      expect(arrowsNy, lessThan(foulNy));
      expect(rangefinderNy, lessThan(arrowsNy));
      expect(pinNy, lessThan(rangefinderNy));

      // 두 중간선 모두 파울라인/핀덱 사이 구간 안에 있어야 한다(보간 검증).
      expect(arrowsNy, inInclusiveRange(pinNy, foulNy));
      expect(rangefinderNy, inInclusiveRange(pinNy, foulNy));
    });

    test('좌우 폭(xM=0 vs xM=1.05) 투영도 대칭적으로 갈라진다', () {
      final lines = computeLaneGuideLines(corners)!;
      for (final line in lines) {
        expect(line.right.nx, greaterThan(line.left.nx));
      }
    });

    test('4점이 아니면 null 반환(크래시 없음)', () {
      expect(computeLaneGuideLines(const [FramePoint(nx: 0, ny: 0)]), isNull);
      expect(computeLaneGuideLines(const []), isNull);
    });

    test('퇴화 사각형(일직선 위 4점)은 호모그래피를 풀 수 없어 null 반환', () {
      // homography_solver_test.dart의 특이 케이스와 동일한 형태 — 프레임 코너가
      // 모두 한 직선 위에 있으면 레인 사각형(비직선)으로 매핑하는 호모그래피가
      // 존재하지 않는다(호모그래피는 공선성을 보존).
      const degenerate = [
        FramePoint(nx: 0, ny: 0),
        FramePoint(nx: 0.3, ny: 0),
        FramePoint(nx: 0.6, ny: 0),
        FramePoint(nx: 1, ny: 0),
      ];

      expect(computeLaneGuideLines(degenerate), isNull);
    });
  });
}
