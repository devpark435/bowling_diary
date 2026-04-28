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
              Text(
                '영상 분석 중...',
                style: AppTextStyles.bodyLarge.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                '볼 궤적을 추적하고 있어요',
                style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
