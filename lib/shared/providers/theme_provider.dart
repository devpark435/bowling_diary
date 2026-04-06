import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/color_themes.dart';

final colorThemeProvider = StateNotifierProvider<ColorThemeNotifier, AppColorTheme>((ref) {
  return ColorThemeNotifier();
});

final themeProvider = Provider<ThemeMode>((ref) {
  final colorTheme = ref.watch(colorThemeProvider);
  final palette = ColorThemes.fromTheme(colorTheme);
  return palette.brightness == Brightness.light ? ThemeMode.light : ThemeMode.dark;
});

class ColorThemeNotifier extends StateNotifier<AppColorTheme> {
  ColorThemeNotifier() : super(AppColorTheme.dark) {
    _load();
  }

  static const _key = 'color_theme';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_key) ?? 0;
    if (idx >= 0 && idx < AppColorTheme.values.length) {
      final theme = AppColorTheme.values[idx];
      AppColors.setPalette(ColorThemes.fromTheme(theme));
      state = theme;
    }
  }

  Future<void> setTheme(AppColorTheme theme) async {
    AppColors.setPalette(ColorThemes.fromTheme(theme));
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, theme.index);
  }
}
