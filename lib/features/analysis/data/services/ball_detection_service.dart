import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class BallDetection {
  final double cx;
  final double cy;
  final double bw;
  final double bh;
  final double confidence;
  const BallDetection({
    required this.cx,
    required this.cy,
    required this.bw,
    required this.bh,
    required this.confidence,
  });
}

class BallDetectionService {
  static const _modelPath = 'assets/models/yolov8n.tflite';
  static const _inputSize = 320;
  static const _confidenceThreshold = 0.3;
  // 커스텀 모델: 클래스 1개 → 출력 [1, 5, 2100] (4bbox + 1class)
  static const _numDims = 5;
  static const _numAnchors = 2100;

  Interpreter? _interpreter;
  int _frameCount = 0;

  Future<void> init() async {
    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(_modelPath, options: options);
    final inShape = _interpreter!.getInputTensor(0).shape;
    final outShape = _interpreter!.getOutputTensor(0).shape;
    debugPrint('[BallDetection] 모델 로드 | 입력: $inShape | 출력: $outShape');
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _frameCount = 0;
  }

  BallDetection? detect(img.Image frame) {
    if (_interpreter == null) return null;

    final resized = img.copyResize(frame, width: _inputSize, height: _inputSize);
    final input = _toFloat32Input(resized);

    final output = List.generate(
      1,
      (_) => List.generate(_numDims, (_) => List.filled(_numAnchors, 0.0)),
    );

    _interpreter!.run(input, output);
    _frameCount++;

    return _parseBest(output[0], verbose: _frameCount == 1);
  }

  List<List<List<List<double>>>> _toFloat32Input(img.Image image) {
    return [
      List.generate(_inputSize, (y) =>
        List.generate(_inputSize, (x) {
          final px = image.getPixel(x, y);
          return [px.r / 255.0, px.g / 255.0, px.b / 255.0];
        }),
      )
    ];
  }

  BallDetection? _parseBest(List<List<double>> raw, {bool verbose = false}) {
    double maxConf = _confidenceThreshold;
    BallDetection? best;

    for (int i = 0; i < _numAnchors; i++) {
      final conf = raw[4][i]; // class 0 = bowling ball
      if (conf <= maxConf) continue;
      maxConf = conf;
      best = BallDetection(
        cx: raw[0][i].clamp(0.0, 1.0),
        cy: raw[1][i].clamp(0.0, 1.0),
        bw: raw[2][i].clamp(0.0, 1.0),
        bh: raw[3][i].clamp(0.0, 1.0),
        confidence: conf,
      );
    }

    if (verbose) {
      final globalMax = List.generate(_numAnchors, (i) => raw[4][i]).reduce((a, b) => a > b ? a : b);
      debugPrint('[BallDetection] 볼 최대신뢰도: ${globalMax.toStringAsFixed(3)}');
    }

    return best;
  }
}

class BallTracker {
  static const _laneLength = 18.29;

  static double? calcSpeedKmh(List<BallDetection?> detections, double fps) {
    final detected = detections.asMap().entries.where((e) => e.value != null).toList();

    if (detected.length < 3) {
      debugPrint('[BallTracker] 볼 감지 부족: ${detected.length}프레임');
      return null;
    }

    final releaseFrame = detected.first.key;
    final impactFrame = detected.last.key;
    final elapsed = (impactFrame - releaseFrame) / fps;

    debugPrint('[BallTracker] 프레임 $releaseFrame→$impactFrame, elapsed=${elapsed.toStringAsFixed(2)}s');

    if (elapsed <= 0) return null;
    final rawSpeed = (_laneLength / elapsed) * 3.6;

    if (rawSpeed < 10 || rawSpeed > 50) {
      debugPrint('[BallTracker] 속도 범위 초과(${rawSpeed.toStringAsFixed(1)}km/h) → 측정불가');
      return null;
    }

    debugPrint('[BallTracker] 구속: ${rawSpeed.toStringAsFixed(1)}km/h');
    return double.parse(rawSpeed.toStringAsFixed(1));
  }
}
