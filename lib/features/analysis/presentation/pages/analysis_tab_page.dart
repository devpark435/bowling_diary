import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_detail_page.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_selection_page.dart';
import 'package:bowling_diary/features/analysis/presentation/providers/analysis_provider.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/analysis_history_card.dart';
import 'package:bowling_diary/shared/widgets/loading_widget.dart';

class AnalysisTabPage extends ConsumerWidget {
  const AnalysisTabPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(analysisHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('분석')),
      body: history.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_outlined,
                      size: 72, color: AppColors.textHint),
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
            itemBuilder: (_, i) => AnalysisHistoryCard(
              result: items[i],
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => AnalysisDetailPage(result: items[i]),
                ),
              ),
            ),
          );
        },
        loading: () => const LoadingWidget(),
        error: (e, _) => Center(child: Text('불러오기 실패: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.neonOrange,
        onPressed: () => Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute(
                builder: (_) => const AnalysisSelectionPage()))
            .then((_) => ref.invalidate(analysisHistoryProvider)),
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}
