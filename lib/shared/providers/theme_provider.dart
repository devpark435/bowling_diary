import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/color_themes.dart';

final colorThemeProvider =
    StateNotifierProvider<ColorThemeNotifier, AppColorTheme>((ref) {
  return ColorThemeNotifier();
});

class ColorThemeNotifier extends StateNotifier<AppColorTheme> {
  ColorThemeNotifier() : super(AppColorTheme.blue) {
    _load();
  }

  static const _key = 'color_theme_v2';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_key);
    final theme = (idx != null && idx >= 0 && idx < AppColorTheme.values.length)
        ? AppColorTheme.values[idx]
        : AppColorTheme.blue;

    // 앱 시작 시 디바이스 밝기 한 번 감지
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    AppColors.setPalette(ColorThemes.palette(theme, brightness));
    state = theme;
  }

  /// 테마 저장 후 앱을 재시작해야 실제로 적용됨
  Future<void> setTheme(AppColorTheme theme) async {
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, theme.index);
  }
}
