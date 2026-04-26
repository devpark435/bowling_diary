import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/domain/entities/analysis_result_entity.dart';

class AnalysisHistoryCard extends StatelessWidget {
  final AnalysisResultEntity result;

  const AnalysisHistoryCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MM.dd HH:mm').format(result.recordedAt);
    final rpmText = result.rpmEstimated != null
        ? '${result.rpmEstimated} RPM (추정)'
        : 'RPM 측정 불가';

    return Card(
      color: AppColors.darkCard,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.sports_baseball, color: AppColors.neonOrange, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateStr,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                    '${result.speedKmh.toStringAsFixed(1)} km/h',
                    style: AppTextStyles.headingSmall
                        .copyWith(color: AppColors.textPrimary),
                  ),
                  Text(rpmText,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (result.linkedSessionId != null)
              Icon(Icons.link, color: AppColors.neonOrange, size: 18),
          ],
        ),
      ),
    );
  }
}
