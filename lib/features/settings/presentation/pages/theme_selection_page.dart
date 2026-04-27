import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/app/theme/color_themes.dart';
import 'package:bowling_diary/shared/providers/theme_provider.dart';

class ThemeSelectionPage extends ConsumerWidget {
  const ThemeSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(colorThemeProvider);
    final currentBrightness = ref.watch(platformBrightnessProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('테마')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '디바이스 다크모드에 따라 자동으로 색상이 변경됩니다.',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ...AppColorTheme.values.map((theme) {
            final isSelected = theme == currentTheme;
            final lightPalette = ColorThemes.previewLight(theme);
            final darkPalette = ColorThemes.previewDark(theme);
            final activePalette = ColorThemes.palette(theme, currentBrightness);

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
                        ? activePalette.primary
                        : AppColors.darkDivider,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // 라이트/다크 미리보기 원 2개
                    Row(
                      children: [
                        _PreviewCircle(palette: lightPalette, label: '라이트'),
                        const SizedBox(width: 8),
                        _PreviewCircle(palette: darkPalette, label: '다크'),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _themeName(theme),
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _themeDesc(theme),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textHint,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_rounded,
                          color: activePalette.primary, size: 20),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _themeName(AppColorTheme theme) {
    switch (theme) {
      case AppColorTheme.blue:
        return '블루';
      case AppColorTheme.cream:
        return '크림';
      case AppColorTheme.lavender:
        return '라벤더';
    }
  }

  String _themeDesc(AppColorTheme theme) {
    switch (theme) {
      case AppColorTheme.blue:
        return '깔끔하고 신뢰감 있는 블루 계열';
      case AppColorTheme.cream:
        return '따뜻하고 아늑한 크림 계열';
      case AppColorTheme.lavender:
        return '부드럽고 감각적인 라벤더 계열';
    }
  }
}

class _PreviewCircle extends StatelessWidget {
  final ColorPalette palette;
  final String label;

  const _PreviewCircle({required this.palette, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.bg, palette.card, palette.primary],
            ),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }
}
