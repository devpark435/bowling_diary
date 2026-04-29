import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/domain/entities/analysis_result_entity.dart';

class AnalysisHistoryCard extends StatelessWidget {
  final AnalysisResultEntity result;
  final VoidCallback? onTap;

  const AnalysisHistoryCard({super.key, required this.result, this.onTap});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('MM.dd').format(result.recordedAt);
    final time = DateFormat('HH:mm').format(result.recordedAt);
    final hasSpeed = result.speedKmh != null;
    final hasRpm = result.rpmEstimated != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 날짜
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  date,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  time,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textHint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            Container(
              width: 1,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: AppColors.darkDivider,
            ),
            // 구속
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (hasSpeed) ...[
                        Text(
                          result.speedKmh!.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.neonOrange,
                            height: 1.0,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3, left: 3),
                          child: Text(
                            'km/h',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.neonOrange.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ] else
                        Text(
                          '측정불가',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textHint,
                            height: 1.0,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasRpm ? '${result.rpmEstimated} RPM' : 'RPM 미측정',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // 우측 아이콘
            Column(
              children: [
                if (result.linkedSessionId != null)
                  Icon(PhosphorIconsRegular.link,
                      color: AppColors.textHint, size: 16),
                const SizedBox(height: 4),
                Icon(PhosphorIconsRegular.caretRight,
                    color: AppColors.textHint, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
