import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/color_themes.dart';
import 'package:bowling_diary/shared/providers/theme_provider.dart';

class ThemeSelectionPage extends ConsumerWidget {
  const ThemeSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(colorThemeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('테마')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: AppColorTheme.values.map((theme) {
          final palette = ColorThemes.fromTheme(theme);
          final isSelected = theme == currentTheme;

          return GestureDetector(
            onTap: () => ref.read(colorThemeProvider.notifier).setTheme(theme),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? palette.primary
                      : AppColors.darkDivider,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  // 테마 미리보기 원
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          palette.bg,
                          palette.primary,
                          palette.secondary,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _themeName(theme),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (isSelected)
                    Icon(Icons.check_rounded,
                        color: palette.primary, size: 20),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _themeName(AppColorTheme theme) {
    switch (theme) {
      case AppColorTheme.dark:
        return '다크';
      case AppColorTheme.cream:
        return '크림';
      case AppColorTheme.lavender:
        return '라벤더';
      case AppColorTheme.tossBlue:
        return '블루';
    }
  }
}
