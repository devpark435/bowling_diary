import 'dart:io' as dart_io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _AnalysisResultPageState extends ConsumerState<AnalysisResultPage> {
  VideoPlayerController? _videoController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
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
  }

  Future<void> _save({String? linkedSessionId}) async {
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthStateAuthenticated) return;
    setState(() => _isSaving = true);

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
    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _onSavePressed() async {
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthStateAuthenticated) return;

    final sessions =
        await ref.read(sameDaySessionsProvider(widget.recordedAt).future);
    if (!mounted) return;

    if (sessions.isEmpty) {
      await _save();
      return;
    }

    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (_) => _SessionLinkSheet(sessions: sessions),
    );
    if (!mounted) return;
    await _save(linkedSessionId: picked);
  }

  void _togglePlay() {
    if (_videoController == null) return;
    _videoController!.value.isPlaying
        ? _videoController!.pause()
        : _videoController!.play();
    setState(() {});
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.analysisData;
    final isVideoReady =
        _videoController != null && _videoController!.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('측정 결과'),
      ),
      body: Column(
        children: [
          // 영상 + 오버레이
          Expanded(
            child: GestureDetector(
              onTap: _togglePlay,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 영상
                  if (isVideoReady)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _videoController!.value.size.width,
                        height: _videoController!.value.size.height,
                        child: VideoPlayer(_videoController!),
                      ),
                    )
                  else
                    const Center(
                      child: CircularProgressIndicator(),
                    ),

                  // 하단 그라데이션
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // 재생/일시정지 중앙 아이콘 (일시정지 시만)
                  if (isVideoReady && !_videoController!.value.isPlaying)
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow,
                            color: Colors.white, size: 40),
                      ),
                    ),

                  // 슬로우모션 뱃지
                  Positioned(
                    top: 12,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '0.25× 슬로우모션',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.white70),
                      ),
                    ),
                  ),

                  // 구속 · RPM 오버레이 (하단)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 20,
                    child: Row(
                      children: [
                        _StatOverlayCard(
                          label: '구속',
                          value: data.speedKmh > 0
                              ? data.speedKmh.toStringAsFixed(1)
                              : '—',
                          unit: 'km/h',
                          isMain: true,
                        ),
                        const SizedBox(width: 12),
                        _StatOverlayCard(
                          label: 'RPM',
                          value: data.rpmEstimated != null
                              ? data.rpmEstimated.toString()
                              : '—',
                          unit: 'rpm',
                          isMain: false,
                          note: '추정값',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 저장 버튼
          SafeArea(
            top: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonOrange,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isSaving ? null : _onSavePressed,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('저장',
                          style: AppTextStyles.bodyLarge
                              .copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatOverlayCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool isMain;
  final String? note;

  const _StatOverlayCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.isMain,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMain
                ? AppColors.neonOrange.withValues(alpha: 0.6)
                : Colors.white24,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style:
                  AppTextStyles.bodySmall.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isMain ? 32 : 28,
                    fontWeight: FontWeight.bold,
                    color: isMain ? AppColors.neonOrange : Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    unit,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: Colors.white60),
                  ),
                ),
              ],
            ),
            if (note != null)
              Text(
                note!,
                style: AppTextStyles.bodySmall
                    .copyWith(color: Colors.white38, fontSize: 10),
              ),
          ],
        ),
      ),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('오늘 기록에 연결할까요?', style: AppTextStyles.headingSmall),
            const SizedBox(height: 8),
            Text(
              '연결하면 해당 세션에서 볼 분석 결과를 확인할 수 있어요.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ...sessions.map((s) => ListTile(
                  title: Text(s.alleyName ?? '볼링장 미입력',
                      style: AppTextStyles.bodyMedium),
                  subtitle: Text('${s.date.month}/${s.date.day}',
                      style: AppTextStyles.bodySmall),
                  trailing: const Icon(Icons.link),
                  onTap: () => Navigator.pop(context, s.id),
                )),
            ListTile(
              title: Text('연결 없이 독립 저장',
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
