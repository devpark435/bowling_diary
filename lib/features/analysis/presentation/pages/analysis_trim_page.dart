import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/core/services/debug_log_buffer.dart';
import 'package:bowling_diary/features/analysis/data/services/analysis_debug_log_service.dart';
import 'package:bowling_diary/features/analysis/data/services/analysis_pipeline.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:bowling_diary/features/analysis/data/services/speed_estimator_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/homography_solver.dart';
import 'package:bowling_diary/features/analysis/domain/services/lane_detector_service.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_result_page.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/lane_confirm_page.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/analysis_loading_widget.dart';

/// 레인 실측 좌표계(spec §10 기준: 파울라인=y0, 핀덱=y18.29m, 폭 1.05m).
/// 순서는 코너 리스트와 동일하게 foul-left, foul-right, pin-right, pin-left.
const _laneCorners = [
  LanePoint(xM: 0, yM: 0),
  LanePoint(xM: 1.05, yM: 0),
  LanePoint(xM: 1.05, yM: 18.29),
  LanePoint(xM: 0, yM: 18.29),
];

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
  final _debugLog = AnalysisDebugLogService();

  @override
  void initState() {
    super.initState();
    _initVideo();
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
    setState(() => _isAnalyzing = true);
    // 실패 시 어느 단계에서 터졌는지 QA가 바로 알 수 있게 단계를 기록한다
    // (기존에는 6개 실패 지점이 하나의 "문제가 발생했어요"로 뭉개졌다).
    var stage = '영상 자르기';
    // 이번 분석이 남긴 줄만 올라가도록 직전 세션 로그를 비운다.
    DebugLogBuffer.instance.clear();
    try {
      final tempDir = await getTemporaryDirectory();
      final trimmedPath = '${tempDir.path}/trimmed_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final trimSession = await FFmpegKit.execute(
        '-i "${widget.videoPath}" -ss $_startSec -to $_endSec -c copy "$trimmedPath"',
      );
      final trimRc = await trimSession.getReturnCode();
      if (trimRc == null || !trimRc.isValueSuccess()) {
        throw Exception('영상 자르기 실패 (rc: $trimRc)\n${await _ffmpegTail(trimSession)}');
      }

      if (mounted) setState(() => _trimmedPath = trimmedPath);

      // 트림된 영상의 첫 프레임을 뽑아 레인 4코너를 자동검출한다(spec §10:
      // 영상별 자동검출+확인 — 저장형 캘리브레이션 프로파일 폐기).
      stage = '첫 프레임 추출';
      final framePath = '${tempDir.path}/lane_frame_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final frameSession = await FFmpegKit.execute(
        '-i "$trimmedPath" -frames:v 1 -q:v 3 "$framePath"',
      );
      final frameRc = await frameSession.getReturnCode();
      if (frameRc == null || !frameRc.isValueSuccess()) {
        throw Exception('첫 프레임 추출 실패 (rc: $frameRc)\n${await _ffmpegTail(frameSession)}');
      }

      final frameBytes = await File(framePath).readAsBytes();
      final frame = img.decodeImage(frameBytes);
      if (frame == null) throw Exception('첫 프레임 디코딩 실패');

      stage = '레인 검출';
      final detection = LaneDetectorService().detect(frame);

      if (!mounted) return;
      final confirmedCorners = await Navigator.push<List<FramePoint>>(
        context,
        MaterialPageRoute(
          builder: (_) => LaneConfirmPage(framePath: framePath, detection: detection),
        ),
      );

      if (!mounted) return;
      if (confirmedCorners == null) {
        // 유저가 확인 화면에서 취소함 — 분석을 중단하고 트림 화면으로 되돌아간다.
        setState(() => _isAnalyzing = false);
        return;
      }

      stage = '호모그래피 계산';
      final homography = HomographySolver.solve4Point(confirmedCorners, _laneCorners);

      stage = '분석 파이프라인';
      final pipeline = AnalysisPipeline(
        frameExtractor: VideoFrameExtractorService(),
        ballDetector: BallDetectionService(),
        releaseDetector: ReleaseDetectorService(),
        impactDetector: ImpactDetectorService(pinImpactDetector: PinImpactDetectorService()),
        speedEstimator: SpeedEstimatorService(),
      );
      // 화살표 검출은 분석 프레임(폭 480, jpeg q5)에선 뭉개진다 — 레인 확인용으로
      // 이미 원본 해상도로 뽑아둔 첫 프레임을 그대로 넘긴다.
      final analysisData =
          await pipeline.run(trimmedPath, homography, landmarkFrame: frame);

      // 성공 케이스도 남긴다 — 구속 두 코어 값이 매 투구 쌓여야 표본 1개가
      // 아닌 분포로 정확도를 판단할 수 있다. await하지 않는다(결과 화면 지연 방지).
      unawaited(_debugLog.log(
        outcome: 'success',
        metrics: <String, dynamic>{
          'frames_analyzed': analysisData.framesAnalyzed,
          'fps_used': analysisData.fpsUsed,
          'speed_kmh': analysisData.speedKmh,
          'landmark_speed_kmh': analysisData.landmarkSpeedKmh,
          'legacy_speed_kmh': analysisData.legacySpeedKmh,
          'speed_source': analysisData.speedSource?.name,
          'speed_confidence': analysisData.speedConfidence,
          'speed_failure': analysisData.speedFailure?.name,
          'trajectory_source': analysisData.trajectorySource?.name,
          'trajectory_fit_rms': analysisData.trajectoryFitRms,
          'trajectory_points': analysisData.trajectory.length,
          // 리본이 핀까지 닿는지 SQL만으로 판정하기 위한 끝점(깊이축 정규화 좌표).
          'trajectory_first_frame': analysisData.trajectory.isEmpty
              ? null
              : analysisData.trajectory.first.frame,
          'trajectory_last_frame': analysisData.trajectory.isEmpty
              ? null
              : analysisData.trajectory.last.frame,
          'trajectory_first_ny': analysisData.trajectory.isEmpty
              ? null
              : (analysisData.trajectory.first.left.ny +
                      analysisData.trajectory.first.right.ny) /
                  2,
          'trajectory_last_ny': analysisData.trajectory.isEmpty
              ? null
              : (analysisData.trajectory.last.left.ny +
                      analysisData.trajectory.last.right.ny) /
                  2,
          'entry_angle_deg': analysisData.entryAngleDeg,
          'trim_start_sec': _startSec,
          'trim_end_sec': _endSec,
        },
      ));

      if (!mounted) return;
      await Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => AnalysisResultPage(
          analysisData: analysisData, videoPath: trimmedPath, recordedAt: DateTime.now(),
        ),
      ));
    } catch (e, st) {
      debugPrint('분석 실패 [$stage]: $e\n$st');
      unawaited(_debugLog.log(
        outcome: 'failure',
        stage: stage,
        error: e,
        stack: st,
        metrics: <String, dynamic>{
          'trim_start_sec': _startSec,
          'trim_end_sec': _endSec,
          'source_fps': widget.fps,
        },
      ));
      if (!mounted) return;
      setState(() => _isAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('[$stage] 단계에서 실패했어요. 다시 시도해 주세요'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '자세히',
            onPressed: () => _showFailureDetail(stage, e, st),
          ),
        ),
      );
    }
  }

  /// ffmpeg 실패 원인은 returnCode만으론 알 수 없다 — 마지막 로그 몇 줄을
  /// 예외 메시지에 붙여 TestFlight에서도 원인이 보이게 한다.
  Future<String> _ffmpegTail(dynamic session) async {
    try {
      final logs = await session.getLogs();
      final lines = logs
          .map((dynamic l) => l.getMessage() as String? ?? '')
          .join()
          .split('\n')
          .where((String l) => l.trim().isNotEmpty)
          .toList();
      return lines.length <= 12 ? lines.join('\n') : lines.sublist(lines.length - 12).join('\n');
    } catch (e) {
      return '(로그 수집 실패: $e)';
    }
  }

  /// 내부 QA용 — 실패 단계/예외/스택을 그대로 보여준다. 공개 배포 전 제거.
  void _showFailureDetail(String stage, Object error, StackTrace st) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('분석 실패 — $stage'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              '$error\n\n$st',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
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
