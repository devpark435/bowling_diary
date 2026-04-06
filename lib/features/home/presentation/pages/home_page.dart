import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/home/presentation/providers/home_provider.dart';
import 'package:bowling_diary/features/record/presentation/pages/record_page.dart';
import 'package:bowling_diary/features/record/presentation/pages/session_detail_page.dart';
import 'package:bowling_diary/shared/providers/theme_provider.dart';
import 'package:bowling_diary/shared/widgets/loading_widget.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(colorThemeProvider);
    final recentGames = ref.watch(recentGamesProvider);
    final monthly = ref.watch(monthlySummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bowling Diary'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(recentGamesProvider);
          ref.invalidate(monthlySummaryProvider);
        },
        color: AppColors.neonOrange,
        child: recentGames.when(
          data: (items) {
            if (items.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.sports_baseball, size: 72, color: AppColors.textHint),
                          const SizedBox(height: 20),
                          Text('아직 기록된 게임이 없어요',
                              style: AppTextStyles.headingSmall.copyWith(color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          Text('+ 버튼을 눌러 기록을 추가해보세요',
                              style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  monthly.when(
                    data: (data) => _MonthlySummaryCard(
                      gameCount: data['gameCount'] as int,
                      totalScore: data['totalScore'] as int,
                      highScore: data['highScore'] as int,
                    ),
                    loading: () => _MonthlySummaryCard(gameCount: 0, totalScore: 0, highScore: 0),
                    error: (_, __) => _MonthlySummaryCard(gameCount: 0, totalScore: 0, highScore: 0),
                  ),
                  const SizedBox(height: 24),
                  Text('최근 게임', style: AppTextStyles.headingSmall),
                  const SizedBox(height: 12),
                  SlidableAutoCloseBehavior(
                    child: Column(
                      children: items.map((e) => _RecentGameCard(
                        summary: e,
                        onTap: () => _navigateToDetail(context, e),
                        onEdit: () => _navigateToEdit(context, ref, e),
                        onDelete: () => _confirmDelete(context, ref, e),
                      )).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const LoadingWidget(),
          error: (e, st) {
            debugPrint('최근 게임 로드 에러: $e\n$st');
            return const SizedBox.shrink();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home_fab',
        onPressed: () => context.push('/record'),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _navigateToDetail(BuildContext context, RecentGameSummary summary) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SessionDetailPage(summary: summary)),
    );
  }

  void _navigateToEdit(BuildContext context, WidgetRef ref, RecentGameSummary summary) {
    final s = summary.session;
    final editData = EditSessionData(
      sessionId: s.id,
      date: s.date,
      alleyName: s.alleyName,
      laneNumber: s.laneNumber,
      oilPattern: s.oilPattern,
      memo: s.memo,
      games: summary.games
          .map((g) => EditGameData(totalScore: g.totalScore, ballId: g.ballId))
          .toList(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordPage(editSession: editData)),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, RecentGameSummary summary) async {
    final dateStr = DateFormat('M/d', 'ko').format(summary.session.date);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('기록 삭제'),
        content: Text('$dateStr 기록을 삭제할까요?\n삭제된 기록은 복구할 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('삭제', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      final ds = ref.read(sessionRemoteDataSourceProvider);
      await ds.deleteSession(summary.session.id);
      ref.invalidate(recentGamesProvider);
      ref.invalidate(monthlySummaryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('기록이 삭제되었습니다'), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      debugPrint('기록 삭제 에러: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제에 실패했습니다'), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }
}

class _MonthlySummaryCard extends StatelessWidget {
  final int gameCount;
  final int totalScore;
  final int highScore;

  const _MonthlySummaryCard({
    required this.gameCount,
    required this.totalScore,
    required this.highScore,
  });

  @override
  Widget build(BuildContext context) {
    final avg = gameCount > 0 ? totalScore / gameCount : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('이번 달', style: AppTextStyles.labelLarge),
                Text(DateFormat('yyyy년 M월').format(DateTime.now()), style: AppTextStyles.bodySmall),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryItem(label: '게임 수', value: '$gameCount', color: AppColors.neonOrange),
                _SummaryItem(label: '평균', value: avg.toStringAsFixed(1), color: AppColors.mint),
                _SummaryItem(label: '하이스코어', value: '$highScore', color: AppColors.textPrimary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTextStyles.scoreDisplay.copyWith(fontSize: 24, color: color)),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.labelSmall),
      ],
    );
  }
}

class _RecentGameCard extends StatelessWidget {
  final RecentGameSummary summary;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RecentGameCard({
    required this.summary,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary.session;
    final dateStr = DateFormat('M/d (E)', 'ko').format(s.date);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(s.id),
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.4,
          children: [
            CustomSlidableAction(
              onPressed: (_) => onEdit(),
              backgroundColor: AppColors.mint,
              foregroundColor: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit, size: 22),
                  SizedBox(height: 4),
                  Text('수정', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            CustomSlidableAction(
              onPressed: (_) => onDelete(),
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, size: 22),
                  SizedBox(height: 4),
                  Text('삭제', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(dateStr, style: AppTextStyles.labelLarge),
                          if (summary.ballName != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.neonOrange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(summary.ballName!,
                                  style: TextStyle(color: AppColors.neonOrange, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                      if (summary.games.isNotEmpty)
                        Text(
                          '${summary.totalScore}점 · ${summary.games.length}게임',
                          style: AppTextStyles.labelSmall,
                        ),
                    ],
                  ),
                  if (s.alleyName != null && s.alleyName!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on, color: AppColors.mint, size: 14),
                        const SizedBox(width: 4),
                        Text(s.alleyName!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.mint)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: summary.games.map((g) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _scoreColor(g.totalScore).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _scoreColor(g.totalScore).withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                '${g.totalScore}',
                                style: TextStyle(
                                  color: _scoreColor(g.totalScore),
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            summary.average.toStringAsFixed(1),
                            style: AppTextStyles.scoreDisplay.copyWith(fontSize: 26, color: AppColors.neonOrange),
                          ),
                          Text('평균', style: AppTextStyles.labelSmall),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 200) return AppColors.mint;
    if (score >= 150) return AppColors.neonOrange;
    return AppColors.textSecondary;
  }
}
