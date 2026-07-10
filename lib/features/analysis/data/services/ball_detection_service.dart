import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

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

  /// 공-레인 접점(bbox 바닥 중점)의 프레임 좌표. 호모그래피는 레인 평면 전제라
  /// 공 중심(바닥에서 반지름 ~11cm 위)을 넣으면 평면 밖 점이 실제보다 앞으로
  /// 투영되는 계통 오차가 생긴다(거리에 비례해 증가 — 실측: 궤적 y가 핀덱
  /// 18.29m를 넘는 18.65m까지 관측). 접점은 평면 위의 점이라 바이어스가 없다.
  FramePoint get contactPoint => FramePoint(nx: cx, ny: (cy + bh / 2).clamp(0.0, 1.0));
}

/// letterbox 배치: 원본을 비율 유지로 [dstSize] 안에 맞췄을 때의 스케일 결과
/// 크기와 패딩 오프셋. 순수 함수 — 위젯/인터프리터 없이 단위 테스트 가능.
typedef LetterboxLayout = ({int scaledW, int scaledH, int padX, int padY});

LetterboxLayout computeLetterbox(int srcW, int srcH, int dstSize) {
  final scale = math.min(dstSize / srcW, dstSize / srcH);
  final scaledW = (srcW * scale).round().clamp(1, dstSize);
  final scaledH = (srcH * scale).round().clamp(1, dstSize);
  return (
    scaledW: scaledW,
    scaledH: scaledH,
    padX: (dstSize - scaledW) ~/ 2,
    padY: (dstSize - scaledH) ~/ 2,
  );
}

/// 모델 입력(letterbox 캔버스) 기준 정규화 좌표를 원본 프레임 기준 정규화
/// 좌표로 역매핑한다.
BallDetection unletterbox(BallDetection d, LetterboxLayout lb, int dstSize) {
  return BallDetection(
    cx: ((d.cx * dstSize - lb.padX) / lb.scaledW).clamp(0.0, 1.0),
    cy: ((d.cy * dstSize - lb.padY) / lb.scaledH).clamp(0.0, 1.0),
    bw: (d.bw * dstSize / lb.scaledW).clamp(0.0, 1.0),
    bh: (d.bh * dstSize / lb.scaledH).clamp(0.0, 1.0),
    confidence: d.confidence,
  );
}

class BallDetectionService {
  // YOLO11s @ 640 (COCO 80클래스, ultralytics tflite export — 출력 (1, 84, 8400),
  // 84 = box4 + 클래스점수80, 좌표는 0~1 정규화 xywh). 이전 모델
  // yolov8n.tflite(@320, 1클래스 전용학습, 출력 (1, 5, 2100))은 롤백용으로
  // 애셋에 유지 — 아래 상수 5개를 (yolov8n, 320, 5, 2100, 무시)로 되돌리면 복귀.
  // 교체 이유: far-lane에서 공이 3~5px로 뭉개지는 320 입력의 localization
  // 지터(정제 드롭률 58%, 회귀 R² 0.67 실측)를 640 입력 + s급 모델로 개선 실험.
  static const _modelPath = 'assets/models/yolo11s.tflite';
  static const _inputSize = 640;
  static const _confidenceThreshold = 0.3;
  static const _numDims = 84;
  static const _numAnchors = 8400;

  /// COCO 클래스 인덱스 32 = sports ball. 1클래스 모델(_numDims == 5)에서는
  /// 사용되지 않는다(_parseBest 참조).
  static const _ballClassIndex = 32;

  /// yolo11s는 신형 litert 변환기 산출물이라 torch 채널-우선(NCHW
  /// [1,3,640,640]) 입력을 요구한다 — NHWC로 넣으면 CONV_2D가 준비 단계에서
  /// 실패(input_channel % filter_input_channel != 0, 실기기 확인). 구형 tf 경유
  /// export(yolov8n)는 NHWC [1,320,320,3] — 롤백 시 false로 되돌릴 것.
  static const _inputChannelFirst = true;

  Interpreter? _interpreter;

  GpuDelegate _gpuDelegateIOS() {
    return GpuDelegate(
      options: GpuDelegateOptions(allowPrecisionLoss: true, waitType: 0),
    );
  }

  GpuDelegateV2 _gpuDelegateAndroid() {
    return GpuDelegateV2(
      options: GpuDelegateOptionsV2(
        isPrecisionLossAllowed: true,
        inferencePreference: 0,
        inferencePriority1: 2,
        inferencePriority2: 0,
        inferencePriority3: 0,
      ),
    );
  }

  Future<void> init() async {
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
    } catch (e) {
      debugPrint('[BallDetection] GPU 실패, CPU fallback: $e');
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);
    }
    // 모델 교체 시 출력 레이아웃 가정(_numDims x _numAnchors)이 맞는지
    // 실기기 로그로 즉시 검증하기 위한 1회성 진단.
    debugPrint('[BallDetection] 모델 로드: $_modelPath, '
        '입력 shape ${_interpreter!.getInputTensor(0).shape} '
        '(채널우선=$_inputChannelFirst), '
        '출력 shape ${_interpreter!.getOutputTensor(0).shape} '
        '(기대: [1, $_numDims, $_numAnchors])');
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  /// 진단용 — 임계값 미달 포함, 전 detect() 호출에서 관측된 최고 신뢰도.
  /// "검출 0건"이 (a) 추론 자체가 깨져 점수가 ~0인지 (b) 실제 점수가 임계값
  /// 바로 아래(전처리/클래스 문제)인지 구분하는 데 쓴다.
  double debugMaxScore = 0;

  BallDetection? detect(img.Image frame) {
    if (_interpreter == null) return null;

    // letterbox: ultralytics 학습 전처리와 동일하게 비율 유지 + 회색 패딩.
    // 스쿼시 리사이즈(비율 무시)는 480x853 포트레이트에서 공을 타원으로
    // 찌그러뜨려 범용 COCO 모델의 점수를 크게 떨어뜨린다.
    final lb = computeLetterbox(frame.width, frame.height, _inputSize);
    final scaled = img.copyResize(frame, width: lb.scaledW, height: lb.scaledH);
    final canvas = img.Image(width: _inputSize, height: _inputSize)
      ..clear(img.ColorRgb8(114, 114, 114)); // ultralytics 표준 패딩색
    img.compositeImage(canvas, scaled, dstX: lb.padX, dstY: lb.padY);
    final input = _toFloat32Input(canvas);

    final output = List.generate(
      1,
      (_) => List.generate(_numDims, (_) => List.filled(_numAnchors, 0.0)),
    );

    _interpreter!.run(input, output);

    final best = _parseBest(output[0]);
    if (best == null) return null;
    // letterbox 좌표(모델 입력 기준 0~1)를 원본 프레임 기준 0~1로 역매핑.
    return unletterbox(best, lb, _inputSize);
  }

  List<List<List<List<double>>>> _toFloat32Input(img.Image image) {
    if (_inputChannelFirst) {
      // NCHW: [1][3][H][W]
      return [
        List.generate(3, (c) {
          return List.generate(
            _inputSize,
            (y) => List.generate(_inputSize, (x) {
              final px = image.getPixel(x, y);
              final v = c == 0 ? px.r : (c == 1 ? px.g : px.b);
              return v / 255.0;
            }),
          );
        })
      ];
    }
    // NHWC: [1][H][W][3]
    return [
      List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final px = image.getPixel(x, y);
          return [px.r / 255.0, px.g / 255.0, px.b / 255.0];
        }),
      )
    ];
  }

  BallDetection? _parseBest(List<List<double>> raw) {
    double maxConf = _confidenceThreshold;
    BallDetection? best;

    // 1클래스 전용학습 모델(5차원)은 row4가 곧 신뢰도, COCO 80클래스 모델은
    // row4부터 클래스별 점수라 sports ball(_ballClassIndex) 행만 본다.
    final confRow = _numDims == 5 ? 4 : 4 + _ballClassIndex;

    for (int i = 0; i < _numAnchors; i++) {
      final conf = raw[confRow][i];
      if (conf > debugMaxScore) debugMaxScore = conf;
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
    return best;
  }
}
