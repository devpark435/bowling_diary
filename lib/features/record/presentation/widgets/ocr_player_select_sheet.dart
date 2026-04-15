import 'package:flutter/material.dart';

import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/record/domain/entities/ocr_result.dart';

/// 다중 플레이어 선택 바텀시트
/// OCR 결과에서 여러 플레이어가 감지된 경우 사용자가 본인을 선택
Future<OcrPlayerResult?> showOcrPlayerSelectSheet(
  BuildContext context,
  List<OcrPlayerResult> players,
) async {
  return showModalBottomSheet<OcrPlayerResult>(
    context: context,
    backgroundColor: AppColors.darkCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _OcrPlayerSelectSheet(players: players),
  );
}

class _OcrPlayerSelectSheet extends StatelessWidget {
  final List<OcrPlayerResult> players;

  const _OcrPlayerSelectSheet({required this.players});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.people_outline, color: AppColors.neonOrange, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '플레이어 선택',
                    style: AppTextStyles.headingSmall,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '여러 플레이어가 감지되었습니다. 본인의 이름을 선택해주세요.',
              style: AppTextStyles.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: AppColors.darkDivider, height: 1),
          ...players.map((player) => _PlayerTile(player: player)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final OcrPlayerResult player;

  const _PlayerTile({required this.player});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.neonOrange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            player.playerName.isNotEmpty ? player.playerName[0] : '?',
            style: TextStyle(
              color: AppColors.neonOrange,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      title: Text(
        player.playerName,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Row(
        children: [
          if (player.totalScore != null) ...[
            Text(
              '${player.totalScore}점',
              style: TextStyle(
                color: AppColors.neonOrange,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            '${player.completedFrameCount}/10 프레임',
            style: AppTextStyles.bodySmall,
          ),
          if (!player.isGameComplete) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.mint.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '진행중',
                style: TextStyle(
                  color: AppColors.mint,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
      onTap: () => Navigator.pop(context, player),
    );
  }
}
