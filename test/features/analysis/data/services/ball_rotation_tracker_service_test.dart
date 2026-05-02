import 'dart:math' show pi, cos, sin;

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_rotation_tracker_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// 지정 위치에 어두운 원형 홀이 있는 볼 프레임 생성
img.Image _makeBallFrame({
  required int w,
  required int h,
  required List<(int, int)> holes, // (cx, cy) 픽셀 좌표
  int ballLum = 160,
  int holeLum = 20,
  int holeRadius = 5,
}) {
  final frame = img.Image(width: w, height: h);
  img.fill(frame, color: img.ColorRgb8(ballLum, ballLum, ballLum));
  for (final (hx, hy) in holes) {
    for (int dy = -holeRadius; dy <= holeRadius; dy++) {
      for (int dx = -holeRadius; dx <= holeRadius; dx++) {
        if (dx * dx + dy * dy <= holeRadius * holeRadius) {
          final px = (hx + dx).clamp(0, w - 1);
          final py = (hy + dy).clamp(0, h - 1);
          frame.setPixelRgb(px, py, holeLum, holeLum, holeLum);
        }
      }
    }
  }
  return frame;
}

BallDetection _det(int frameW, int frameH, int ballW, int ballH) => BallDetection(
      cx: 0.5,
      cy: 0.5,
      bw: ballW / frameW,
      bh: ballH / frameH,
      confidence: 0.9,
    );

void main() {
  late BallRotationTrackerService sut;

  setUp(() => sut = BallRotationTrackerService());

  test('프레임 없으면 null', () {
    expect(sut.trackRpm([], [], 0, 30), isNull);
  });

  test('감지 없으면 null', () {
    final frames = List.generate(10, (_) => _makeBallFrame(w: 100, h: 100, holes: [(50, 30)]));
    final dets = List<BallDetection?>.filled(10, null);
    expect(sut.trackRpm(frames, dets, 0, 30), isNull);
  });

  test('릴리즈 후 홀이 보이는 프레임 부족하면 null', () {
    // 5프레임 미만으로 성공 → null
    final frames = List.generate(3, (_) => _makeBallFrame(w: 100, h: 100, holes: [(50, 30)]));
    final det = _det(100, 100, 60, 60);
    final dets = List<BallDetection?>.filled(3, det);
    expect(sut.trackRpm(frames, dets, 0, 30), isNull);
  });

  test('홀 회전 감지로 RPM 범위 내 값 반환', () {
    // 30fps에서 300RPM = 5rev/s = 10도/frame (360도/30frame/rev * 5rev)
    const fps = 30;
    const targetRpm = 300;
    const revPerSec = targetRpm / 60.0;
    const radPerFrame = 2 * pi * revPerSec / fps;

    const frameW = 120;
    const frameH = 120;
    const ballW = 80;
    const ballH = 80;
    const holeRadius = 6;
    const holeDist = 20.0; // 홀 ~ 볼 중심 거리 (픽셀)

    final frames = <img.Image>[];
    for (int i = 0; i < 10; i++) {
      final angle = radPerFrame * i;
      final hx = (frameW / 2 + holeDist * cos(angle)).round();
      final hy = (frameH / 2 + holeDist * sin(angle)).round();
      frames.add(_makeBallFrame(
        w: frameW,
        h: frameH,
        holes: [(hx, hy)],
        holeRadius: holeRadius,
      ));
    }
    final det = _det(frameW, frameH, ballW, ballH);
    final dets = List<BallDetection?>.filled(10, det);

    final rpm = sut.trackRpm(frames, dets, 0, fps);
    expect(rpm, isNotNull);
    expect(rpm, greaterThanOrEqualTo(100));
    expect(rpm, lessThanOrEqualTo(500));
  });
}
