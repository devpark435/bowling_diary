import 'package:flutter/material.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_camera_page.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/bowling_pin_character.dart';

class AnalysisGuidePage extends StatefulWidget {
  const AnalysisGuidePage({super.key});

  @override
  State<AnalysisGuidePage> createState() => _AnalysisGuidePageState();
}

class _AnalysisGuidePageState extends State<AnalysisGuidePage> {
  final _controller = PageController();
  int _page = 0;

  static const _steps = [
    _GuideStep(
      emotion: 'normal',
      title: '파울라인 뒤에 서주세요',
      body: '파울라인에서 1~1.5m 뒤에 서서\n레인을 향해 카메라를 준비하세요.',
      icon: Icons.straighten,
    ),
    _GuideStep(
      emotion: 'normal',
      title: '허리 높이로 맞춰주세요',
      body: '카메라를 허리 높이(약 90cm)에 두고\n레인을 따라 수평으로 향해주세요.',
      icon: Icons.height,
    ),
    _GuideStep(
      emotion: 'cheer',
      title: '레인 전체가 보이면 OK!',
      body: '화면에 레인 끝(핀 구역)이\n모두 보이면 준비 완료입니다!',
      icon: Icons.check_circle_outline,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('촬영 가이드')),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _steps.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _GuideStepView(step: _steps[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _steps.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _page == i ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _page == i
                            ? AppColors.neonOrange
                            : AppColors.textHint,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
                    onPressed: () {
                      if (_page < _steps.length - 1) {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AnalysisCameraPage()),
                        );
                      }
                    },
                    child: Text(
                      _page < _steps.length - 1 ? '다음' : '측정 시작',
                      style: AppTextStyles.bodyLarge
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideStep {
  final String emotion;
  final String title;
  final String body;
  final IconData icon;
  const _GuideStep(
      {required this.emotion,
      required this.title,
      required this.body,
      required this.icon});
}

class _GuideStepView extends StatelessWidget {
  final _GuideStep step;
  const _GuideStepView({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BowlingPinCharacter(emotion: step.emotion),
          const SizedBox(height: 32),
          Icon(step.icon, color: AppColors.neonOrange, size: 40),
          const SizedBox(height: 16),
          Text(step.title,
              style: AppTextStyles.headingMedium, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(step.body,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
