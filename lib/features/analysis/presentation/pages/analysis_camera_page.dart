import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/data/services/camera_recording_service.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_trim_page.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/analysis_loading_widget.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/camera_guide_overlay.dart';

class AnalysisCameraPage extends StatefulWidget {
  const AnalysisCameraPage({super.key});

  @override
  State<AnalysisCameraPage> createState() => _AnalysisCameraPageState();
}

class _AnalysisCameraPageState extends State<AnalysisCameraPage> {
  final _cameraService = CameraRecordingService();

  CameraController? _controller;
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isAnalyzing = false;
  String? _analyzingVideoPath;
  String? _error;

  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final ctrl = await _cameraService.initialize();
      if (!mounted) return;
      setState(() {
        _controller = ctrl;
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('카메라 초기화 실패: $e');
      if (!mounted) return;
      setState(() => _error = '카메라를 열 수 없어요. 앱 권한을 확인해 주세요');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopAndAnalyze();
    } else {
      await _cameraService.startRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordingSeconds++);
      });
    }
  }

  Future<void> _stopAndAnalyze() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() {
      _isRecording = false;
      _isAnalyzing = true;
    });

    try {
      final session = await _cameraService.stopRecording();
      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AnalysisTrimPage(
            videoPath: session.videoPath,
            fps: session.fps,
          ),
        ),
      );
    } catch (e) {
      debugPrint('분석 중 오류: $e');
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _error = '녹화 처리 중 문제가 발생했어요. 다시 시도해 주세요';
      });
    }
  }

  String _formatElapsed(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _cameraService.dispose();
    super.dispose();
  }

  Widget _buildCloseButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.4),
            shape: const CircleBorder(),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Stack(
          children: [
            Center(child: Text(_error!, style: AppTextStyles.bodyMedium)),
            Align(alignment: Alignment.topLeft, child: _buildCloseButton()),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Scaffold(
        body: Stack(
          children: [
            const Center(child: CircularProgressIndicator()),
            Align(alignment: Alignment.topLeft, child: _buildCloseButton()),
          ],
        ),
      );
    }

    if (_isAnalyzing) {
      return Scaffold(
        body: AnalysisLoadingWidget(videoPath: _analyzingVideoPath),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          CameraGuideOverlay(isRecording: _isRecording),
          Align(alignment: Alignment.topLeft, child: _buildCloseButton()),
          if (_isRecording)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatElapsed(_recordingSeconds),
                          style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _toggleRecording,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.red : Colors.white,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Icon(
                    _isRecording ? PhosphorIconsFill.stop : PhosphorIconsFill.record,
                    color: _isRecording ? Colors.white : Colors.red,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 72,
            right: 40,
            child: Text(
              '${_cameraService.fps}fps',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
