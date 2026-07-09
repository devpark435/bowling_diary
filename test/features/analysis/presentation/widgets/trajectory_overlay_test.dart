import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/trajectory_overlay.dart';

/// TrajectoryOverlay 서브트리 안의 CustomPaint만 찾는다. Scaffold/Material이
/// 자체적으로 CustomPaint를 그리므로 find.byType(CustomPaint)를 트리 전체에
/// 쓰면 오탐(false positive)이 난다.
Finder _paintersUnderOverlay() => find.descendant(
      of: find.byType(TrajectoryOverlay),
      matching: find.byType(CustomPaint),
    );

VideoPlayerValue _valueAt(
  Duration position, {
  Duration duration = const Duration(seconds: 10),
  bool isPlaying = false,
}) {
  return VideoPlayerValue(
    duration: duration,
    position: position,
    isPlaying: isPlaying,
  );
}

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

  group('frameForPosition', () {
    test('position 0 → frame 0', () {
      expect(frameForPosition(Duration.zero, 30), 0);
    });

    test('정확히 프레임 경계 → 해당 프레임 (내림 경계값)', () {
      // 30fps에서 1프레임 = 33333.33...us. 1초 = 정확히 프레임 30.
      expect(frameForPosition(const Duration(seconds: 1), 30), 30);
    });

    test('프레임 경계 살짝 못 미침 → 내림으로 이전 프레임', () {
      // 30fps에서 frame 1 경계는 33333.33us. 33333us는 아직 frame 0.
      expect(frameForPosition(const Duration(microseconds: 33333), 30), 0);
    });

    test('fps가 클수록 같은 position에 대해 더 큰 프레임 번호', () {
      expect(frameForPosition(const Duration(milliseconds: 500), 60), 30);
      expect(frameForPosition(const Duration(milliseconds: 500), 30), 15);
    });
  });

  group('visiblePointCount', () {
    const points = [
      TrajectoryFramePoint(frame: 10, point: FramePoint(nx: 0.1, ny: 0.1)),
      TrajectoryFramePoint(frame: 20, point: FramePoint(nx: 0.2, ny: 0.2)),
      TrajectoryFramePoint(frame: 30, point: FramePoint(nx: 0.3, ny: 0.3)),
    ];

    test('빈 리스트 → 0', () {
      expect(visiblePointCount(const [], 100), 0);
    });

    test('전부 미래 프레임(currentFrame이 첫 점보다 작음) → 0', () {
      expect(visiblePointCount(points, 5), 0);
    });

    test('전부 과거 프레임(currentFrame이 마지막 점 이상) → 전체 길이', () {
      expect(visiblePointCount(points, 100), 3);
    });

    test('중간 프레임 → 그 프레임까지만 카운트', () {
      expect(visiblePointCount(points, 20), 2);
    });

    test('정확히 첫 점의 frame과 일치 → 1개 포함', () {
      expect(visiblePointCount(points, 10), 1);
    });

    test('첫 점 바로 못 미침 → 0', () {
      expect(visiblePointCount(points, 9), 0);
    });
  });

  group('TrajectoryOverlay 렌더링', () {
    // fps=10 기준: frame 5 → 500ms, frame 15 → 1500ms, frame 20 → 2000ms.
    const points = [
      TrajectoryFramePoint(frame: 5, point: FramePoint(nx: 0.5, ny: 0.9)),
      TrajectoryFramePoint(frame: 15, point: FramePoint(nx: 0.5, ny: 0.5)),
      TrajectoryFramePoint(frame: 20, point: FramePoint(nx: 0.5, ny: 0.1)),
    ];

    testWidgets('재생 전(position=0, currentFrame < 첫 점) → 아무것도 그리지 않는다', (tester) async {
      final playback = ValueNotifier<VideoPlayerValue>(_valueAt(Duration.zero));
      addTearDown(playback.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: TrajectoryOverlay(
                points: points,
                videoSize: const Size(800, 800),
                playback: playback,
                fps: 10,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TrajectoryOverlay), findsOneWidget);
      expect(_paintersUnderOverlay(), findsNothing);
    });

    testWidgets('중간 위치(position이 두 번째 점 프레임) → 일부만 그려진다', (tester) async {
      // frame 15 = 1500ms → 첫 두 점(frame 5, 15)까지 보여야 함, 2개 이상이라 렌더됨.
      final playback = ValueNotifier<VideoPlayerValue>(
        _valueAt(const Duration(milliseconds: 1500)),
      );
      addTearDown(playback.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: TrajectoryOverlay(
                points: points,
                videoSize: const Size(800, 800),
                playback: playback,
                fps: 10,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(_paintersUnderOverlay(), findsWidgets);
    });

    testWidgets('끝 위치(position=duration) → 전체가 그려진다', (tester) async {
      final playback = ValueNotifier<VideoPlayerValue>(
        _valueAt(const Duration(seconds: 10)),
      );
      addTearDown(playback.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: TrajectoryOverlay(
                points: points,
                videoSize: const Size(800, 800),
                playback: playback,
                fps: 10,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(_paintersUnderOverlay(), findsWidgets);
    });

    testWidgets('notifier 값 갱신 후 pump → visibleCount 증가가 반영된다(SizedBox.shrink → CustomPaint)',
        (tester) async {
      // isPlaying: false로 두고 position만 갱신 — ticker 보간이 비활성이라 결정적.
      final playback = ValueNotifier<VideoPlayerValue>(_valueAt(Duration.zero));
      addTearDown(playback.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: TrajectoryOverlay(
                points: points,
                videoSize: const Size(800, 800),
                playback: playback,
                fps: 10,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(_paintersUnderOverlay(), findsNothing);

      // frame 15(1500ms)로 이동 → 첫 두 점이 보여야 하므로 렌더된다.
      playback.value = _valueAt(const Duration(milliseconds: 1500));
      await tester.pump();

      expect(_paintersUnderOverlay(), findsWidgets);
    });

    testWidgets('위젯 dispose가 에러 없이 정상 동작한다', (tester) async {
      final playback = ValueNotifier<VideoPlayerValue>(
        _valueAt(const Duration(seconds: 10)),
      );
      addTearDown(playback.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: TrajectoryOverlay(
                points: points,
                videoSize: const Size(800, 800),
                playback: playback,
                fps: 10,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 위젯 트리를 비워 dispose를 유도 — 예외 없이 통과하면 성공.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
