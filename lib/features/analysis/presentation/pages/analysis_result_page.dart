import 'dart:io' as dart_io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/data/services/video_analysis_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:bowling_diary/features/analysis/presentation/providers/analysis_provider.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';
import 'package:bowling_diary/features/record/domain/entities/session_entity.dart';

class AnalysisResultPage extends ConsumerStatefulWidget {
  final AnalysisData analysisData;
  final String videoPath;
  final DateTime recordedAt;

  const AnalysisResultPage({
    super.key,
    required this.analysisData,
    required this.videoPath,
    required this.recordedAt,
  });

  @override
  ConsumerState<AnalysisResultPage> createState() => _AnalysisResultPageState();
}

class _AnalysisResultPageState extends ConsumerState<AnalysisResultPage>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoController;
  bool _isSaving = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _initVideo();
  }

  Future<void> _initVideo() async {
    final ctrl = VideoPlayerController.file(dart_io.File(widget.videoPath));
    await ctrl.initialize();
    await ctrl.setPlaybackSpeed(0.25);
    await ctrl.setLooping(true);
    await ctrl.play();
    if (!mounted) return;
    setState(() => _videoController = ctrl);
    _animCtrl.forward();
  }

  void _togglePlay() {
    if (_videoController == null) return;
    _videoController!.value.isPlaying
        ? _videoController!.pause()
        : _videoController!.play();
    setState(() {});
  }

  Future<void> _save({String? linkedSessionId}) async {
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthStateAuthenticated) return;

    final entity = AnalysisResultEntity(
      id: const Uuid().v4(),
      userId: auth.user.id,
      recordedAt: widget.recordedAt,
      speedKmh: widget.analysisData.speedKmh,
      rpmEstimated: widget.analysisData.rpmEstimated,
      fpsUsed: widget.analysisData.fpsUsed,
      videoLocalPath: widget.videoPath,
      linkedSessionId: linkedSessionId,
      createdAt: DateTime.now(),
    );

    await ref.read(analysisRepositoryProvider).save(entity);
    ref.invalidate(analysisHistoryProvider);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _onSavePressed() async {
    if (_isSaving) return;
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthStateAuthenticated) return;

    setState(() => _isSaving = true);

    try {
      final sessions =
          await ref.read(sameDaySessionsProvider(widget.recordedAt).future);
      if (!mounted) return;

      if (sessions.isEmpty) {
        await _save();
        return;
      }

      final picked = await showModalBottomSheet<String?>(
        context: context,
        backgroundColor: AppColors.darkCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _SessionLinkSheet(sessions: sessions),
      );
      if (!mounted) return;
      await _save(linkedSessionId: picked);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.analysisData;
    final isReady =
        _videoController != null && _videoController!.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 영상 전체 배경
          if (isReady)
            GestureDetector(
              onTap: _togglePlay,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white38),
            ),

          // 상단 그라데이션 (앱바 영역)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 하단 그라데이션 (결과 영역)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 340,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.92),
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 상단 바
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
                  // 슬로우모션 뱃지
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.slow_motion_video,
                            color: AppColors.neonOrange, size: 14),
                        const SizedBox(width: 4),
                        Text('0.25×',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          // 일시정지 아이콘
          if (isReady && !_videoController!.value.isPlaying)
            GestureDetector(
              onTap: _togglePlay,
              child: Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 40),
                ),
              ),
            ),

          // 하단 결과 패널
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
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 구속
                        _StatRow(
                          label: '구속',
                          value: data.speedKmh > 0
                              ? data.speedKmh.toStringAsFixed(1)
                              : '—',
                          unit: 'km/h',
                          highlight: true,
                        ),
                        const SizedBox(height: 2),
                        // 구분선
                        Divider(
                          color: Colors.white.withValues(alpha: 0.1),
                          height: 16,
                        ),
                        // RPM
                        _StatRow(
                          label: 'RPM',
                          value: data.rpmEstimated != null
                              ? data.rpmEstimated.toString()
                              : '—',
                          unit: 'rpm',
                          highlight: false,
                          badge: '추정값',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '* AI 측정으로 정확하지 않을 수 있습니다',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white30,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 저장 버튼
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.neonOrange,
                              foregroundColor: Colors.black,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            onPressed: _isSaving ? null : _onSavePressed,
                            child: _isSaving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black54))
                                : Text(
                                    '저장하기',
                                    style: AppTextStyles.bodyLarge.copyWith(
                                        fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
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

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool highlight;
  final String? badge;

  const _StatRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.highlight,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 숫자
        Text(
          value,
          style: TextStyle(
            fontSize: highlight ? 52 : 44,
            fontWeight: FontWeight.w800,
            color: highlight ? AppColors.neonOrange : Colors.white,
            height: 1.0,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(width: 6),
        // 단위 + 라벨
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unit,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: highlight
                      ? AppColors.neonOrange.withValues(alpha: 0.8)
                      : Colors.white60,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white38,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        if (badge != null) ...[
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Text(
              badge!,
              style: const TextStyle(
                  fontSize: 10, color: Colors.white38, letterSpacing: 0.5),
            ),
          ),
        ],
      ],
    );
  }
}

class _SessionLinkSheet extends StatelessWidget {
  final List<SessionEntity> sessions;
  const _SessionLinkSheet({required this.sessions});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('오늘 기록에 연결할까요?',
                style: AppTextStyles.headingSmall),
            const SizedBox(height: 6),
            Text(
              '연결하면 해당 세션에서 볼 분석 결과를 확인할 수 있어요.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ...sessions.map((s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.alleyName ?? '볼링장 미입력',
                      style: AppTextStyles.bodyMedium),
                  subtitle: Text('${s.date.month}/${s.date.day}',
                      style: AppTextStyles.bodySmall),
                  trailing: Icon(PhosphorIconsRegular.link, color: AppColors.neonOrange),
                  onTap: () => Navigator.pop(context, s.id),
                )),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('연결 없이 저장',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary)),
              onTap: () => Navigator.pop(context, null),
            ),
          ],
        ),
      ),
    );
  }
}
