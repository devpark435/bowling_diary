import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// 녹화 완료 후 반환되는 결과
class RecordingSession {
  final String videoPath;
  final List<CameraImage> sampledFrames;
  final int fps;
  final int sampleInterval;

  const RecordingSession({
    required this.videoPath,
    required this.sampledFrames,
    required this.fps,
    required this.sampleInterval,
  });
}

class CameraRecordingService {
  CameraController? _controller;
  final List<CameraImage> _frames = [];
  int _frameCounter = 0;
  int _fps = 60;

  /// 카메라 초기화. 240 → 120 → 60fps 순으로 시도
  Future<CameraController> initialize() async {
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    for (final targetFps in [240, 120, 60]) {
      try {
        final ctrl = CameraController(
          back,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        await ctrl.initialize();
        await ctrl.getMinExposureOffset();
        _fps = targetFps;
        _controller = ctrl;
        debugPrint('[Analysis] 카메라 초기화 완료: ${_fps}fps');
        return ctrl;
      } catch (_) {
        debugPrint('[Analysis] ${targetFps}fps 불지원 → 다음 시도');
        continue;
      }
    }
    throw Exception('카메라 초기화 실패');
  }

  CameraController get controller {
    assert(_controller != null, 'initialize() 먼저 호출 필요');
    return _controller!;
  }

  int get fps => _fps;

  /// 녹화 시작 (프레임 스트림 병행 수집)
  Future<void> startRecording() async {
    _frames.clear();
    _frameCounter = 0;

    // 10프레임마다 1개 샘플링
    await _controller!.startImageStream((image) {
      _frameCounter++;
      if (_frameCounter % 10 == 0) {
        _frames.add(image);
      }
    });
    await _controller!.startVideoRecording();
    debugPrint('[Analysis] 녹화 시작');
  }

  /// 녹화 중지 후 RecordingSession 반환
  Future<RecordingSession> stopRecording() async {
    final xfile = await _controller!.stopVideoRecording();
    await _controller!.stopImageStream();

    debugPrint('[Analysis] 녹화 완료: ${_frames.length}개 프레임 수집');
    return RecordingSession(
      videoPath: xfile.path,
      sampledFrames: List.unmodifiable(_frames),
      fps: _fps,
      sampleInterval: 10,
    );
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
}
