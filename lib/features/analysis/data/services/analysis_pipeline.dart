import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/rpm_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/analysis_data.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';

class AnalysisPipeline {
  final VideoFrameExtractorService frameExtractor;
  final BallDetectionService ballDetector;
  final ReleaseDetectorService releaseDetector;
  final HomographyMatrix homography;
  final SpeedEstimatorService speedEstimator;
  final RpmEstimatorService rpmEstimator;

  AnalysisPipeline({
    required this.frameExtractor,
    required this.ballDetector,
    required this.releaseDetector,
    required this.homography,
    required this.speedEstimator,
    required this.rpmEstimator,
  });

  Future<AnalysisData> run(String videoPath, int fpsHint) async {
    final extracted = await frameExtractor.extract(videoPath);
    final frames = extracted.frames;
    if (frames.isEmpty) {
      return AnalysisData(framesAnalyzed: 0, fpsUsed: extracted.sampleFps);
    }

    List<BallDetection?> detections;
    try {
      await ballDetector.init();
      detections = frames.map((f) => ballDetector.detect(f)).toList();
    } catch (e) {
      debugPrint('[Pipeline] YOLO 오류: $e');
      detections = List.filled(frames.length, null);
    } finally {
      ballDetector.dispose();
    }

    // 짧은 gap(≤5프레임) 보간 → velocity 시계열 안정화
    detections = _interpolateDetections(detections);

    final release = releaseDetector.findRelease(detections, homography: homography);

    // release 이후 trajectory linearity 기반 outlier 제거
    if (release.isFound) {
      detections = _filterOutliers(detections, release.frame);
    }
    final speed = speedEstimator.estimate(
      release: release,
      detections: detections,
      homography: homography,
      sampleFps: extracted.sampleFps,
    );

    final rpm = rpmEstimator.estimate(
      frames: frames,
      detections: detections,
      releaseFrame: release.frame,
      sampleFps: extracted.sampleFps,
    );

    // ── FSM 병렬 패스 (Phase 5.2): trajectory/break/aim 산출 ──────────────
    final fsm = AnalysisStateMachine();
    for (var i = 0; i < detections.length; i++) {
      final d = detections[i];
      final lanePos = d != null
          ? homography.frameToLane(FramePoint(nx: d.cx, ny: d.cy))
          : null;
      fsm.onFrame(frameIdx: i, detection: d, lanePos: lanePos);
    }

    LanePoint? releasePosM;
    List<LanePoint> trajectoryLane = const [];
    double? aimAngleDeg;
    LanePoint? breakPosM;

    if (fsm.releaseFrame != null) {
      final relIdx = fsm.releaseFrame!;
      final relDet = relIdx < detections.length ? detections[relIdx] : null;
      if (relDet != null) {
        releasePosM =
            homography.frameToLane(FramePoint(nx: relDet.cx, ny: relDet.cy));
      }
    }

    trajectoryLane = fsm.trajectory.map((e) => e.lane).toList();

    // aimAngleDeg: 릴리즈 직후 0.5m 구간의 레인 y축 기준 진행각
    if (trajectoryLane.length >= 2) {
      final first = trajectoryLane.first;
      LanePoint? second;
      for (final p in trajectoryLane) {
        if (p.yM - first.yM >= 0.5) {
          second = p;
          break;
        }
      }
      second ??= trajectoryLane.last;
      final dx = second.xM - first.xM;
      final dy = second.yM - first.yM;
      if (dy.abs() > 1e-6) {
        // 레인 y축 기준 각도. 오른쪽(+x) 방향이 양수.
        aimAngleDeg = (math.atan2(dx, dy) * 180.0 / math.pi);
      }
    }

    // breakPosM: 직선(first→last)에서 최대 수선 거리 지점 (곡률 > 5cm)
    if (trajectoryLane.length >= 5) {
      final start = trajectoryLane.first;
      final end = trajectoryLane.last;
      final vx = end.xM - start.xM;
      final vy = end.yM - start.yM;
      final segLen = math.sqrt(vx * vx + vy * vy);
      if (segLen > 1.0) {
        var maxDist = 0.0;
        LanePoint? bestPoint;
        for (final p in trajectoryLane) {
          final num1 =
              (vx * (start.yM - p.yM) - (start.xM - p.xM) * vy).abs();
          final dist = num1 / segLen;
          if (dist > maxDist) {
            maxDist = dist;
            bestPoint = p;
          }
        }
        if (maxDist > 0.05 && bestPoint != null) {
          breakPosM = bestPoint;
        }
      }
    }

    return AnalysisData(
      speedKmh: speed.kmh,
      rpmEstimated: rpm.rpm,
      framesAnalyzed: frames.length,
      fpsUsed: extracted.sampleFps,
      speedFailure: speed.failure,
      rpmFailure: rpm.failure,
      speedConfidence: speed.confidence,
      rpmConfidence: rpm.confidence,
      releasePosM: releasePosM,
      breakPosM: breakPosM,
      aimAngleDeg: aimAngleDeg,
      trajectoryLane: trajectoryLane,
    );
  }

  /// null gap ≤ 5프레임이면 양쪽 valid detection 사이를 선형 보간.
  /// 긴 gap은 보간하지 않음 (볼이 실제로 사라진 상태).
  static const _maxInterpolateGap = 5;

  List<BallDetection?> _interpolateDetections(List<BallDetection?> raw) {
    final result = List<BallDetection?>.from(raw);
    int i = 0;
    while (i < result.length) {
      if (result[i] != null) {
        i++;
        continue;
      }
      // null 시작 위치 찾기
      final gapStart = i;
      while (i < result.length && result[i] == null) {
        i++;
      }
      final gapEnd = i; // exclusive, result[gapEnd] = first non-null after gap

      final gapLen = gapEnd - gapStart;
      if (gapLen > _maxInterpolateGap) continue;
      if (gapStart == 0 || gapEnd >= result.length) continue;

      final prev = result[gapStart - 1]!;
      final next = result[gapEnd]!;

      for (int j = gapStart; j < gapEnd; j++) {
        final t = (j - gapStart + 1) / (gapLen + 1);
        result[j] = BallDetection(
          cx: prev.cx + (next.cx - prev.cx) * t,
          cy: prev.cy + (next.cy - prev.cy) * t,
          bw: prev.bw + (next.bw - prev.bw) * t,
          bh: prev.bh + (next.bh - prev.bh) * t,
          confidence: math.min(prev.confidence, next.confidence) * 0.7,
        );
      }
      debugPrint('[Pipeline] 보간 gap=$gapLen (frame $gapStart~${gapEnd - 1})');
    }
    return result;
  }

  /// release 이후 detection trajectory에서 직선 이탈 outlier 제거.
  /// 최소 8개 valid detection이 있어야 linearity 계산. 없으면 그대로 반환.
  static const _linearityWindow = 15;
  static const _outlierThreshold = 0.08; // 정규화 좌표 기준 잔차

  List<BallDetection?> _filterOutliers(
      List<BallDetection?> detections, int releaseFrame) {
    final result = List<BallDetection?>.from(detections);
    final valid = <(int idx, double cx, double cy)>[];

    for (int i = releaseFrame;
        i < detections.length && valid.length < _linearityWindow;
        i++) {
      final d = detections[i];
      if (d != null) valid.add((i, d.cx, d.cy));
    }
    if (valid.length < 8) return result;

    // cx vs frame index 선형회귀
    final n = valid.length.toDouble();
    final sumX = valid.map((e) => e.$1.toDouble()).reduce((a, b) => a + b);
    final sumCx = valid.map((e) => e.$2).reduce((a, b) => a + b);
    final sumX2 =
        valid.map((e) => e.$1 * e.$1.toDouble()).reduce((a, b) => a + b);
    final sumXCx =
        valid.map((e) => e.$1 * e.$2).reduce((a, b) => a + b);
    final slopeX = (n * sumXCx - sumX * sumCx) / (n * sumX2 - sumX * sumX);
    final interceptX = (sumCx - slopeX * sumX) / n;

    // cy vs frame index
    final sumCy = valid.map((e) => e.$3).reduce((a, b) => a + b);
    final sumXCy =
        valid.map((e) => e.$1 * e.$3).reduce((a, b) => a + b);
    final slopeY = (n * sumXCy - sumX * sumCy) / (n * sumX2 - sumX * sumX);
    final interceptY = (sumCy - slopeY * sumX) / n;

    int removed = 0;
    for (int i = releaseFrame; i < result.length; i++) {
      final d = result[i];
      if (d == null) continue;
      final predCx = slopeX * i + interceptX;
      final predCy = slopeY * i + interceptY;
      final residual = math.sqrt(
          math.pow(d.cx - predCx, 2) + math.pow(d.cy - predCy, 2));
      if (residual > _outlierThreshold) {
        result[i] = null;
        removed++;
      }
    }
    if (removed > 0) {
      debugPrint('[Pipeline] trajectory outlier $removed개 제거');
    }
    return result;
  }
}
