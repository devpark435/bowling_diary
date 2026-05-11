import 'dart:io' show Platform;

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
  final Stopwatch _detectStopwatch = Stopwatch();
  double _totalDetectMs = 0;

  /// iOS Metal delegate 생성
  GpuDelegate _gpuDelegateIOS() {
    return GpuDelegate(
      options: GpuDelegateOptions(
        allowPrecisionLoss: true,
        // TFLGpuDelegateWaitTypePassive = 0 (bindings 비공개 상수)
        waitType: 0,
      ),
    );
  }

  /// Android GPU delegate V2 생성
  GpuDelegateV2 _gpuDelegateAndroid() {
    return GpuDelegateV2(
      options: GpuDelegateOptionsV2(
        isPrecisionLossAllowed: true,
        // TFLITE_GPU_INFERENCE_PREFERENCE_FAST_SINGLE_ANSWER = 0
        inferencePreference: 0,
        // TFLITE_GPU_INFERENCE_PRIORITY_MIN_LATENCY = 2
        inferencePriority1: 2,
        // TFLITE_GPU_INFERENCE_PRIORITY_AUTO = 0
        inferencePriority2: 0,
        inferencePriority3: 0,
      ),
    );
  }

  Future<void> init() async {
    final stopwatch = Stopwatch()..start();
    try {
      final options = InterpreterOptions();
      if (Platform.isIOS) {
        options.addDelegate(_gpuDelegateIOS());
      } else if (Platform.isAndroid) {
        options.addDelegate(_gpuDelegateAndroid());
      } else {
        options.threads = 2;
      }
      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);
      debugPrint('[BallDetection] GPU delegate 로드 (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      debugPrint('[BallDetection] GPU 실패, CPU fallback: $e');
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);
      debugPrint('[BallDetection] CPU 로드 (${stopwatch.elapsedMilliseconds}ms)');
    }
    final inShape = _interpreter!.getInputTensor(0).shape;
    final outShape = _interpreter!.getOutputTensor(0).shape;
    debugPrint('[BallDetection] 입력: $inShape | 출력: $outShape');
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _frameCount = 0;
    _totalDetectMs = 0;
    _detectStopwatch.reset();
  }

  BallDetection? detect(img.Image frame) {
    if (_interpreter == null) return null;

    _detectStopwatch.reset();
    _detectStopwatch.start();

    final resized = img.copyResize(frame, width: _inputSize, height: _inputSize);
    final input = _toFloat32Input(resized);

    final output = List.generate(
      1,
      (_) => List.generate(_numDims, (_) => List.filled(_numAnchors, 0.0)),
    );

    _interpreter!.run(input, output);
    _frameCount++;

    _detectStopwatch.stop();
    if (_frameCount <= 10) {
      _totalDetectMs += _detectStopwatch.elapsedMicroseconds / 1000.0;
      if (_frameCount == 10) {
        debugPrint('[BallDetection] 평균 추론: ${(_totalDetectMs / 10).toStringAsFixed(1)}ms/frame');
      }
    }

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

