import 'package:flutter/material.dart';

enum AppColorTheme { blue, cream, lavender }

class ColorPalette {
  final Color primary;
  final Color secondary;
  final Color primaryGlow;
  final Color secondaryGlow;

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color card;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;

  final Color error;
  final Color success;

  const ColorPalette({
    required this.primary,
    required this.secondary,
    required this.primaryGlow,
    required this.secondaryGlow,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.card,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.error,
    required this.success,
  });
}

class ColorThemes {
  ColorThemes._();

  // ── 블루 ──────────────────────────────────────────────────
  static const blueLight = ColorPalette(
    primary: Color(0xFF3182F6),
    secondary: Color(0xFF00B4D8),
    primaryGlow: Color(0x333182F6),
    secondaryGlow: Color(0x3300B4D8),
    brightness: Brightness.light,
    bg: Color(0xFFF2F6FF),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    divider: Color(0xFFE2EAF5),
    textPrimary: Color(0xFF191F28),
    textSecondary: Color(0xFF6B7684),
    textHint: Color(0xFFB0BAC8),
    error: Color(0xFFF04452),
    success: Color(0xFF05C072),
  );

  static const blueDark = ColorPalette(
    primary: Color(0xFF3182F6),
    secondary: Color(0xFF4DD0E1),
    primaryGlow: Color(0x333182F6),
    secondaryGlow: Color(0x334DD0E1),
    brightness: Brightness.dark,
    bg: Color(0xFF0E1117),
    surface: Color(0xFF161B22),
    card: Color(0xFF1C2333),
    divider: Color(0xFF2D3548),
    textPrimary: Color(0xFFECF0F6),
    textSecondary: Color(0xFF8B95A5),
    textHint: Color(0xFF5A6577),
    error: Color(0xFFFF6B6B),
    success: Color(0xFF69DB7C),
  );

  // ── 크림 ──────────────────────────────────────────────────
  static const creamLight = ColorPalette(
    primary: Color(0xFFFF8A65),
    secondary: Color(0xFF9CDDCE),
    primaryGlow: Color(0x33FF8A65),
    secondaryGlow: Color(0x339CDDCE),
    brightness: Brightness.light,
    bg: Color(0xFFFFFBF5),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFF9F0),
    divider: Color(0xFFEDE4D8),
    textPrimary: Color(0xFF3D2817),
    textSecondary: Color(0xFF8B7355),
    textHint: Color(0xFFBBA88A),
    error: Color(0xFFE8534A),
    success: Color(0xFF5CB88A),
  );

  static const creamDark = ColorPalette(
    primary: Color(0xFFFF8A65),
    secondary: Color(0xFF9CDDCE),
    primaryGlow: Color(0x33FF8A65),
    secondaryGlow: Color(0x339CDDCE),
    brightness: Brightness.dark,
    bg: Color(0xFF1A1208),
    surface: Color(0xFF231A10),
    card: Color(0xFF2C2215),
    divider: Color(0xFF3D3020),
    textPrimary: Color(0xFFF5EFE6),
    textSecondary: Color(0xFFC4A882),
    textHint: Color(0xFF8A7060),
    error: Color(0xFFFF6B5B),
    success: Color(0xFF6DD9A0),
  );

  // ── 라벤더 ────────────────────────────────────────────────
  static const lavenderLight = ColorPalette(
    primary: Color(0xFF7B61FF),
    secondary: Color(0xFFE8A0BF),
    primaryGlow: Color(0x337B61FF),
    secondaryGlow: Color(0x33E8A0BF),
    brightness: Brightness.light,
    bg: Color(0xFFF8F5FF),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    divider: Color(0xFFE8E0F5),
    textPrimary: Color(0xFF1A1625),
    textSecondary: Color(0xFF6B5F80),
    textHint: Color(0xFFA899C0),
    error: Color(0xFFE84057),
    success: Color(0xFF2DB87A),
  );

  static const lavenderDark = ColorPalette(
    primary: Color(0xFF9B72CF),
    secondary: Color(0xFFE8A0BF),
    primaryGlow: Color(0x339B72CF),
    secondaryGlow: Color(0x33E8A0BF),
    brightness: Brightness.dark,
    bg: Color(0xFF13111C),
    surface: Color(0xFF1C1928),
    card: Color(0xFF252236),
    divider: Color(0xFF332F48),
    textPrimary: Color(0xFFF0EBF8),
    textSecondary: Color(0xFFA49BBF),
    textHint: Color(0xFF6B6280),
    error: Color(0xFFFF6B8A),
    success: Color(0xFF7EE8B7),
  );

  /// 테마 + 디바이스 밝기에 맞는 팔레트 반환
  static ColorPalette palette(AppColorTheme theme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    switch (theme) {
      case AppColorTheme.blue:
        return isDark ? blueDark : blueLight;
      case AppColorTheme.cream:
        return isDark ? creamDark : creamLight;
      case AppColorTheme.lavender:
        return isDark ? lavenderDark : lavenderLight;
    }
  }

  /// ThemeSelectionPage 미리보기용 — 라이트 팔레트 반환
  static ColorPalette previewLight(AppColorTheme theme) =>
      palette(theme, Brightness.light);

  /// ThemeSelectionPage 미리보기용 — 다크 팔레트 반환
  static ColorPalette previewDark(AppColorTheme theme) =>
      palette(theme, Brightness.dark);
}
