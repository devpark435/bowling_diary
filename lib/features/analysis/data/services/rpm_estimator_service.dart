import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv.dart' as cv;

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/rpm_result.dart';

/// Lucas-Kanade optical flow 기반 RPM 추정.
///
/// 릴리스 직후 프레임마다 볼 중심 정사각 ROI를 잘라
/// goodFeaturesToTrack + calcOpticalFlowPyrLK로 표면 특징점을 추적.
/// 각 추적 점이 ROI 중심을 기준으로 만든 각도 변화량을 누적해 angular velocity → RPM 산출.
class RpmEstimatorService {
  static const int _roiSize = 128;
  static const int _maxFeatures = 40;
  static const double _qualityLevel = 0.01;
  static const double _minDistance = 5.0;
  static const int _maxAnalyzeFrames = 30;
  static const int _minTrackedFrames = 5;
  static const int _minFeatures = 6;
  static const int _minRpm = 100;
  static const int _maxRpm = 600;
  // LK 추적 실패로 간주할 한 프레임 내 변위 한계 (픽셀)
  static const double _maxFeatureDisplacement = 30.0;
  // 각도 변화 안정성 컷오프: 표준편차/|평균| 비율
  static const double _maxAngleCoefVariation = 1.5;

  RpmResult estimate({
    required List<img.Image> frames,
    required List<BallDetection?> detections,
    required int releaseFrame,
    required int sampleFps,
  }) {
    if (frames.isEmpty || sampleFps <= 0) {
      return RpmResult.failed(RpmFailure.featureDetectionFailed);
    }
    if (releaseFrame < 0 || releaseFrame >= frames.length) {
      return RpmResult.failed(RpmFailure.featureDetectionFailed);
    }

    final crops = <cv.Mat>[];
    try {
      for (int i = releaseFrame; i < frames.length; i++) {
        if (i >= detections.length) break;
        final det = detections[i];
        if (det == null) continue;
        final crop = _cropBallToMat(frames[i], det);
        if (crop == null) continue;
        crops.add(crop);
        if (crops.length >= _maxAnalyzeFrames) break;
      }

      if (crops.length < _minTrackedFrames + 1) {
        debugPrint('[RpmEstimator] crop 부족: ${crops.length}');
        return RpmResult.failed(RpmFailure.featureDetectionFailed);
      }

      var prevPts = cv.goodFeaturesToTrack(
        crops[0], _maxFeatures, _qualityLevel, _minDistance,
      );

      if (prevPts.length < _minFeatures) {
        debugPrint('[RpmEstimator] 특징점 부족: ${prevPts.length}');
        prevPts.dispose();
        return RpmResult.failed(RpmFailure.featureDetectionFailed);
      }

      final angleDeltas = <double>[];
      const center = _roiSize / 2.0;
      int redetectCount = 0;

      for (int i = 1; i < crops.length; i++) {
        final result = cv.calcOpticalFlowPyrLK(
          crops[i - 1], crops[i], prevPts, cv.VecPoint2f(),
        );
        final nextPts = result.$1;
        final status = result.$2;

        final perFrameDeltas = <double>[];
        final tracked = <cv.Point2f>[];

        for (int p = 0; p < prevPts.length && p < nextPts.length; p++) {
          if (status != null && p < status.length && status[p] == 0) continue;
          final pp = prevPts[p];
          final np = nextPts[p];
          final dx = np.x - pp.x;
          final dy = np.y - pp.y;
          if (dx * dx + dy * dy >
              _maxFeatureDisplacement * _maxFeatureDisplacement) {
            continue;
          }
          final prevAngle = math.atan2(pp.y - center, pp.x - center);
          final currAngle = math.atan2(np.y - center, np.x - center);
          var delta = currAngle - prevAngle;
          while (delta > math.pi) {
            delta -= 2 * math.pi;
          }
          while (delta < -math.pi) {
            delta += 2 * math.pi;
          }
          perFrameDeltas.add(delta);
          tracked.add(cv.Point2f(np.x, np.y));
        }

        prevPts.dispose();
        nextPts.dispose();
        status?.dispose();
        result.$3?.dispose();

        if (perFrameDeltas.length < _minFeatures ~/ 2) {
          // 추적 손실 → 새 특징점 검출 (최대 3회 재시도)
          prevPts = cv.goodFeaturesToTrack(
            crops[i], _maxFeatures, _qualityLevel, _minDistance,
          );
          redetectCount++;
          if (prevPts.length < _minFeatures || redetectCount > 3) {
            prevPts.dispose();
            return RpmResult.failed(RpmFailure.trackingLost);
          }
          continue;
        }

        perFrameDeltas.sort();
        angleDeltas.add(perFrameDeltas[perFrameDeltas.length ~/ 2]);

        prevPts = cv.VecPoint2f.fromList(tracked);
      }

      prevPts.dispose();

      if (angleDeltas.length < _minTrackedFrames) {
        debugPrint('[RpmEstimator] 추적 프레임 부족: ${angleDeltas.length}');
        return RpmResult.failed(RpmFailure.trackingLost);
      }

      final avgAbsDelta =
          angleDeltas.map((d) => d.abs()).reduce((a, b) => a + b) /
              angleDeltas.length;
      final radPerSec = avgAbsDelta * sampleFps;
      final rps = radPerSec / (2 * math.pi);
      final rpm = (rps * 60).round();

      debugPrint('[RpmEstimator] frames=${angleDeltas.length}, '
          'avgΔ=${avgAbsDelta.toStringAsFixed(3)}rad, RPM=$rpm');

      if (rpm < _minRpm || rpm > _maxRpm) {
        return RpmResult.failed(RpmFailure.outOfRange);
      }

      final confidence = _calcConfidence(angleDeltas);
      if (confidence < 0.2) {
        return RpmResult.failed(RpmFailure.inconsistentRotation);
      }

      return RpmResult.success(rpm, confidence);
    } catch (e, st) {
      debugPrint('[RpmEstimator] 예외: $e\n$st');
      return RpmResult.failed(RpmFailure.featureDetectionFailed);
    } finally {
      for (final m in crops) {
        try {
          m.dispose();
        } catch (_) {}
      }
    }
  }

  cv.Mat? _cropBallToMat(img.Image frame, BallDetection det) {
    final fw = frame.width.toDouble();
    final fh = frame.height.toDouble();
    final bw = (det.bw * fw).round();
    final bh = (det.bh * fh).round();
    var size = math.max(bw, bh);
    size = size.clamp(20, math.min(frame.width, frame.height));
    final cx = (det.cx * fw).round();
    final cy = (det.cy * fh).round();
    final x = (cx - size ~/ 2).clamp(0, frame.width - size);
    final y = (cy - size ~/ 2).clamp(0, frame.height - size);

    final cropped = img.copyCrop(frame, x: x, y: y, width: size, height: size);
    final resized = img.copyResize(cropped, width: _roiSize, height: _roiSize);

    final bytes = List<int>.filled(_roiSize * _roiSize, 0);
    for (int yy = 0; yy < _roiSize; yy++) {
      for (int xx = 0; xx < _roiSize; xx++) {
        bytes[yy * _roiSize + xx] =
            img.getLuminance(resized.getPixel(xx, yy)).toInt();
      }
    }

    return cv.Mat.fromList(_roiSize, _roiSize, cv.MatType.CV_8UC1, bytes);
  }

  double _calcConfidence(List<double> deltas) {
    final absMean =
        deltas.map((d) => d.abs()).reduce((a, b) => a + b) / deltas.length;
    if (absMean == 0) return 0.0;

    final mean = deltas.reduce((a, b) => a + b) / deltas.length;
    final variance =
        deltas.fold<double>(0, (acc, d) => acc + (d - mean) * (d - mean)) /
            deltas.length;
    final std = math.sqrt(variance);
    final coefVar = std / absMean;
    final stability =
        (1.0 - (coefVar / _maxAngleCoefVariation)).clamp(0.0, 1.0);
    final coverage =
        (deltas.length / _maxAnalyzeFrames).clamp(0.0, 1.0);
    return (stability * 0.65 + coverage * 0.35).clamp(0.0, 1.0);
  }
}
