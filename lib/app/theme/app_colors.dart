import 'package:flutter/material.dart';
import 'color_themes.dart';

class AppColors {
  AppColors._();

  static ColorPalette _palette = ColorThemes.dark;

  static void setPalette(ColorPalette palette) {
    _palette = palette;
  }

  static ColorPalette get palette => _palette;

  // Accent 색상 (테마에 따라 변경)
  static Color get neonOrange => _palette.primary;
  static Color get mint => _palette.secondary;
  static Color get neonGlow => _palette.primaryGlow;
  static Color get mintGlow => _palette.secondaryGlow;
  static Color get strike => _palette.primary;
  static Color get spare => _palette.secondary;

  // 배경/표면 (테마에 따라 변경)
  static Color get darkBg => _palette.bg;
  static Color get darkSurface => _palette.surface;
  static Color get darkCard => _palette.card;
  static Color get darkDivider => _palette.divider;

  // 텍스트 (테마에 따라 변경)
  static Color get textPrimary => _palette.textPrimary;
  static Color get textSecondary => _palette.textSecondary;
  static Color get textHint => _palette.textHint;

  // 상태 색상
  static Color get error => _palette.error;
  static Color get success => _palette.success;
  static const Color woodLane = Color(0xFF3D2B1F);

  // 라이트 테마 호환 (light 테마 선택 시 사용)
  static Color get lightBg => _palette.bg;
  static Color get lightSurface => _palette.surface;
  static Color get lightCard => _palette.card;
  static Color get lightDivider => _palette.divider;
  static Color get lightTextPrimary => _palette.textPrimary;
  static Color get lightTextSecondary => _palette.textSecondary;
}
