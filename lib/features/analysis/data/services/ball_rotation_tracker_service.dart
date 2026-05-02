import 'dart:math' show atan2, min, pi;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'ball_detection_service.dart';

class BallRotationTrackerService {
  static const _maxFrames = 60;
  static const _minSuccessFrames = 5;
  static const double _holeDarknessThreshold = 80.0;
  static const _minHoleAreaRatio = 0.003;
  static const _maxHoleAreaRatio = 0.08;
  static const _gridDivisions = 8;

  int? trackRpm(
    List<img.Image> frames,
    List<BallDetection?> detections,
    int releaseFrame,
    int fps,
  ) {
    if (frames.isEmpty || detections.isEmpty) return null;

    // angleDeltas 최대 = limit - 1 이므로 최소 _minSuccessFrames 개 delta 확보에 limit+1 필요
    final limit = min(_maxFrames, frames.length - releaseFrame);
    if (limit < _minSuccessFrames + 1) return null;

    final angleDeltas = <double>[];
    _HoleGroup? prevHoles;

    for (int i = 0; i < limit; i++) {
      final frameIdx = releaseFrame + i;
      if (frameIdx >= frames.length || frameIdx >= detections.length) break;

      final det = detections[frameIdx];
      if (det == null) {
        prevHoles = null;
        continue;
      }

      final crop = _cropBall(frames[frameIdx], det);
      if (crop == null) {
        prevHoles = null;
        continue;
      }

      final holes = _findHoleGroup(crop);
      if (holes == null) {
        prevHoles = null;
        continue;
      }

      if (prevHoles != null) {
        final delta = _angleDelta(prevHoles, holes);
        if (delta != null) angleDeltas.add(delta);
      }
      prevHoles = holes;
    }

    if (angleDeltas.length < _minSuccessFrames) return null;

    final totalAngle = angleDeltas.fold(0.0, (sum, d) => sum + d.abs());
    final durationSec = (angleDeltas.length + 1) / fps.toDouble();
    final rotationsPerSec = (totalAngle / (2 * pi)) / durationSec;
    final rpm = (rotationsPerSec * 60).round();

    debugPrint('[BallRotation] totalAngle=${totalAngle.toStringAsFixed(2)}rad, '
        'frames=${angleDeltas.length}, RPM=$rpm');

    if (rpm < 100 || rpm > 500) return null;
    return rpm;
  }

  img.Image? _cropBall(img.Image frame, BallDetection det) {
    final fw = frame.width.toDouble();
    final fh = frame.height.toDouble();
    const pad = 1.2;
    final bw = (det.bw * fw * pad).round();
    final bh = (det.bh * fh * pad).round();
    final x = ((det.cx * fw) - bw / 2).round().clamp(0, frame.width - 1);
    final y = ((det.cy * fh) - bh / 2).round().clamp(0, frame.height - 1);
    final w = bw.clamp(1, frame.width - x);
    final h = bh.clamp(1, frame.height - y);
    if (w < 10 || h < 10) return null;
    return img.copyCrop(frame, x: x, y: y, width: w, height: h);
  }

  _HoleGroup? _findHoleGroup(img.Image crop) {
    final gray = img.grayscale(crop);
    final w = gray.width;
    final h = gray.height;
    final gridSize = (w / _gridDivisions).round().clamp(2, 30);
    final ballArea = w * h;

    final spots = <(double, double)>[];

    for (int gy = 0; gy < h - gridSize; gy += gridSize) {
      for (int gx = 0; gx < w - gridSize; gx += gridSize) {
        int darkCount = 0;
        double sumX = 0, sumY = 0;

        for (int py = gy; py < min(gy + gridSize, h); py++) {
          for (int px = gx; px < min(gx + gridSize, w); px++) {
            if (img.getLuminance(gray.getPixel(px, py)) < _holeDarknessThreshold) {
              darkCount++;
              sumX += px;
              sumY += py;
            }
          }
        }

        final cellArea = gridSize * gridSize;
        final darkRatio = darkCount / cellArea;
        final spotArea = darkCount / ballArea;

        if (darkRatio > 0.35 && spotArea >= _minHoleAreaRatio && spotArea <= _maxHoleAreaRatio) {
          spots.add((sumX / darkCount - w / 2, sumY / darkCount - h / 2));
        }
      }
    }

    if (spots.isEmpty) return null;
    final cx = spots.map((s) => s.$1).reduce((a, b) => a + b) / spots.length;
    final cy = spots.map((s) => s.$2).reduce((a, b) => a + b) / spots.length;
    return _HoleGroup(cx, cy);
  }

  double? _angleDelta(_HoleGroup prev, _HoleGroup curr) {
    if (prev.cx == 0 && prev.cy == 0) return null;
    if (curr.cx == 0 && curr.cy == 0) return null;
    final prevAngle = atan2(prev.cy, prev.cx);
    final currAngle = atan2(curr.cy, curr.cx);
    var delta = currAngle - prevAngle;
    while (delta > pi) { delta -= 2 * pi; }
    while (delta < -pi) { delta += 2 * pi; }
    return delta;
  }
}

class _HoleGroup {
  final double cx;
  final double cy;
  const _HoleGroup(this.cx, this.cy);
}
