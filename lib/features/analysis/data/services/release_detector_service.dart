import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';

class ReleaseDetectorService {
  static const _windowSize = 5;
  static const _minConsecutive = 2;
  static const double _absSpeedFloor = 0.015;
  static const double _peakRatio = 0.35;
  static const double _backswingDetectRatio = 1.4;

  ReleaseResult findRelease(
    List<BallDetection?> detections, {
    HomographyMatrix? homography,
  }) {
    final velocities = _smoothedVelocities(detections);
    if (velocities.length < _minConsecutive + 1) {
      return ReleaseResult.notFound;
    }

    final peakV = velocities.reduce((a, b) => a > b ? a : b);
    if (peakV < _absSpeedFloor) {
      return ReleaseResult.notFound;
    }

    final threshold = (peakV * _peakRatio).clamp(_absSpeedFloor, 1.0);

    final backswingPeakFrame = _findBackswingPeak(detections);
    final minStart = (velocities.length * 0.25).round().clamp(1, velocities.length);
    final rawStart = backswingPeakFrame ?? 1;
    final searchStart =
        rawStart >= minStart ? rawStart.clamp(1, velocities.length) : minStart;

    final segments = <(int start, int len)>[];
    int consecutive = 0;
    int? startFrame;

    void closeSegment() {
      if (consecutive >= _minConsecutive && startFrame != null) {
        segments.add((startFrame!, consecutive));
      }
      consecutive = 0;
      startFrame = null;
    }

    for (int i = searchStart; i < velocities.length; i++) {
      final v = velocities[i];
      final a = v - velocities[i - 1];
      final ok = v >= threshold && a >= 0;
      if (ok) {
        consecutive++;
        if (consecutive == 1) startFrame = i;
      } else {
        closeSegment();
      }
    }
    closeSegment();

    if (segments.isEmpty) {
      return ReleaseResult.notFound;
    }

    int? bestStart;
    int bestLen = 0;
    double bestScore = double.negativeInfinity;
    for (final seg in segments) {
      final shrinkScore = _postReleaseBboxShrinkScore(detections, seg.$1);
      final laneFwdScore =
          homography != null ? _laneForwardScore(detections, homography, seg.$1) : 0.0;
      final score = seg.$2.toDouble() + shrinkScore * 5 + laneFwdScore * 5;
      if (score > bestScore) {
        bestScore = score;
        bestStart = seg.$1;
        bestLen = seg.$2;
      }
    }

    // 제대로 트리밍된 클립이라면 release는 후반 25%(flight/impact/settle 구간)에
    // 올 수 없다 — 이 범위에서 검출됐다면 다른 원인의 오검출일 가능성이 높으므로
    // 조용히 틀린 프레임을 반환하는 대신 notFound로 실패를 명시한다.
    if (bestStart! > (detections.length * 0.75).round()) {
      return ReleaseResult.notFound;
    }

    final confidence = (bestLen / _windowSize).clamp(0.0, 1.0);
    debugPrint('[ReleaseDetector] release=$bestStart, conf=$confidence');
    return ReleaseResult(frame: bestStart, confidence: confidence);
  }

  double _laneForwardScore(List<BallDetection?> detections, HomographyMatrix h, int startFrame) {
    final ys = <double>[];
    for (var i = startFrame; i < startFrame + 10 && i < detections.length; i++) {
      final d = detections[i];
      if (d == null) continue;
      ys.add(h.frameToLane(FramePoint(nx: d.cx, ny: d.cy)).yM);
    }
    if (ys.length < 3) return 0.0;
    var inc = 0;
    var total = 0;
    for (var i = 1; i < ys.length; i++) {
      if (ys[i] > ys[i - 1]) inc++;
      total++;
    }
    return (inc / total) * 2 - 1;
  }

  double _postReleaseBboxShrinkScore(List<BallDetection?> detections, int startFrame) {
    double avgArea(int from, int to) {
      double sum = 0;
      int count = 0;
      for (int i = from; i < to && i < detections.length; i++) {
        if (i < 0) continue;
        final d = detections[i];
        if (d == null) continue;
        sum += d.bw * d.bh;
        count++;
      }
      return count > 0 ? sum / count : 0;
    }

    final pre = avgArea(startFrame - 5, startFrame);
    final post = avgArea(startFrame, startFrame + 10);
    if (pre <= 0 || post <= 0) return 0;
    final ratio = (pre - post) / pre;
    return ratio.clamp(-1.0, 1.0);
  }

  int? _findBackswingPeak(List<BallDetection?> detections) {
    // 백스윙 피크는 항상 클립 전반부에서만 발생한다. 실기기 로그에서
    // 임팩트 이후 파편/모션블러로 인한 스퓨리어스 대형 bbox가 후반부에
    // 잡혀 전체 스캔 시 이를 피크로 오검출, release 탐색을 통째로
    // 건너뛰게 만드는 사례가 확인되어 스캔 범위를 전반 50%로 제한한다.
    final scanEnd = (detections.length * 0.5).round();
    final areas = <(int, double)>[];
    for (int i = 0; i < scanEnd; i++) {
      final d = detections[i];
      if (d == null) continue;
      areas.add((i, d.bw * d.bh));
    }
    if (areas.length < 5) return null;
    final maxArea = areas.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
    final minArea = areas.map((e) => e.$2).reduce((a, b) => a < b ? a : b);
    if (minArea <= 0 || maxArea / minArea < _backswingDetectRatio) {
      return null;
    }
    final peakEntry = areas.firstWhere((e) => e.$2 == maxArea);
    return peakEntry.$1;
  }

  List<double> _smoothedVelocities(List<BallDetection?> detections) {
    final raw = <double>[0.0];
    for (int i = 1; i < detections.length; i++) {
      final prev = detections[i - 1];
      final curr = detections[i];
      if (prev == null || curr == null) {
        raw.add(0.0);
      } else {
        final dx = curr.cx - prev.cx;
        final dy = curr.cy - prev.cy;
        raw.add(sqrt(dx * dx + dy * dy));
      }
    }
    final smoothed = <double>[];
    for (int i = 0; i < raw.length; i++) {
      final start = (i - _windowSize ~/ 2).clamp(0, raw.length - 1);
      final end = (i + _windowSize ~/ 2 + 1).clamp(0, raw.length);
      double sum = 0;
      for (int j = start; j < end; j++) {
        sum += raw[j];
      }
      smoothed.add(sum / (end - start));
    }
    return smoothed;
  }
}
