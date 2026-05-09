import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';

class PinImpactDetectorService {
  static const double _pixelDiffThreshold = 30.0;
  // 50 km/h 기준 18.29m 이동 = 1.3s = 39프레임 → 안전 절반(20프레임)을 release 직후 무시
  static const _minTravelFrames = 20;
  static const double _roiWidthRatio = 0.30;
  static const double _minThreshold = 0.05;
  // 볼 bbox 크기가 release 후 1.5배 이상 커지면 카메라가 핀 뒤편 시나리오
  static const double _cameraBehindPinsBboxGrowth = 1.5;

  ImpactResult findImpact(
    List<img.Image> frames,
    List<BallDetection?> detections,
    int releaseFrame,
  ) {
    if (frames.length < 2) return ImpactResult.notFound;
    if (releaseFrame >= frames.length) return ImpactResult.notFound;

    final searchStart = releaseFrame + _minTravelFrames;
    if (searchStart >= frames.length) return ImpactResult.notFound;

    final roi = _resolveRoi(frames, detections, releaseFrame);

    final ratios = <double>[];
    img.Image? prevZone;

    for (int i = releaseFrame; i < frames.length; i++) {
      final zone = _crop(frames[i], roi);
      final gray = img.grayscale(zone);
      if (prevZone != null) {
        ratios.add(_changeRatio(prevZone, gray));
      }
      prevZone = gray;
    }

    if (ratios.isEmpty) return ImpactResult.notFound;

    final mean = ratios.reduce((a, b) => a + b) / ratios.length;
    final variance =
        ratios.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) /
            ratios.length;
    final stddev = variance > 0 ? math.sqrt(variance) : 0.0;
    final dynamicThreshold = mean + 3 * stddev < _minThreshold
        ? _minThreshold
        : mean + 3 * stddev;

    debugPrint(
        '[PinImpact] roi=$roi, μ=${mean.toStringAsFixed(3)}, σ=${stddev.toStringAsFixed(3)}, threshold=${dynamicThreshold.toStringAsFixed(3)}');

    for (int i = 0; i < ratios.length; i++) {
      final frameIdx = releaseFrame + 1 + i;
      if (frameIdx <= searchStart) continue;
      if (ratios[i] >= dynamicThreshold) {
        debugPrint(
            '[PinImpact] impact=$frameIdx, ratio=${(ratios[i] * 100).toStringAsFixed(1)}%');
        return ImpactResult(
          frame: frameIdx,
          roi: roi,
          confidence: ratios[i].clamp(0.0, 1.0),
        );
      }
    }

    debugPrint('[PinImpact] impact 미감지');
    return ImpactResult.notFound;
  }

  Rect _resolveRoi(
    List<img.Image> frames,
    List<BallDetection?> detections,
    int releaseFrame,
  ) {
    final fw = frames.first.width.toDouble();
    final fh = frames.first.height.toDouble();

    // release 직후 첫 detection + 마지막 detection 비교
    BallDetection? firstAfter;
    BallDetection? last;
    BallDetection? second;
    for (int i = releaseFrame; i < detections.length; i++) {
      final d = detections[i];
      if (d != null) {
        firstAfter = d;
        break;
      }
    }
    for (int i = detections.length - 1; i >= releaseFrame; i--) {
      final d = detections[i];
      if (d == null) continue;
      if (last == null) {
        last = d;
        continue;
      }
      second = d;
      break;
    }

    if (last == null) {
      // fallback: 화면 상단 20%
      return Rect.fromLTWH(0, 0, fw, fh * 0.2);
    }

    // 카메라 시점 자동 판정: bbox 크기 추세
    final bboxGrowth = firstAfter != null && firstAfter.bw > 0
        ? last.bw / firstAfter.bw
        : 1.0;
    final cameraBehindPins = bboxGrowth >= _cameraBehindPinsBboxGrowth;

    final double cx;
    final double cy;
    if (cameraBehindPins) {
      // 카메라가 핀 뒤편: 볼이 카메라로 옴. 임팩트는 last detection 근처
      // (extrapolation 작게: 1배만)
      final dx = second != null ? last.cx - second.cx : 0.0;
      final dy = second != null ? last.cy - second.cy : 0.0;
      cx = last.cx + dx * 1.0;
      cy = last.cy + dy * 1.0;
      debugPrint('[PinImpact] camera-behind-pins (bboxGrowth=${bboxGrowth.toStringAsFixed(2)}x)');
    } else {
      // 카메라가 던지는 사람 뒤편: 볼이 핀(멀리)으로 감. 외삽 5배
      final dx = second != null ? last.cx - second.cx : 0.0;
      final dy = second != null ? last.cy - second.cy : 0.0;
      cx = last.cx + dx * 5;
      cy = last.cy + dy * 5;
      debugPrint('[PinImpact] camera-behind-thrower (bboxGrowth=${bboxGrowth.toStringAsFixed(2)}x)');
    }

    // ROI 크기: 마지막 bbox의 4배 또는 영상 폭 30% 중 큰 값
    final dynamicW = math.max(fw * _roiWidthRatio, last.bw * fw * 4);
    final dynamicH = math.max(fh * _roiWidthRatio, last.bh * fh * 4);
    final left = (cx * fw - dynamicW / 2).clamp(0.0, fw - 1);
    final top = (cy * fh - dynamicH / 2).clamp(0.0, fh - 1);
    final width = dynamicW.clamp(1.0, fw - left);
    final height = dynamicH.clamp(1.0, fh - top);
    return Rect.fromLTWH(left, top, width, height);
  }

  img.Image _crop(img.Image src, Rect roi) {
    final x = roi.left.round().clamp(0, src.width - 1);
    final y = roi.top.round().clamp(0, src.height - 1);
    final w = roi.width.round().clamp(1, src.width - x);
    final h = roi.height.round().clamp(1, src.height - y);
    return img.copyCrop(src, x: x, y: y, width: w, height: h);
  }

  double _changeRatio(img.Image prev, img.Image curr) {
    final w = curr.width < prev.width ? curr.width : prev.width;
    final h = curr.height < prev.height ? curr.height : prev.height;
    final total = w * h;
    if (total == 0) return 0;
    int changed = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final diff =
            (img.getLuminance(curr.getPixel(x, y)) - img.getLuminance(prev.getPixel(x, y)))
                .abs();
        if (diff > _pixelDiffThreshold) changed++;
      }
    }
    return changed / total;
  }

}
