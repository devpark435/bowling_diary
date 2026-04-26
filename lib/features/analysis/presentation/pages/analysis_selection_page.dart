import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/data/services/gemini_analysis_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_analysis_service.dart';
import 'package:bowling_diary/features/analysis/data/services/video_frame_extractor_service.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_guide_page.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_result_page.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/analysis_loading_widget.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/bowling_pin_character.dart';

class AnalysisSelectionPage extends StatefulWidget {
  const AnalysisSelectionPage({super.key});

  @override
  State<AnalysisSelectionPage> createState() => _AnalysisSelectionPageState();
}

class _AnalysisSelectionPageState extends State<AnalysisSelectionPage> {
  final _frameExtractor = VideoFrameExtractorService();
  final _geminiService = GeminiAnalysisService();
  final _fallbackService = VideoAnalysisService();
  bool _isAnalyzing = false;
  String? _analyzingVideoPath;

  Future<void> _pickFromGallery() async {
    final video = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (video == null || !mounted) return;

    setState(() {
      _isAnalyzing = true;
      _analyzingVideoPath = video.path;
    });
    try {
      final result = await _frameExtractor.extract(video.path);
      final analysisData = await _analyzeWithFallback(result.frames, result.originalFps);

      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AnalysisResultPage(
            analysisData: analysisData,
            videoPath: video.path,
            recordedAt: DateTime.now(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('영상 분석 실패: $e')),
      );
    }
  }

  Future<AnalysisData> _analyzeWithFallback(
      List<dynamic> frames, int originalFps) async {
    try {
      return await _geminiService.analyze(
        frames.cast(),
        originalFps,
      );
    } on GeminiQuotaExceededException {
      debugPrint('[Analysis] Gemini 할당량 초과 → 로컬 분석으로 fallback');
      return _fallbackService.analyzeImages(frames.cast(), originalFps);
    } on GeminiApiException catch (e) {
      debugPrint('[Analysis] Gemini 오류 → fallback: $e');
      return _fallbackService.analyzeImages(frames.cast(), originalFps);
    }
  }

  void _goToRecord() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AnalysisGuidePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('볼 분석')),
      body: _isAnalyzing
          ? AnalysisLoadingWidget(videoPath: _analyzingVideoPath)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(),
                  const BowlingPinCharacter(emotion: 'normal'),
                  const SizedBox(height: 32),
                  Text(
                    '어떻게 분석할까요?',
                    style: AppTextStyles.headingMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '투구 영상을 직접 촬영하거나\n갤러리에서 불러와 분석해보세요',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.neonOrange,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _goToRecord,
                      icon: const Icon(Icons.videocam),
                      label: Text(
                        '즉시 촬영하기',
                        style: AppTextStyles.bodyLarge
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.neonOrange,
                        side: BorderSide(color: AppColors.neonOrange),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        '갤러리에서 가져오기',
                        style: AppTextStyles.bodyLarge
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}
