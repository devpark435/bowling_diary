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
    final videoCtrl =
        VideoPlayerController.file(dart_io.File(widget.videoPath));
    await videoCtrl.initialize();
    await videoCtrl.setPlaybackSpeed(0.25);
    await videoCtrl.setLooping(true);
    if (!mounted) return;
    setState(() => _videoController = videoCtrl);
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

    final sessions = await ref.read(
      sameDaySessionsProvider(widget.recordedAt).future,
    );

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

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.analysisData;

    return Scaffold(
      appBar: AppBar(title: const Text('측정 결과')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_videoController != null &&
                _videoController!.value.isInitialized)
              Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () {
                          _videoController!.value.isPlaying
                              ? _videoController!.pause()
                              : _videoController!.play();
                          setState(() {});
                        },
                        icon: Icon(
                          _videoController!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: AppColors.neonOrange,
                        ),
                      ),
                      Text('0.25× 슬로우모션',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              )
            else
              const Center(child: CircularProgressIndicator()),
            _ResultTile(
              label: '구속',
              value: data.speedKmh > 0
                  ? '${data.speedKmh.toStringAsFixed(1)} km/h'
                  : '측정 불가',
              isMain: true,
            ),
            const SizedBox(height: 12),
            _ResultTile(
              label: 'RPM (추정값)',
              value: data.rpmEstimated != null
                  ? '${data.rpmEstimated} RPM'
                  : '측정 불가',
              isMain: false,
              note: 'RPM은 후방 촬영 특성상 추정값입니다',
            ),
            const SizedBox(height: 8),
            Text(
                '분석 프레임: ${data.framesAnalyzed}개 / ${data.fpsUsed}fps',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textHint)),
            const SizedBox(height: 32),
            SizedBox(
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
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final String label;
  final String value;
  final bool isMain;
  final String? note;

  const _ResultTile(
      {required this.label,
      required this.value,
      required this.isMain,
      this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: isMain
                ? AppTextStyles.headingLarge
                    .copyWith(color: AppColors.neonOrange)
                : AppTextStyles.headingSmall
                    .copyWith(color: AppColors.textPrimary),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textHint)),
          ],
        ],
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
            Text('연결하면 해당 세션에서 볼 분석 결과를 확인할 수 있어요.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
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
