import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/data/services/video_analysis_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_guide_page.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_result_page.dart';
import 'package:bowling_diary/features/analysis/presentation/providers/analysis_provider.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/analysis_history_card.dart';
import 'package:bowling_diary/shared/widgets/loading_widget.dart';

class AnalysisTabPage extends ConsumerStatefulWidget {
  const AnalysisTabPage({super.key});

  @override
  ConsumerState<AnalysisTabPage> createState() => _AnalysisTabPageState();
}

class _AnalysisTabPageState extends ConsumerState<AnalysisTabPage> {
  final _frameExtractor = VideoFrameExtractorService();
  final _analysisService = VideoAnalysisService();
  bool _isAnalyzing = false;

  void _onFabTapped() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.neonOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.videocam, color: AppColors.neonOrange),
                ),
                title: Text('즉시 촬영하기', style: AppTextStyles.bodyLarge),
                subtitle: Text('카메라로 투구 영상을 녹화합니다',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                onTap: () {
                  Navigator.pop(context);
                  _goToRecord();
                },
              ),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.neonOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.photo_library_outlined, color: AppColors.neonOrange),
                ),
                title: Text('갤러리에서 가져오기', style: AppTextStyles.bodyLarge),
                subtitle: Text('저장된 영상으로 분석합니다',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromGallery();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _goToRecord() {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => const AnalysisGuidePage()))
        .then((_) => ref.invalidate(analysisHistoryProvider));
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

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => AnalysisResultPage(
            analysisData: analysisData,
            videoPath: video.path,
            recordedAt: DateTime.now(),
          ),
        ),
      );
      ref.invalidate(analysisHistoryProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('영상 분석 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(analysisHistoryProvider);

    if (_isAnalyzing) {
      return Scaffold(
        appBar: AppBar(title: const Text('볼 분석')),
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
      appBar: AppBar(title: const Text('볼 분석')),
      body: history.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_outlined, size: 72, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text('아직 측정 기록이 없어요',
                      style: AppTextStyles.headingSmall
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Text('+ 버튼을 눌러 첫 측정을 시작해보세요',
                      style: AppTextStyles.bodySmall),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: items.length,
            itemBuilder: (_, i) => AnalysisHistoryCard(result: items[i]),
          );
        },
        loading: () => const LoadingWidget(),
        error: (e, _) => Center(child: Text('불러오기 실패: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.neonOrange,
        onPressed: _onFabTapped,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}
