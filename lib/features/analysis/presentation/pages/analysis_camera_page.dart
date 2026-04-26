import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/data/services/camera_recording_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_analysis_service.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_result_page.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/analysis_loading_widget.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/camera_guide_overlay.dart';

class AnalysisCameraPage extends StatefulWidget {
  const AnalysisCameraPage({super.key});

  @override
  State<AnalysisCameraPage> createState() => _AnalysisCameraPageState();
}

class _AnalysisCameraPageState extends State<AnalysisCameraPage> {
  final _cameraService = CameraRecordingService();
  final _analysisService = VideoAnalysisService();

  CameraController? _controller;
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isAnalyzing = false;
  String? _analyzingVideoPath;
  String? _error;

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
      if (!mounted) return;
      setState(() => _error = '카메라 초기화 실패: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopAndAnalyze();
    } else {
      await _cameraService.startRecording();
      if (!mounted) return;
      setState(() => _isRecording = true);
    }
  }

  Future<void> _stopAndAnalyze() async {
    setState(() {
      _isRecording = false;
      _isAnalyzing = true;
    });

    try {
      final session = await _cameraService.stopRecording();
      if (mounted) setState(() => _analyzingVideoPath = session.videoPath);
      final analysisData =
          _analysisService.analyze(session.sampledFrames, session.fps);

      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AnalysisResultPage(
            analysisData: analysisData,
            videoPath: session.videoPath,
            recordedAt: DateTime.now(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _error = '분석 중 오류: $e';
      });
    }
  }

  @override
  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text(_error!, style: AppTextStyles.bodyMedium)),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
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
                    _isRecording ? Icons.stop : Icons.fiber_manual_record,
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
