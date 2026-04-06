import 'package:flutter/material.dart';

enum AppColorTheme {
  dark,
  light,
  lavender,
  tossBlue,
}

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

  static const dark = ColorPalette(
    primary: Color(0xFFFF6B35),
    secondary: Color(0xFF00D9A6),
    primaryGlow: Color(0x33FF6B35),
    secondaryGlow: Color(0x3300D9A6),
    brightness: Brightness.dark,
    bg: Color(0xFF0D0D0D),
    surface: Color(0xFF1A1A1A),
    card: Color(0xFF242424),
    divider: Color(0xFF2E2E2E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFAAAAAA),
    textHint: Color(0xFF666666),
    error: Color(0xFFFF4757),
    success: Color(0xFF2ED573),
  );

  static const light = ColorPalette(
    primary: Color(0xFFFF6B35),
    secondary: Color(0xFF00D9A6),
    primaryGlow: Color(0x33FF6B35),
    secondaryGlow: Color(0x3300D9A6),
    brightness: Brightness.light,
    bg: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFAFAFA),
    divider: Color(0xFFE0E0E0),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF666666),
    textHint: Color(0xFFAAAAAA),
    error: Color(0xFFFF4757),
    success: Color(0xFF2ED573),
  );

  static const lavender = ColorPalette(
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

  static const tossBlue = ColorPalette(
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

  static ColorPalette fromTheme(AppColorTheme theme) {
    switch (theme) {
      case AppColorTheme.dark:
        return dark;
      case AppColorTheme.light:
        return light;
      case AppColorTheme.lavender:
        return lavender;
      case AppColorTheme.tossBlue:
        return tossBlue;
    }
  }
}
