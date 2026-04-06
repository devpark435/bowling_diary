import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/balls/presentation/providers/ball_provider.dart';
import 'package:bowling_diary/features/home/presentation/providers/home_provider.dart';
import 'package:bowling_diary/features/record/data/models/game_model.dart';
import 'package:bowling_diary/features/record/data/models/session_model.dart';
import 'package:bowling_diary/features/record/presentation/pages/record_page.dart';
import 'package:bowling_diary/shared/providers/theme_provider.dart';

class SessionDetailPage extends ConsumerWidget {
  final RecentGameSummary summary;

  const SessionDetailPage({super.key, required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(colorThemeProvider);
    final s = summary.session;
    final games = summary.games;
    final dateStr = DateFormat('yyyy년 M월 d일 (E)', 'ko').format(s.date);

    return Scaffold(
      appBar: AppBar(
        title: const Text('기록 상세'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            color: AppColors.darkSurface,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: AppColors.darkDivider, width: 0.5),
            ),
            surfaceTintColor: Colors.transparent,
            offset: const Offset(0, 48),
            constraints: const BoxConstraints(minWidth: 160),
            onSelected: (value) {
              if (value == 'edit') {
                _navigateToEdit(context, s, games);
              } else if (value == 'delete') {
                _confirmDelete(context, ref);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                height: 44,
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.mint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.edit_outlined, size: 15, color: AppColors.mint),
                    ),
                    const SizedBox(width: 12),
                    Text('수정하기', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 0.5),
              PopupMenuItem(
                value: 'delete',
                height: 44,
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.delete_outline, size: 15, color: AppColors.error),
                    ),
                    const SizedBox(width: 12),
                    Text('삭제하기', style: TextStyle(color: AppColors.error, fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildScoreSummary(games),
            const SizedBox(height: 24),
            _buildSessionInfo(dateStr, s),
            const SizedBox(height: 24),
            _buildGameList(ref, games),
            if (s.memo != null && s.memo!.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildMemo(s.memo!),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreSummary(List<GameModel> games) {
    final total = summary.totalScore;
    final avg = summary.average;
    final high = games.isEmpty ? 0 : games.map((g) => g.totalScore).reduce((a, b) => a > b ? a : b);
    final low = games.isEmpty ? 0 : games.map((g) => g.totalScore).reduce((a, b) => a < b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            Text(
              avg.toStringAsFixed(1),
              style: AppTextStyles.scoreDisplay.copyWith(
                fontSize: 48,
                color: AppColors.neonOrange,
              ),
            ),
            const SizedBox(height: 4),
            Text('평균 점수', style: AppTextStyles.labelSmall),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatItem(label: '게임 수', value: '${games.length}'),
                _divider(),
                _StatItem(label: '총 점수', value: '$total'),
                _divider(),
                _StatItem(label: '최고', value: '$high', color: AppColors.mint),
                _divider(),
                _StatItem(label: '최저', value: '$low'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 32, color: AppColors.darkDivider);
  }

  Widget _buildSessionInfo(String dateStr, SessionModel s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('세션 정보', style: AppTextStyles.headingSmall),
            const SizedBox(height: 14),
            _InfoRow(icon: Icons.calendar_today, label: '날짜', value: dateStr),
            if (s.alleyName != null && s.alleyName!.isNotEmpty)
              _InfoRow(icon: Icons.location_on, label: '볼링장', value: s.alleyName!, valueColor: AppColors.mint),
            if (s.laneNumber != null)
              _InfoRow(icon: Icons.tag, label: '레인', value: '${s.laneNumber}번'),
            if (s.oilPattern != null && s.oilPattern!.isNotEmpty)
              _InfoRow(icon: Icons.water_drop_outlined, label: '오일 패턴', value: s.oilPattern!),
          ],
        ),
      ),
    );
  }

  Widget _buildGameList(WidgetRef ref, List<GameModel> games) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('게임별 점수', style: AppTextStyles.headingSmall),
        const SizedBox(height: 12),
        ...games.asMap().entries.map((entry) {
          final idx = entry.key;
          final game = entry.value;
          return _GameDetailCard(
            index: idx,
            game: game,
            ref: ref,
          );
        }),
      ],
    );
  }

  Widget _buildMemo(String memo) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note, color: AppColors.textHint, size: 18),
                const SizedBox(width: 8),
                Text('메모', style: AppTextStyles.headingSmall),
              ],
            ),
            const SizedBox(height: 10),
            Text(memo, style: AppTextStyles.bodyMedium),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('기록이 삭제되었습니다'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('기록 삭제 에러: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('삭제에 실패했습니다'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _navigateToEdit(BuildContext context, SessionModel s, List<GameModel> games) {
    final editData = EditSessionData(
      sessionId: s.id,
      date: s.date,
      alleyName: s.alleyName,
      laneNumber: s.laneNumber,
      oilPattern: s.oilPattern,
      memo: s.memo,
      games: games
          .map((g) => EditGameData(totalScore: g.totalScore, ballId: g.ballId))
          .toList(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordPage(editSession: editData)),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.scoreDisplay.copyWith(
            fontSize: 20,
            color: color ?? AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.labelSmall),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textHint, size: 16),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(label, style: AppTextStyles.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameDetailCard extends StatelessWidget {
  final int index;
  final GameModel game;
  final WidgetRef ref;

  const _GameDetailCard({
    required this.index,
    required this.game,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final ballName = _getBallName();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _scoreColor(game.totalScore).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: _scoreColor(game.totalScore),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('게임 ${index + 1}', style: AppTextStyles.labelLarge),
                if (ballName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.sports_baseball, color: AppColors.textHint, size: 12),
                        const SizedBox(width: 4),
                        Text(ballName, style: AppTextStyles.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${game.totalScore}',
            style: AppTextStyles.scoreDisplay.copyWith(
              fontSize: 28,
              color: _scoreColor(game.totalScore),
            ),
          ),
        ],
      ),
    );
  }

  String? _getBallName() {
    if (game.ballId == null) return null;
    final ballsAsync = ref.watch(ballsListProvider);
    return ballsAsync.whenOrNull(
      data: (balls) {
        final match = balls.where((b) => b.id == game.ballId);
        return match.isNotEmpty ? match.first.name : null;
      },
    );
  }

  Color _scoreColor(int score) {
    if (score >= 200) return AppColors.mint;
    if (score >= 150) return AppColors.neonOrange;
    return AppColors.textSecondary;
  }
}
