import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart';

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/release_result.dart';

class ReleaseDetectorService {
  static const _windowSize = 5;
  static const _minConsecutive = 3;
  // 어프로치 동작은 보통 0.01-0.03, 진짜 release는 0.05+. 이 영역 분리하기 위해
  // peak의 50%를 임계값으로 동적 설정.
  static const double _absSpeedFloor = 0.025;
  static const double _peakRatio = 0.5;
  // 카메라가 사용자 뒤편 시점이면 백스윙에서 bbox가 커짐.
  // bbox max/min ratio가 1.4 이상이면 백스윙 신호 활용 (백스윙 정점 이후만 release 후보).
  static const double _backswingDetectRatio = 1.4;

  ReleaseResult findRelease(List<BallDetection?> detections) {
    final velocities = _smoothedVelocities(detections);
    if (velocities.length < _minConsecutive + 1) {
      debugPrint('[ReleaseDetector] 데이터 부족');
      return ReleaseResult.notFound;
    }

    final peakV = velocities.reduce((a, b) => a > b ? a : b);
    if (peakV < _absSpeedFloor) {
      debugPrint('[ReleaseDetector] 전체 peak 부족: ${peakV.toStringAsFixed(3)}');
      return ReleaseResult.notFound;
    }

    final threshold = (peakV * _peakRatio).clamp(_absSpeedFloor, 1.0);

    // 백스윙 정점 감지: bbox 면적 max 시점 + 그 이후만 release 후보로 제한.
    // 카메라가 측면이거나 변화 작으면 무시 (전체 영상 검색).
    final backswingPeakFrame = _findBackswingPeak(detections);
    // searchStart는 최소 1 (velocities[i-1] 접근 위해)
    final searchStart = (backswingPeakFrame ?? 1).clamp(1, velocities.length);

    // 모든 후보 segment 수집.
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
      debugPrint('[ReleaseDetector] 적합 segment 없음 '
          '(peak=${peakV.toStringAsFixed(3)}, threshold=${threshold.toStringAsFixed(3)}, '
          'searchStart=$searchStart)');
      return ReleaseResult.notFound;
    }

    // 점수 기반 best segment 선택:
    // score = segment 길이 + 후속 bbox 감소 신호(release 직후 forward swing → 카메라 멀어짐)
    int? bestStart;
    int bestLen = 0;
    double bestScore = double.negativeInfinity;
    for (final seg in segments) {
      final shrinkScore = _postReleaseBboxShrinkScore(detections, seg.$1);
      final score = seg.$2.toDouble() + shrinkScore * 5;
      debugPrint('[ReleaseDetector] candidate start=${seg.$1}, len=${seg.$2}, '
          'shrink=${shrinkScore.toStringAsFixed(2)}, score=${score.toStringAsFixed(2)}');
      if (score > bestScore) {
        bestScore = score;
        bestStart = seg.$1;
        bestLen = seg.$2;
      }
    }

    final confidence = (bestLen / _windowSize).clamp(0.0, 1.0);
    debugPrint('[ReleaseDetector] release=$bestStart, conf=$confidence, '
        'peak=${peakV.toStringAsFixed(3)}, threshold=${threshold.toStringAsFixed(3)}, '
        'len=$bestLen, backswingPeak=$backswingPeakFrame');
    return ReleaseResult(frame: bestStart!, confidence: confidence);
  }

  /// release 직후 bbox 면적이 직전 대비 얼마나 감소했는지 [-1, 1] 범위로 반환.
  /// 양수=감소(forward swing), 음수=증가(백스윙 잔여), 0=변화 없음.
  /// 측정 윈도우: pre = startFrame-5 ~ startFrame, post = startFrame ~ startFrame+10
  double _postReleaseBboxShrinkScore(
    List<BallDetection?> detections,
    int startFrame,
  ) {
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

  /// bbox 면적 시계열에서 백스윙 정점(=면적 max) frame 반환.
  /// bbox 변화가 _backswingDetectRatio 미만이면 측면 시점 등으로 간주, null 반환.
  int? _findBackswingPeak(List<BallDetection?> detections) {
    final areas = <(int, double)>[];
    for (int i = 0; i < detections.length; i++) {
      final d = detections[i];
      if (d == null) continue;
      areas.add((i, d.bw * d.bh));
    }
    if (areas.length < 5) return null;

    final maxArea = areas.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
    final minArea = areas.map((e) => e.$2).reduce((a, b) => a < b ? a : b);
    if (minArea <= 0 || maxArea / minArea < _backswingDetectRatio) {
      return null; // 측면 시점 또는 변화 부족
    }
    final peakEntry = areas.firstWhere((e) => e.$2 == maxArea);
    return peakEntry.$1;
  }

  /// 정규화 변위 시퀀스를 5프레임 이동평균 처리하여 반환.
  /// null 또는 null과 인접한 프레임은 변위 0으로 처리.
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
