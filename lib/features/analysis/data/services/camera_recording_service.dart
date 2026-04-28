import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class RecordingSession {
  final String videoPath;
  final int fps;

  const RecordingSession({required this.videoPath, required this.fps});
}

class CameraRecordingService {
  CameraController? _controller;
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

  Future<void> startRecording() async {
    await _controller!.startVideoRecording();
    debugPrint('[Analysis] 녹화 시작');
  }

  Future<RecordingSession> stopRecording() async {
    final xfile = await _controller!.stopVideoRecording();
    debugPrint('[Analysis] 녹화 완료: ${xfile.path}');
    return RecordingSession(videoPath: xfile.path, fps: _fps);
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
}
