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
    final hasSpeed = r.speedKmh != null;
    final hasRpm = r.rpmEstimated != null;
    final dateStr = DateFormat('yyyy.MM.dd  HH:mm').format(r.recordedAt);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Text(
          dateStr,
          style: AppTextStyles.bodySmall.copyWith(
            color: Colors.white60,
            fontSize: 13,
          ),
        ),
        actions: [
          if (_videoAvailable)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 영상 or 빈 배경
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
                child: Icon(Icons.videocam_off_outlined,
                    color: AppColors.textHint, size: 48),
              ),
            ),

          // 하단 그라데이션
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 380,
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

          // 하단 수치 패널
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
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 구속
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (hasSpeed) ...[
                              Text(
                                r.speedKmh!.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.neonOrange,
                                  height: 1.0,
                                  letterSpacing: -1.5,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 8, left: 6),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('km/h',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: AppColors.neonOrange
                                              .withValues(alpha: 0.75),
                                          fontWeight: FontWeight.w500,
                                        )),
                                    const Text('구속',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white38,
                                          letterSpacing: 1.2,
                                        )),
                                  ],
                                ),
                              ),
                            ] else
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '측정불가',
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white24,
                                        height: 1.0,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text('구속',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white24,
                                          letterSpacing: 1.2,
                                        )),
                                  ],
                                ),
                              ),
                          ],
                        ),

                        Divider(
                          color: Colors.white.withValues(alpha: 0.1),
                          height: 20,
                        ),

                        // RPM
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (hasRpm) ...[
                              Text(
                                '${r.rpmEstimated}',
                                style: const TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.0,
                                  letterSpacing: -1,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 6, left: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('rpm',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.white60,
                                          fontWeight: FontWeight.w500,
                                        )),
                                    Text('RPM 추정값',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white30,
                                          letterSpacing: 0.5,
                                        )),
                                  ],
                                ),
                              ),
                            ] else
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '측정불가',
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white24,
                                        height: 1.0,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text('RPM',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white24,
                                          letterSpacing: 0.5,
                                        )),
                                  ],
                                ),
                              ),
                          ],
                        ),

                        if (r.linkedSessionId != null) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Icon(Icons.link_rounded,
                                  color: AppColors.neonOrange, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                '세션에 연결됨',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.neonOrange
                                      .withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ],
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
