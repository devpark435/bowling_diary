import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class BallDetection {
  final double cx; // 0~1 정규화 중심 x
  final double cy; // 0~1 정규화 중심 y
  final double confidence;

  const BallDetection({
    required this.cx,
    required this.cy,
    required this.confidence,
  });
}

class BallDetectionService {
  static const _modelPath = 'assets/models/yolov8n.tflite';
  static const _inputSize = 320;
  static const _sportsBallClass = 32; // COCO class index
  static const _confidenceThreshold = 0.1;

  Interpreter? _interpreter;

  Future<void> init() async {
    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(_modelPath, options: options);
    final inShape = _interpreter!.getInputTensor(0).shape;
    final outShape = _interpreter!.getOutputTensor(0).shape;
    debugPrint('[BallDetection] 모델 로드 완료 | 입력: $inShape | 출력: $outShape');
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  int _detectCount = 0;

  /// 프레임에서 볼러(person) 하단 y좌표 반환 (0~1, 높을수록 카메라에 가까움)
  double? detectPersonBottom(img.Image frame) {
    if (_interpreter == null) return null;
    final resized = img.copyResize(frame, width: _inputSize, height: _inputSize);
    final input = _toFloat32Input(resized);
    final output = List.generate(1, (_) => List.generate(84, (_) => List.filled(2100, 0.0)));
    _interpreter!.run(input, output);
    final raw = output[0];

    double maxConf = 0.4; // person 신뢰도 임계값
    double? bottom;
    for (int i = 0; i < 2100; i++) {
      final conf = raw[4][i]; // class 0 = person
      if (conf <= maxConf) continue;
      maxConf = conf;
      final cy = raw[1][i];
      final h = raw[3][i];
      bottom = (cy + h / 2).clamp(0.0, 1.0);
    }
    return bottom;
  }

  /// 모든 프레임에서 person 위치 추적 → 릴리즈 프레임 인덱스 반환
  /// 릴리즈 = person 이동 속도가 양수(접근)에서 0(정지)으로 전환되는 시점
  int findReleaseFrame(List<img.Image> frames) {
    // 1. 각 프레임의 person bottom y 수집
    final bottomY = <double?>[];
    for (final frame in frames) {
      bottomY.add(detectPersonBottom(frame));
    }

    // 2. 연속된 y 변화량(속도) 계산
    final velocities = <double>[];
    for (int i = 1; i < bottomY.length; i++) {
      final prev = bottomY[i - 1];
      final curr = bottomY[i];
      velocities.add((prev != null && curr != null) ? curr - prev : 0.0);
    }

    // 3. 속도가 양수(접근)였다가 0 이하로 전환되는 첫 지점 = 릴리즈
    int releaseFrame = 0;
    for (int i = 1; i < velocities.length; i++) {
      if (velocities[i - 1] > 0.01 && velocities[i] <= 0.01) {
        releaseFrame = i;
        break;
      }
    }

    // 릴리즈 감지 실패 시 → person bottom 최대 지점 사용
    if (releaseFrame == 0) {
      double maxBottom = 0;
      for (int i = 0; i < bottomY.length; i++) {
        final b = bottomY[i];
        if (b != null && b > maxBottom) { maxBottom = b; releaseFrame = i; }
      }
    }

    // 릴리즈 이후 충분한 프레임 있는지 확인
    final remaining = frames.length - releaseFrame;
    debugPrint('[BallDetection] 릴리즈 프레임: $releaseFrame, 이후 $remaining프레임 남음');

    if (remaining < 5) {
      debugPrint('[BallDetection] 릴리즈 이후 프레임 부족 → 릴리즈 프레임 0으로 초기화');
      return 0;
    }

    return releaseFrame;
  }

  /// 프레임에서 볼링공 감지 → 중심 좌표 반환 (없으면 null)
  BallDetection? detect(img.Image frame) {
    if (_interpreter == null) return null;

    final resized = img.copyResize(frame, width: _inputSize, height: _inputSize);
    final input = _toFloat32Input(resized);

    // 출력 버퍼: [1, 84, 2100] — YOLOv8n 320×320
    final output = List.generate(
      1,
      (_) => List.generate(84, (_) => List.filled(2100, 0.0)),
    );

    _interpreter!.run(input, output);
    _detectCount++;

    return _parseBestDetection(output[0], verbose: _detectCount == 1);
  }

  // 입력 텐서: [1, 320, 320, 3] float32
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

  // output[dim][anchors] 에서 sports ball 최고 신뢰도 감지 반환
  BallDetection? _parseBestDetection(List<List<double>> raw, {bool verbose = false}) {
    final numDims = raw.length;
    final numAnchors = raw.isNotEmpty ? raw[0].length : 0;

    // sports ball class 신뢰도 최대값 찾기 (shape 진단)
    double maxConf = 0;
    int maxAnchor = 0;
    for (int i = 0; i < numAnchors; i++) {
      final conf = raw[4 + _sportsBallClass][i];
      if (conf > maxConf) { maxConf = conf; maxAnchor = i; }
    }

    if (verbose) {
      debugPrint('[BallDetection] shape=[$numDims][$numAnchors], sports ball 최대신뢰도=${maxConf.toStringAsFixed(3)} @anchor$maxAnchor');
      // 전체 클래스 중 최고 신뢰도 클래스 확인
      double globalMax = 0; int globalClass = 0; int globalAnchor = 0;
      for (int c = 4; c < numDims; c++) {
        for (int i = 0; i < numAnchors; i++) {
          if (raw[c][i] > globalMax) {
            globalMax = raw[c][i]; globalClass = c - 4; globalAnchor = i;
          }
        }
      }
      debugPrint('[BallDetection] 전체 최고: class=$globalClass, conf=${globalMax.toStringAsFixed(3)} @anchor$globalAnchor');
    }

    BallDetection? best;
    for (int i = 0; i < numAnchors; i++) {
      final conf = raw[4 + _sportsBallClass][i];
      if (conf < _confidenceThreshold) continue;
      if (best != null && conf <= best.confidence) continue;

      final cx = raw[0][i].clamp(0.0, 1.0);
      final cy = raw[1][i].clamp(0.0, 1.0);
      best = BallDetection(cx: cx, cy: cy, confidence: conf);
    }

    return best;
  }
}

/// 볼 위치 시퀀스에서 릴리즈/임팩트 프레임 추출 → elapsed 계산
class BallTracker {
  static const _laneLength = 18.29; // m

  /// positions: 프레임별 BallDetection? (null = 볼 없음)
  /// fps: 실제 영상 fps
  static double? calcSpeedKmh(List<BallDetection?> positions, double fps) {
    // 연속 감지 구간 찾기 (최소 3프레임)
    final detected = <int>[];
    for (int i = 0; i < positions.length; i++) {
      if (positions[i] != null) detected.add(i);
    }
    if (detected.length < 3) {
      debugPrint('[BallTracker] 볼 감지 부족: ${detected.length}프레임');
      return null;
    }

    // 볼이 레인 위에서 이동하는 구간만 사용
    // 볼이 카메라에서 멀어질수록 cy 감소 (또는 화면 내 위치에 따라 다름)
    // 연속된 감지 구간의 첫 프레임 = 릴리즈, 마지막 = 임팩트
    final releaseFrame = detected.first;
    final impactFrame = detected.last;
    final frameDiff = impactFrame - releaseFrame;

    if (frameDiff <= 0) return null;

    final elapsed = frameDiff / fps;
    final rawSpeed = (_laneLength / elapsed) * 3.6;

    debugPrint('[BallTracker] 프레임 $releaseFrame→$impactFrame, elapsed=${elapsed.toStringAsFixed(2)}s, 속도=${rawSpeed.toStringAsFixed(1)}km/h');

    if (rawSpeed < 15 || rawSpeed > 50) {
      debugPrint('[BallTracker] 속도 범위 초과 → 측정불가');
      return null;
    }

    return double.parse(rawSpeed.toStringAsFixed(1));
  }
}
