import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/data/repositories/calibration_repository_impl.dart';
import 'package:bowling_diary/features/analysis/data/services/analysis_pipeline.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/services/calibration_drift_checker.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_result_page.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/calibration_page.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/analysis_loading_widget.dart';

class AnalysisTrimPage extends StatefulWidget {
  final String videoPath;
  final int fps;

  const AnalysisTrimPage({
    super.key,
    required this.videoPath,
    required this.fps,
  });

  @override
  State<AnalysisTrimPage> createState() => _AnalysisTrimPageState();
}

class _AnalysisTrimPageState extends State<AnalysisTrimPage> {
  VideoPlayerController? _controller;
  double _startSec = 0;
  double _endSec = 0;
  double _totalSec = 0;
  bool _isAnalyzing = false;
  String? _trimmedPath;
  CalibrationProfile? _calibrationProfile;

  @override
  void initState() {
    super.initState();
    _initVideo();
    _loadDefaultCalibrationProfile();
  }

  Future<void> _loadDefaultCalibrationProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final profile = await CalibrationRepositoryImpl(prefs).getDefault();
    if (mounted) setState(() => _calibrationProfile = profile);
  }

  Future<void> _openCalibration() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (!mounted) return;
    final profile = await Navigator.push<CalibrationProfile>(
      context,
      MaterialPageRoute(builder: (_) => CalibrationPage(referenceImagePath: picked.path)),
    );
    if (profile != null) {
      await _loadDefaultCalibrationProfile();
    }
  }

  Future<void> _initVideo() async {
    final ctrl = VideoPlayerController.file(File(widget.videoPath));
    await ctrl.initialize();
    await ctrl.setLooping(false);
    ctrl.addListener(_onPositionChanged);

    final total = ctrl.value.duration.inMilliseconds / 1000.0;
    if (!mounted) return;
    setState(() {
      _controller = ctrl;
      _totalSec = total;
      _startSec = 0;
      _endSec = total;
    });
  }

  void _onPositionChanged() {
    if (_controller == null || !mounted) return;
    final pos = _controller!.value.position.inMilliseconds / 1000.0;
    if (_controller!.value.isPlaying && pos >= _endSec) {
      _controller!.seekTo(Duration(milliseconds: (_startSec * 1000).round()));
      _controller!.pause();
    }
    setState(() {});
  }

  void _onRangeChanged(RangeValues values) {
    if (values.end - values.start < 0.5) return;
    final endChanged = values.end != _endSec;
    setState(() {
      _startSec = values.start;
      _endSec = values.end;
    });
    final seekSec = endChanged ? _endSec : _startSec;
    _controller?.seekTo(Duration(milliseconds: (seekSec * 1000).round()));
    _controller?.pause();
  }

  void _togglePlay() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.seekTo(Duration(milliseconds: (_startSec * 1000).round()));
      _controller!.play();
    }
  }

  Future<void> _startAnalysis() async {
    final profile = _calibrationProfile;
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('캘리브레이션 프로파일이 없습니다. 먼저 캘리브레이션을 완료해 주세요')),
      );
      return;
    }

    setState(() => _isAnalyzing = true);
    try {
      final tempDir = await getTemporaryDirectory();
      final trimmedPath = '${tempDir.path}/trimmed_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final session = await FFmpegKit.execute(
        '-i "${widget.videoPath}" -ss $_startSec -to $_endSec -c copy "$trimmedPath"',
      );
      final rc = await session.getReturnCode();
      if (rc == null || !rc.isValueSuccess()) throw Exception('영상 자르기 실패');

      if (mounted) setState(() => _trimmedPath = trimmedPath);

      final pipeline = AnalysisPipeline(
        frameExtractor: VideoFrameExtractorService(),
        ballDetector: BallDetectionService(),
        releaseDetector: ReleaseDetectorService(),
        impactDetector: ImpactDetectorService(pinImpactDetector: PinImpactDetectorService()),
        speedEstimator: SpeedEstimatorService(),
        driftChecker: CalibrationDriftChecker(),
      );
      final analysisData = await pipeline.run(trimmedPath, profile, widget.fps);

      if (!mounted) return;
      await Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => AnalysisResultPage(
          analysisData: analysisData, videoPath: trimmedPath, recordedAt: DateTime.now(),
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('분석 실패: $e')));
    }
  }

  String _fmt(double seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toStringAsFixed(1).padLeft(4, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPositionChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAnalyzing) {
      return Scaffold(
        body: AnalysisLoadingWidget(
          videoPath: _trimmedPath ?? widget.videoPath,
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final selectedDuration = _endSec - _startSec;

    return Scaffold(
      appBar: AppBar(
        title: const Text('구간 선택'),
        actions: [
          IconButton(
            icon: const Icon(Icons.straighten),
            tooltip: '레인 캘리브레이션',
            onPressed: _openCalibration,
          ),
        ],
      ),
      body: Column(
        children: [
          // 영상 미리보기 (최대 화면 45%)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: GestureDetector(
              onTap: _togglePlay,
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller!),
                    if (!_controller!.value.isPlaying)
                      Container(
                        color: Colors.black38,
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 64,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                children: [
                  // 구간 정보
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(_startSec),
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.neonOrange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${selectedDuration.toStringAsFixed(1)}초 선택됨',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.neonOrange),
                        ),
                      ),
                      Text(_fmt(_endSec),
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // 구간 슬라이더
                  RangeSlider(
                    values: RangeValues(_startSec, _endSec),
                    min: 0,
                    max: _totalSec,
                    divisions: (_totalSec * 10).round().clamp(1, 1000),
                    activeColor: AppColors.neonOrange,
                    inactiveColor: AppColors.textHint,
                    onChanged: _onRangeChanged,
                  ),

                  Text(
                    '투구 시작(릴리즈)부터 핀 충돌까지 구간을 선택하세요\n짧을수록 분석이 정확합니다',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.neonOrange,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _startAnalysis,
                      child: Text(
                        '분석 시작',
                        style: AppTextStyles.bodyLarge
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
