import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/shared/widgets/loading_widget.dart';
import 'package:bowling_diary/features/stats/presentation/providers/stats_provider.dart';

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(statsPeriodProvider);
    final asyncStats = ref.watch(statsDataProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(title: const Text('통계')),
      body: Column(
        children: [
          _PeriodSelector(period: period, ref: ref),
          Expanded(
            child: asyncStats.when(
              data: (stats) {
                if (stats.gameCount == 0) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bar_chart, size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text('아직 기록된 게임이 없어요', style: AppTextStyles.headingSmall.copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        Text('홈에서 게임을 기록해보세요', style: AppTextStyles.bodySmall),
                      ],
                    ),
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SummaryCards(stats: stats),
                      const SizedBox(height: 24),
                      _ScoreTrendChart(stats: stats),
                      const SizedBox(height: 24),
                      _ScoreDistributionChart(stats: stats),
                      const SizedBox(height: 32),
                    ],
                  ),
                );
              },
              loading: () => const LoadingWidget(),
              error: (e, st) {
                debugPrint('통계 로드 에러: $e\n$st');
                return const Center(child: Text('데이터를 불러올 수 없습니다', style: TextStyle(color: AppColors.textSecondary)));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final StatsPeriod period;
  final WidgetRef ref;

  const _PeriodSelector({required this.period, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _PeriodChip(label: '1개월', isSelected: period == StatsPeriod.oneMonth, onTap: () => ref.read(statsPeriodProvider.notifier).state = StatsPeriod.oneMonth),
          const SizedBox(width: 8),
          _PeriodChip(label: '3개월', isSelected: period == StatsPeriod.threeMonths, onTap: () => ref.read(statsPeriodProvider.notifier).state = StatsPeriod.threeMonths),
          const SizedBox(width: 8),
          _PeriodChip(label: '전체', isSelected: period == StatsPeriod.all, onTap: () => ref.read(statsPeriodProvider.notifier).state = StatsPeriod.all),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeriodChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.neonOrange : AppColors.darkCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.neonOrange : AppColors.darkDivider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final StatsData stats;

  const _SummaryCards({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _StatCard(title: '총 게임', value: '${stats.gameCount}', unit: '게임', color: AppColors.textPrimary)),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(title: '평균 점수', value: stats.average.toStringAsFixed(1), unit: '점', color: AppColors.neonOrange)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _StatCard(title: '최고 점수', value: '${stats.highScore}', unit: '점', color: AppColors.mint)),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(title: '최저 점수', value: '${stats.lowScore}', unit: '점', color: AppColors.error)),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final Color color;

  const _StatCard({required this.title, required this.value, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.labelSmall),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: AppTextStyles.scoreDisplay.copyWith(fontSize: 24, color: color)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(unit, style: AppTextStyles.labelSmall),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreTrendChart extends StatelessWidget {
  final StatsData stats;

  const _ScoreTrendChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    final dailyAvg = stats.dailyAverages;
    if (dailyAvg.isEmpty) return const SizedBox.shrink();

    final spots = dailyAvg.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.score.toDouble());
    }).toList();

    final double maxY = (stats.highScore + 20).toDouble().clamp(0.0, 300.0);
    final double minY = (stats.lowScore - 20).toDouble().clamp(0.0, 300.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('점수 추이', style: AppTextStyles.headingSmall),
          const SizedBox(height: 4),
          Text('일별 평균 점수', style: AppTextStyles.labelSmall),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 30,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColors.darkDivider,
                    strokeWidth: 0.8,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 30,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(color: AppColors.textHint, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: dailyAvg.length > 10 ? (dailyAvg.length / 5).ceilToDouble() : 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= dailyAvg.length) return const SizedBox.shrink();
                        return Text(
                          DateFormat('M/d').format(dailyAvg[idx].date),
                          style: const TextStyle(color: AppColors.textHint, fontSize: 9),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minY: minY,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: AppColors.neonOrange,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: dailyAvg.length <= 20,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 3,
                        color: AppColors.neonOrange,
                        strokeWidth: 1.5,
                        strokeColor: AppColors.darkCard,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.neonOrange.withValues(alpha: 0.25),
                          AppColors.neonOrange.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.darkSurface,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final idx = spot.x.toInt();
                        final date = idx < dailyAvg.length ? DateFormat('M/d').format(dailyAvg[idx].date) : '';
                        return LineTooltipItem(
                          '$date\n${spot.y.toInt()}점',
                          const TextStyle(color: AppColors.neonOrange, fontWeight: FontWeight.w700, fontSize: 12),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreDistributionChart extends StatelessWidget {
  final StatsData stats;

  const _ScoreDistributionChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    final dist = stats.scoreDistribution;
    final maxVal = dist.values.fold<int>(0, (a, b) => a > b ? a : b);
    if (maxVal == 0) return const SizedBox.shrink();

    final labels = dist.keys.toList();
    final values = dist.values.toList();

    final barColors = [
      AppColors.error.withValues(alpha: 0.7),
      AppColors.error.withValues(alpha: 0.5),
      AppColors.neonOrange.withValues(alpha: 0.5),
      AppColors.neonOrange.withValues(alpha: 0.7),
      AppColors.neonOrange,
      AppColors.mint.withValues(alpha: 0.7),
      AppColors.mint,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('점수 분포', style: AppTextStyles.headingSmall),
          const SizedBox(height: 4),
          Text('점수 구간별 게임 수', style: AppTextStyles.labelSmall),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxVal + 1).toDouble(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColors.darkDivider,
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        if (value == value.roundToDouble() && value >= 0) {
                          return Text(value.toInt().toString(), style: const TextStyle(color: AppColors.textHint, fontSize: 10));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[idx],
                            style: const TextStyle(color: AppColors.textHint, fontSize: 8),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: values.asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.toDouble(),
                        color: barColors[e.key % barColors.length],
                        width: 20,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  );
                }).toList(),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.darkSurface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${labels[group.x]}\n${rod.toY.toInt()}게임',
                        const TextStyle(color: AppColors.neonOrange, fontWeight: FontWeight.w700, fontSize: 12),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
