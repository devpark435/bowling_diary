import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/app/router/app_router.dart';
import 'package:bowling_diary/app/theme/app_theme.dart';
import 'package:bowling_diary/app/theme/color_themes.dart';
import 'package:bowling_diary/shared/providers/theme_provider.dart';

class BowlingDiaryApp extends ConsumerWidget {
  const BowlingDiaryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final colorTheme = ref.watch(colorThemeProvider);
    final palette = ColorThemes.fromTheme(colorTheme);
    final themeData = AppTheme.fromPalette(palette);
    final themeMode = palette.brightness == Brightness.light
        ? ThemeMode.light
        : ThemeMode.dark;

    return MaterialApp.router(
      title: 'Bowling Diary',
      theme: themeData,
      darkTheme: themeData,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: child,
        );
      },
    );
  }
}
