import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_guide_page.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_trim_page.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/bowling_pin_character.dart';

class AnalysisSelectionPage extends StatelessWidget {
  const AnalysisSelectionPage({super.key});

  Future<void> _pickFromGallery(BuildContext context) async {
    final video = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (video == null || !context.mounted) return;

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AnalysisTrimPage(videoPath: video.path, fps: 60),
      ),
    );
  }

  void _goToRecord(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AnalysisGuidePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('볼 분석')),
      body: Padding(
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
                onPressed: () => _goToRecord(context),
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
                onPressed: () => _pickFromGallery(context),
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
