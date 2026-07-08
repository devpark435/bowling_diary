import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/calibration_overlay.dart';

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

  group('CalibrationOverlay 탭 처리', () {
    // 이미지 2:1, 컨테이너 400x400 → 표시 영역 (0,100)-(400,300), 상하 100씩 레터박스.
    const containerSize = Size(400, 400);
    const imageSize = Size(1600, 800);

    Widget buildOverlay({
      required List<FramePoint> points,
      required ValueChanged<FramePoint> onTap,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: containerSize.width,
            height: containerSize.height,
            child: CalibrationOverlay(
              points: points,
              onTap: onTap,
              imageSize: imageSize,
            ),
          ),
        ),
      );
    }

    testWidgets('레터박스 영역(상단 여백) 탭은 무시된다', (tester) async {
      FramePoint? tapped;
      await tester.pumpWidget(
        buildOverlay(points: const [], onTap: (p) => tapped = p),
      );

      // 상단 레터박스 영역(y=50) 탭.
      await tester.tapAt(const Offset(200, 50));
      await tester.pump();

      expect(tapped, isNull);
    });

    testWidgets('이미지 표시 영역 내부 탭은 이미지-상대 정규화 좌표로 변환된다', (tester) async {
      FramePoint? tapped;
      await tester.pumpWidget(
        buildOverlay(points: const [], onTap: (p) => tapped = p),
      );

      // 표시 영역 (0,100)-(400,300) 내부 중앙점(200,200) 탭 → nx=0.5, ny=0.5.
      await tester.tapAt(const Offset(200, 200));
      await tester.pump();

      expect(tapped, isNotNull);
      expect(tapped!.nx, closeTo(0.5, 0.001));
      expect(tapped!.ny, closeTo(0.5, 0.001));
    });

    testWidgets('4점이 모두 입력되면 추가 탭은 무시된다', (tester) async {
      FramePoint? tapped;
      final existing = List.generate(4, (_) => const FramePoint(nx: 0.1, ny: 0.1));
      await tester.pumpWidget(
        buildOverlay(points: existing, onTap: (p) => tapped = p),
      );

      await tester.tapAt(const Offset(200, 200));
      await tester.pump();

      expect(tapped, isNull);
    });
  });
}
