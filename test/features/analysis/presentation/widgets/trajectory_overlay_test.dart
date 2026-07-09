import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/trajectory_overlay.dart';

void main() {
  group('computeCoverRect', () {
    test('가로로 넓은 영상 → 좁은 컨테이너에서 좌/우가 잘림(세로에 맞춰 확대)', () {
      // 영상 2:1, 컨테이너 1:1(400x400) → 세로(400) 기준 확대 → 가로 800, 좌우 각 200씩 컨테이너 밖으로.
      const containerSize = Size(400, 400);
      const imageSize = Size(1600, 800);

      final rect = computeCoverRect(containerSize, imageSize);

      expect(rect.width, closeTo(800, 0.001));
      expect(rect.height, closeTo(400, 0.001));
      expect(rect.left, closeTo(-200, 0.001));
      expect(rect.top, closeTo(0, 0.001));
    });

    test('세로로 긴 영상 → 넓은 컨테이너에서 상/하가 잘림(가로에 맞춰 확대)', () {
      // 영상 1:2, 컨테이너 1:1(400x400) → 가로(400) 기준 확대 → 세로 800, 상하 각 200씩 컨테이너 밖으로.
      const containerSize = Size(400, 400);
      const imageSize = Size(800, 1600);

      final rect = computeCoverRect(containerSize, imageSize);

      expect(rect.height, closeTo(800, 0.001));
      expect(rect.width, closeTo(400, 0.001));
      expect(rect.top, closeTo(-200, 0.001));
      expect(rect.left, closeTo(0, 0.001));
    });

    test('영상-컨테이너 비율 일치 시 잘림 없이 컨테이너 전체를 정확히 채움', () {
      const containerSize = Size(300, 300);
      const imageSize = Size(1200, 1200);

      final rect = computeCoverRect(containerSize, imageSize);

      expect(rect, const Rect.fromLTWH(0, 0, 300, 300));
    });

    test('컨테이너 또는 영상 크기가 0이면 컨테이너 전체를 그대로 반환', () {
      const containerSize = Size(300, 300);

      final rect = computeCoverRect(containerSize, Size.zero);

      expect(rect, const Rect.fromLTWH(0, 0, 300, 300));
    });
  });

  group('TrajectoryOverlay 렌더링', () {
    testWidgets('점이 2개 미만이면 아무것도 그리지 않는다(에러 없이 빈 상태)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: TrajectoryOverlay(
                points: [FramePoint(nx: 0.5, ny: 0.5)],
                videoSize: Size(800, 800),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(TrajectoryOverlay), findsOneWidget);
      // 크래시 없이 렌더된 것으로 충분 — CustomPainter 픽셀 출력은 이 프로젝트 관례상 검증 대상 아님.
    });

    testWidgets('점이 2개 이상이면 정상적으로 렌더된다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: TrajectoryOverlay(
                points: [
                  FramePoint(nx: 0.5, ny: 0.9),
                  FramePoint(nx: 0.5, ny: 0.1),
                ],
                videoSize: Size(800, 800),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(TrajectoryOverlay), findsOneWidget);
    });
  });
}
