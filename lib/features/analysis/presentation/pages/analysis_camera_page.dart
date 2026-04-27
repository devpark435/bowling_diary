import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/data/services/camera_recording_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_analysis_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/camera_guide_overlay.dart';

class AnalysisCameraPage extends StatefulWidget {
  const AnalysisCameraPage({super.key});

  @override
  State<AnalysisCameraPage> createState() => _AnalysisCameraPageState();
}

class _AnalysisCameraPageState extends State<AnalysisCameraPage> {
  final _cameraService = CameraRecordingService();
  final _analysisService = VideoAnalysisService();
  final _frameExtractor = VideoFrameExtractorService();

  CameraController? _controller;
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isAnalyzing = false;
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

  Future<void> _pickFromGallery() async {
    final video = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (video == null || !mounted) return;

    setState(() => _isAnalyzing = true);
    try {
      final result = await _frameExtractor.extract(video.path);
      final analysisData = _analysisService.analyzeImages(
        result.frames,
        result.originalFps,
      );

      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      if (!mounted) return;
      context.pushReplacement('/analysis/result', extra: {
        'analysisData': analysisData,
        'videoPath': video.path,
        'recordedAt': DateTime.now(),
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _error = '갤러리 영상 분석 오류: $e';
      });
    }
  }

  Future<void> _stopAndAnalyze() async {
    setState(() {
      _isRecording = false;
      _isAnalyzing = true;
    });

    try {
      final session = await _cameraService.stopRecording();
      final analysisData =
          _analysisService.analyze(session.sampledFrames, session.fps);

      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      if (!mounted) return;
      context.pushReplacement('/analysis/result', extra: {
        'analysisData': analysisData,
        'videoPath': session.videoPath,
        'recordedAt': DateTime.now(),
      });
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
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.neonOrange),
              const SizedBox(height: 24),
              Text('영상 분석 중...', style: AppTextStyles.bodyLarge),
            ],
          ),
        ),
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
          if (!_isRecording)
            Positioned(
              bottom: 68,
              left: 40,
              child: GestureDetector(
                onTap: _pickFromGallery,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black45,
                    border: Border.all(color: Colors.white54, width: 1.5),
                  ),
                  child: const Icon(
                    PhosphorIconsRegular.images,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
