import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Center(
        child: Text(
          '통계',
          style: TextStyle(color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
