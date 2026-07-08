import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/lane_corner_overlay.dart';

void main() {
  group('computeContainRect', () {
    test('가로로 넓은 이미지 → 좁은 컨테이너에서 상/하 레터박스 발생', () {
      // 이미지 2:1, 컨테이너 1:1(400x400) → 표시 영역은 400x200, 상하 각 100씩 여백.
      const containerSize = Size(400, 400);
      const imageSize = Size(1600, 800);

      final rect = computeContainRect(containerSize, imageSize);

      expect(rect.left, closeTo(0, 0.001));
      expect(rect.width, closeTo(400, 0.001));
      expect(rect.height, closeTo(200, 0.001));
      expect(rect.top, closeTo(100, 0.001));
      expect(rect.bottom, closeTo(300, 0.001));
    });

    test('세로로 좁은 이미지 → 넓은 컨테이너에서 좌/우 레터박스 발생', () {
      // 이미지 1:2, 컨테이너 1:1(400x400) → 표시 영역은 200x400, 좌우 각 100씩 여백.
      const containerSize = Size(400, 400);
      const imageSize = Size(800, 1600);

      final rect = computeContainRect(containerSize, imageSize);

      expect(rect.top, closeTo(0, 0.001));
      expect(rect.height, closeTo(400, 0.001));
      expect(rect.width, closeTo(200, 0.001));
      expect(rect.left, closeTo(100, 0.001));
      expect(rect.right, closeTo(300, 0.001));
    });

    test('이미지-컨테이너 비율 일치 시 레터박스 없이 컨테이너 전체를 채움', () {
      const containerSize = Size(300, 300);
      const imageSize = Size(1200, 1200);

      final rect = computeContainRect(containerSize, imageSize);

      expect(rect, const Rect.fromLTWH(0, 0, 300, 300));
    });

    test('컨테이너 또는 이미지 크기가 0이면 컨테이너 전체를 그대로 반환', () {
      const containerSize = Size(300, 300);

      final rect = computeContainRect(containerSize, Size.zero);

      expect(rect, const Rect.fromLTWH(0, 0, 300, 300));
    });
  });

  group('LaneCornerOverlay 드래그 보정', () {
    // 이미지 2:1, 컨테이너 400x400 → 표시 영역 (0,100)-(400,300), 상하 100씩 레터박스.
    const containerSize = Size(400, 400);
    const imageSize = Size(1600, 800);
    const points = [
      FramePoint(nx: 0.2, ny: 0.8), // 화면 좌표 (80, 260)
      FramePoint(nx: 0.8, ny: 0.8), // 화면 좌표 (320, 260)
      FramePoint(nx: 0.7, ny: 0.3), // 화면 좌표 (280, 160)
      FramePoint(nx: 0.3, ny: 0.3), // 화면 좌표 (120, 160)
    ];

    Widget buildOverlay({required ValueChanged<List<FramePoint>> onChanged}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: containerSize.width,
            height: containerSize.height,
            child: LaneCornerOverlay(
              points: points,
              onChanged: onChanged,
              imageSize: imageSize,
            ),
          ),
        ),
      );
    }

    testWidgets('점 근처(32px 이내)에서 드래그를 시작하면 해당 점만 이동한다', (tester) async {
      List<FramePoint>? changed;
      await tester.pumpWidget(buildOverlay(onChanged: (p) => changed = p));

      final gesture = await tester.startGesture(const Offset(80, 260)); // points[0] 정확한 위치
      await tester.pump();
      await gesture.moveBy(const Offset(20, -10)); // → (100, 250)
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(changed, isNotNull);
      // nx = (100-0)/400 = 0.25, ny = (250-100)/200 = 0.75
      expect(changed![0].nx, closeTo(0.25, 0.01));
      expect(changed![0].ny, closeTo(0.75, 0.01));
      expect(changed![1], points[1]);
      expect(changed![2], points[2]);
      expect(changed![3], points[3]);
    });

    testWidgets('모든 점에서 32px보다 먼 곳(레터박스)에서 드래그를 시작하면 무시된다', (tester) async {
      List<FramePoint>? changed;
      await tester.pumpWidget(buildOverlay(onChanged: (p) => changed = p));

      // 상단 레터박스(y=50), 가장 가까운 점(120,160)까지도 32px 초과.
      final gesture = await tester.startGesture(const Offset(200, 50));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(changed, isNull);
    });

    testWidgets('드래그는 이미지 표시 영역 밖을 벗어나지 못하도록 clamp된다', (tester) async {
      List<FramePoint>? changed;
      await tester.pumpWidget(buildOverlay(onChanged: (p) => changed = p));

      final gesture = await tester.startGesture(const Offset(80, 260)); // points[0]
      await tester.pump();
      await gesture.moveBy(const Offset(-500, -500)); // 표시 영역 좌상단 밖으로 크게 이동
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(changed, isNotNull);
      expect(changed![0].nx, 0.0);
      expect(changed![0].ny, 0.0);
    });
  });
}
