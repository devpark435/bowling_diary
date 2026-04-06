import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/home/presentation/providers/home_provider.dart';
import 'package:bowling_diary/shared/widgets/loading_widget.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentGames = ref.watch(recentGamesProvider);
    final monthly = ref.watch(monthlySummaryProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('Bowling Diary'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(recentGamesProvider);
          ref.invalidate(monthlySummaryProvider);
        },
        color: AppColors.neonOrange,
        child: SingleChildScrollView(
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
              recentGames.when(
                data: (items) {
                  if (items.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.darkDivider),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.sports_baseball, size: 64, color: AppColors.textHint),
                          const SizedBox(height: 16),
                          Text('아직 기록된 게임이 없어요', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          Text('기록하기 탭에서 첫 게임을 시작해보세요!', style: AppTextStyles.bodySmall),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: items.map((e) => _RecentGameCard(summary: e)).toList(),
                  );
                },
                loading: () => const LoadingWidget(),
                error: (e, st) {
                  debugPrint('최근 게임 로드 에러: $e\n$st');
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/record'),
        child: const Icon(Icons.add),
      ),
    );
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

  const _RecentGameCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary.session;
    final dateStr = DateFormat('M/d (E)', 'ko').format(s.date);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(dateStr, style: AppTextStyles.labelLarge),
                  if (summary.ballName != null)
                    Text(summary.ballName!, style: AppTextStyles.bodySmall),
                ],
              ),
              if (s.alleyName != null && s.alleyName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(s.alleyName!, style: AppTextStyles.bodySmall),
              ],
              const SizedBox(height: 8),
              Row(
                children: summary.games.asMap().entries.map((e) {
                  final idx = e.key + 1;
                  final g = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('게임$idx: ${g.totalScore}', style: AppTextStyles.scoreFrame),
                  );
                }).toList(),
              ),
              if (summary.games.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('총 ${summary.totalScore}점 (평균 ${summary.average.toStringAsFixed(1)})', style: AppTextStyles.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
