import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/domain/entities/analysis_result_entity.dart';

class AnalysisDetailPage extends StatefulWidget {
  final AnalysisResultEntity result;

  const AnalysisDetailPage({super.key, required this.result});

  @override
  State<AnalysisDetailPage> createState() => _AnalysisDetailPageState();
}

class _AnalysisDetailPageState extends State<AnalysisDetailPage>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _videoAvailable = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));

    _initVideo();
  }

  Future<void> _initVideo() async {
    final path = widget.result.videoLocalPath;
    if (path == null || !File(path).existsSync()) {
      _animCtrl.forward();
      return;
    }
    try {
      final ctrl = VideoPlayerController.file(File(path));
      await ctrl.initialize();
      await ctrl.setPlaybackSpeed(0.25);
      await ctrl.setLooping(true);
      await ctrl.play();
      if (!mounted) return;
      setState(() {
        _controller = ctrl;
        _videoAvailable = true;
      });
    } catch (_) {}
    _animCtrl.forward();
  }

  void _togglePlay() {
    if (_controller == null) return;
    _controller!.value.isPlaying
        ? _controller!.pause()
        : _controller!.play();
    setState(() {});
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final hasSpeed = r.speedKmh > 0;
    final hasRpm = r.rpmEstimated != null;
    final dateStr =
        DateFormat('yyyy년 MM월 dd일 HH:mm').format(r.recordedAt);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 영상 or 어두운 배경
          if (_videoAvailable && _controller != null)
            GestureDetector(
              onTap: _togglePlay,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            )
          else
            Container(
              color: AppColors.darkBg,
              child: Center(
                child: Icon(
                  Icons.videocam_off_outlined,
                  color: AppColors.textHint,
                  size: 48,
                ),
              ),
            ),

          // 상단 그라데이션
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 130,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 하단 그라데이션
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 360,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.95),
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 상단바
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  if (_videoAvailable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.slow_motion_video,
                              color: AppColors.neonOrange, size: 13),
                          const SizedBox(width: 4),
                          Text('0.25×',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: Colors.white60, fontSize: 11)),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          // 일시정지 아이콘
          if (_videoAvailable &&
              _controller != null &&
              !_controller!.value.isPlaying)
            GestureDetector(
              onTap: _togglePlay,
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1.5),
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 36),
                ),
              ),
            ),

          // 하단 통계 패널
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 날짜
                        Text(
                          dateStr,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.white38,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 구속
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              hasSpeed
                                  ? r.speedKmh.toStringAsFixed(1)
                                  : '—',
                              style: TextStyle(
                                fontSize: 56,
                                fontWeight: FontWeight.w800,
                                color: hasSpeed
                                    ? AppColors.neonOrange
                                    : AppColors.textHint,
                                height: 1.0,
                                letterSpacing: -1.5,
                              ),
                            ),
                            if (hasSpeed)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 8, left: 6),
                                child: Text(
                                  'km/h',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: AppColors.neonOrange
                                        .withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        Divider(
                          color: Colors.white.withValues(alpha: 0.1),
                          height: 20,
                        ),

                        // RPM + fps
                        Row(
                          children: [
                            _InfoChip(
                              label: 'RPM',
                              value: hasRpm
                                  ? '${r.rpmEstimated}'
                                  : '—',
                              sub: hasRpm ? '추정값' : null,
                            ),
                            const SizedBox(width: 12),
                            _InfoChip(
                              label: 'FPS',
                              value: '${r.fpsUsed}',
                            ),
                            if (r.linkedSessionId != null) ...[
                              const SizedBox(width: 12),
                              _InfoChip(
                                label: '세션',
                                value: '연결됨',
                                accent: true,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final bool accent;

  const _InfoChip({
    required this.label,
    required this.value,
    this.sub,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent
              ? AppColors.neonOrange.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 10, color: Colors.white38, letterSpacing: 1),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: accent ? AppColors.neonOrange : Colors.white,
              height: 1.1,
            ),
          ),
          if (sub != null)
            Text(sub!,
                style: const TextStyle(
                    fontSize: 9, color: Colors.white30, letterSpacing: 0.3)),
        ],
      ),
    );
  }
}
