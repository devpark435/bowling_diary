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
  static const double _roiWidthRatio = 0.25;
  static const double _minThreshold = 0.05;

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

    // YOLO 마지막 유효 detection 위치 + 직전 방향벡터 → ROI
    final searchEnd = frames.length;
    BallDetection? last;
    BallDetection? second;
    for (int i = searchEnd - 1; i >= releaseFrame; i--) {
      final d = i < detections.length ? detections[i] : null;
      if (d == null) continue;
      if (last == null) {
        last = d;
        continue;
      }
      second = d;
      break;
    }

    if (last != null) {
      final dx = second != null ? last.cx - second.cx : 0.0;
      final dy = second != null ? last.cy - second.cy : 0.0;
      final extX = last.cx + dx * 5;
      final extY = last.cy + dy * 5;
      final roiW = fw * _roiWidthRatio;
      final roiH = fh * _roiWidthRatio;
      final left = (extX * fw - roiW / 2).clamp(0.0, fw - 1);
      final top = (extY * fh - roiH / 2).clamp(0.0, fh - 1);
      final width = roiW.clamp(1.0, fw - left);
      final height = roiH.clamp(1.0, fh - top);
      return Rect.fromLTWH(left, top, width, height);
    }

    // fallback: 화면 상단 20% (현행 동작)
    return Rect.fromLTWH(0, 0, fw, fh * 0.2);
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
