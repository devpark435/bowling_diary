import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_detail_page.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_selection_page.dart';
import 'package:bowling_diary/features/analysis/presentation/providers/analysis_provider.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/analysis_history_card.dart';
import 'package:bowling_diary/shared/widgets/loading_widget.dart';

class AnalysisTabPage extends ConsumerStatefulWidget {
  const AnalysisTabPage({super.key});

  @override
  ConsumerState<AnalysisTabPage> createState() => _AnalysisTabPageState();
}

class _AnalysisTabPageState extends ConsumerState<AnalysisTabPage> {
  // 로컬에서 먼저 제거한 ID 목록 — Supabase 응답 전까지 화면에서 숨김
  final Set<String> _deletedIds = {};

  Future<void> _delete(String id) async {
    setState(() => _deletedIds.add(id));
    try {
      await ref.read(analysisRepositoryProvider).delete(id);
      ref.invalidate(analysisHistoryProvider);
    } catch (_) {
      // 실패 시 복원
      setState(() => _deletedIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(analysisHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('분석')),
      body: history.when(
        data: (allItems) {
          final items =
              allItems.where((e) => !_deletedIds.contains(e.id)).toList();

          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIconsRegular.videoCamera,
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
            itemBuilder: (_, i) {
              final item = items[i];
              return Dismissible(
                key: ValueKey(item.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Colors.white, size: 24),
                ),
                confirmDismiss: (_) => showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: AppColors.darkCard,
                    title: const Text('기록 삭제'),
                    content: const Text('이 분석 기록을 삭제할까요?'),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(false),
                        child: Text('취소',
                            style:
                                TextStyle(color: AppColors.textSecondary)),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(true),
                        child: Text('삭제',
                            style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                ),
                onDismissed: (_) => _delete(item.id),
                child: AnalysisHistoryCard(
                  result: item,
                  onTap: () =>
                      Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => AnalysisDetailPage(result: item),
                    ),
                  ),
                ),
              );
            },
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
        child: const Icon(PhosphorIconsBold.plus, color: Colors.black),
      ),
    );
  }
}
