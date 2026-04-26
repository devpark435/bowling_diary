import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class AnalysisData {
  final double speedKmh;
  final int? rpmEstimated;
  final int framesAnalyzed;
  final int fpsUsed;

  const AnalysisData({
    required this.speedKmh,
    this.rpmEstimated,
    required this.framesAnalyzed,
    required this.fpsUsed,
  });
}

class VideoAnalysisService {
  static const _laneLength = 18.29; // 미터 (파울라인 → 헤드핀)

  AnalysisData analyze(List<CameraImage> frames, int fps) {
    debugPrint('[Analysis] 분석 시작: ${frames.length}개 프레임, ${fps}fps');

    if (frames.length < 5) {
      debugPrint('[Analysis] 프레임 부족 → 기본값 반환');
      return AnalysisData(speedKmh: 0, framesAnalyzed: frames.length, fpsUsed: fps);
    }

    final positions = <_BallPosition?>[];
    img.Image? prevGray;

    for (int i = 0; i < frames.length; i++) {
      final gray = _toGrayscale(frames[i]);
      if (gray == null) { positions.add(null); continue; }

      if (prevGray != null) {
        final pos = _detectBallByMotion(prevGray, gray);
        positions.add(pos);
      } else {
        positions.add(null);
      }
      prevGray = gray;
    }

    final detected = positions.asMap().entries
        .where((e) => e.value != null)
        .toList();

    if (detected.length < 3) {
      debugPrint('[Analysis] 볼 감지 실패 → 속도 0 반환');
      return AnalysisData(speedKmh: 0, framesAnalyzed: frames.length, fpsUsed: fps);
    }

    final releaseIdx = detected.first.key;
    final impactIdx = detected.last.key;

    // 샘플링 간격(10프레임) 고려한 실제 프레임 수 역산
    final actualFrameCount = (impactIdx - releaseIdx) * 10;
    final elapsedSec = actualFrameCount / fps;

    if (elapsedSec <= 0) {
      return AnalysisData(speedKmh: 0, framesAnalyzed: frames.length, fpsUsed: fps);
    }

    final speedKmh = (_laneLength / elapsedSec) * 3.6;
    debugPrint('[Analysis] 속도: ${speedKmh.toStringAsFixed(1)}km/h (${elapsedSec.toStringAsFixed(2)}초)');

    final rpm = _estimateRpm(detected.map((e) => e.value!).toList(), fps);
    debugPrint('[Analysis] RPM 추정: $rpm');

    return AnalysisData(
      speedKmh: double.parse(speedKmh.toStringAsFixed(1)),
      rpmEstimated: rpm,
      framesAnalyzed: frames.length,
      fpsUsed: fps,
    );
  }

  /// 갤러리 영상 프레임(img.Image) 분석 — sampleFps는 추출 시 사용한 fps
  AnalysisData analyzeImages(
    List<img.Image> frames,
    int originalFps, {
    int sampleFps = 10,
  }) {
    debugPrint('[Analysis] 갤러리 분석 시작: ${frames.length}개 프레임, 원본 ${originalFps}fps, 샘플 ${sampleFps}fps');

    if (frames.length < 5) {
      return AnalysisData(speedKmh: 0, framesAnalyzed: frames.length, fpsUsed: originalFps);
    }

    final positions = <_BallPosition?>[];
    img.Image? prevGray;

    for (final frame in frames) {
      final gray = img.grayscale(frame);
      if (prevGray != null) {
        positions.add(_detectBallByMotion(prevGray, gray));
      } else {
        positions.add(null);
      }
      prevGray = gray;
    }

    final detected = positions.asMap().entries.where((e) => e.value != null).toList();

    if (detected.length < 3) {
      debugPrint('[Analysis] 볼 감지 실패 → 속도 0 반환');
      return AnalysisData(speedKmh: 0, framesAnalyzed: frames.length, fpsUsed: originalFps);
    }

    final releaseIdx = detected.first.key;
    final impactIdx = detected.last.key;
    final sampleInterval = (originalFps / sampleFps).round().clamp(1, 999);
    final actualFrameCount = (impactIdx - releaseIdx) * sampleInterval;
    final elapsedSec = actualFrameCount / originalFps;

    if (elapsedSec <= 0) {
      return AnalysisData(speedKmh: 0, framesAnalyzed: frames.length, fpsUsed: originalFps);
    }

    final speedKmh = (_laneLength / elapsedSec) * 3.6;
    debugPrint('[Analysis] 속도: ${speedKmh.toStringAsFixed(1)}km/h');

    final rpm = _estimateRpm(
      detected.map((e) => e.value!).toList(),
      originalFps,
      sampleInterval: sampleInterval,
    );
    debugPrint('[Analysis] RPM 추정: $rpm');

    return AnalysisData(
      speedKmh: double.parse(speedKmh.toStringAsFixed(1)),
      rpmEstimated: rpm,
      framesAnalyzed: frames.length,
      fpsUsed: originalFps,
    );
  }

  /// CameraImage(YUV420) → 그레이스케일 (Y 채널만 사용)
  img.Image? _toGrayscale(CameraImage frame) {
    try {
      final yPlane = frame.planes[0];
      final w = frame.width;
      final h = frame.height;
      final result = img.Image(width: w, height: h);

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final yVal = yPlane.bytes[y * yPlane.bytesPerRow + x];
          result.setPixelRgb(x, y, yVal, yVal, yVal);
        }
      }
      return result;
    } catch (e) {
      debugPrint('[Analysis] 그레이스케일 변환 실패: $e');
      return null;
    }
  }

  /// 프레임 차분으로 볼 중심 좌표 반환
  _BallPosition? _detectBallByMotion(img.Image prev, img.Image curr) {
    final w = curr.width;
    final h = curr.height;
    final yStart = h ~/ 3;

    int sumX = 0, sumY = 0, count = 0;

    for (int y = yStart; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final prevLum = img.getLuminance(prev.getPixel(x, y));
        final currLum = img.getLuminance(curr.getPixel(x, y));
        if ((currLum - prevLum).abs() > 25) {
          sumX += x;
          sumY += y;
          count++;
        }
      }
    }

    if (count < 200) return null;
    return _BallPosition(sumX / count, sumY / count);
  }

  /// 볼의 X 좌표 진동 주기로 RPM 추정
  int? _estimateRpm(
    List<_BallPosition> positions,
    int fps, {
    int sampleInterval = 10,
  }) {
    if (positions.length < 4) return null;

    int directionChanges = 0;
    double prevDx = 0;

    for (int i = 1; i < positions.length; i++) {
      final dx = positions[i].x - positions[i - 1].x;
      if (prevDx != 0 && dx * prevDx < 0) directionChanges++;
      if (dx.abs() > 1) prevDx = dx;
    }

    final effectiveFps = fps / sampleInterval;
    final durationSec = positions.length / effectiveFps;
    if (durationSec <= 0) return null;

    final rotationsPerSec = directionChanges / 2.0 / durationSec;
    final rpm = (rotationsPerSec * 60).round();

    if (rpm < 100 || rpm > 500) return null;
    return rpm;
  }
}

class _BallPosition {
  final double x;
  final double y;
  const _BallPosition(this.x, this.y);
}
