import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/color_themes.dart';

/// 사용자가 선택한 테마 스타일 (3종)
final colorThemeProvider =
    StateNotifierProvider<ColorThemeNotifier, AppColorTheme>((ref) {
  return ColorThemeNotifier();
});

/// 디바이스 밝기 — app.dart의 WidgetsBindingObserver가 업데이트
final platformBrightnessProvider =
    StateProvider<Brightness>((ref) {
  return WidgetsBinding.instance.platformDispatcher.platformBrightness;
});

/// 현재 활성 팔레트 (테마 + 밝기 조합)
final activePaletteProvider = Provider<ColorPalette>((ref) {
  final theme = ref.watch(colorThemeProvider);
  final brightness = ref.watch(platformBrightnessProvider);
  final palette = ColorThemes.palette(theme, brightness);
  AppColors.setPalette(palette);
  return palette;
});

class ColorThemeNotifier extends StateNotifier<AppColorTheme> {
  ColorThemeNotifier() : super(AppColorTheme.blue) {
    _load();
  }

  static const _key = 'color_theme_v2';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_key);
    if (idx != null && idx >= 0 && idx < AppColorTheme.values.length) {
      state = AppColorTheme.values[idx];
    }
  }

  Future<void> setTheme(AppColorTheme theme) async {
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, theme.index);
  }
}
