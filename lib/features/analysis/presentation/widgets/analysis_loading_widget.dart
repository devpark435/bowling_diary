import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/bowling_pin_character.dart';

class AnalysisLoadingWidget extends StatefulWidget {
  final String? videoPath;

  const AnalysisLoadingWidget({super.key, this.videoPath});

  @override
  State<AnalysisLoadingWidget> createState() => _AnalysisLoadingWidgetState();
}

class _AnalysisLoadingWidgetState extends State<AnalysisLoadingWidget>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _videoReady = false;
  late final AnimationController _swayCtrl;
  late final Animation<double> _swayAnim;

  int _stepIndex = 0;

  static const _steps = [
    ('영상 업로드 중...', 'AI 분석을 준비하고 있어요'),
    ('구속 측정 중...', '파울라인~헤드핀 구간을 추적해요'),
    ('회전수 측정 중...', '볼 표면 회전 패턴을 분석해요'),
    ('결과 화면 만드는 중...', '거의 다 됐어요!'),
  ];

  static const _stepDurations = [8, 10, 10, 999];

  @override
  void initState() {
    super.initState();
    _swayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _swayAnim = Tween<double>(begin: -0.12, end: 0.12).animate(
      CurvedAnimation(parent: _swayCtrl, curve: Curves.easeInOut),
    );
    if (widget.videoPath != null) _initVideo(widget.videoPath!);
    _scheduleNextStep();
  }

  void _scheduleNextStep() {
    if (_stepIndex >= _steps.length - 1) return;
    Future.delayed(Duration(seconds: _stepDurations[_stepIndex]), () {
      if (!mounted) return;
      setState(() => _stepIndex++);
      _scheduleNextStep();
    });
  }

  Future<void> _initVideo(String path) async {
    try {
      final ctrl = VideoPlayerController.file(File(path));
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(0);
      await ctrl.play();
      if (!mounted) return;
      setState(() {
        _controller = ctrl;
        _videoReady = true;
      });
    } catch (_) {
      // 영상 로드 실패 시 스피너로 fallback
    }
  }

  @override
  void dispose() {
    _swayCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _steps[_stepIndex];

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_videoReady && _controller != null)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        Container(
          color: Colors.black.withValues(alpha: _videoReady ? 0.5 : 1.0),
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _swayAnim,
                builder: (_, __) => Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.rotationZ(_swayAnim.value),
                  child: const BowlingPinCharacter(emotion: 'normal'),
                ),
              ),
              const SizedBox(height: 28),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  title,
                  key: ValueKey(title),
                  style: AppTextStyles.bodyLarge.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  subtitle,
                  key: ValueKey(subtitle),
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
