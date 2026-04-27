import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bowling_diary/app/router/app_router.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_theme.dart';
import 'package:bowling_diary/app/theme/color_themes.dart';

/// 앱 시작/재시작 전에 팔레트를 동기적으로 세팅
Future<void> preloadTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final idx = prefs.getInt('color_theme_v2');
  final theme = (idx != null && idx >= 0 && idx < AppColorTheme.values.length)
      ? AppColorTheme.values[idx]
      : AppColorTheme.blue;
  final brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  AppColors.setPalette(ColorThemes.palette(theme, brightness));
}

class AppRestarter extends StatefulWidget {
  const AppRestarter({super.key});

  // ignore: library_private_types_in_public_api
  static _AppRestarterState of(BuildContext context) =>
      context.findAncestorStateOfType<_AppRestarterState>()!;

  @override
  State<AppRestarter> createState() => _AppRestarterState();
}

class _AppRestarterState extends State<AppRestarter> {
  Key _key = UniqueKey();

  /// 팔레트를 먼저 세팅한 뒤 재빌드 — 첫 프레임부터 올바른 색상 적용
  Future<void> restart() async {
    await preloadTheme();
    if (mounted) setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: _key,
      child: const BowlingDiaryApp(),
    );
  }
}

class BowlingDiaryApp extends ConsumerWidget {
  const BowlingDiaryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final palette = AppColors.palette;
    final themeData = AppTheme.fromPalette(palette);
    final themeMode = palette.brightness == Brightness.light
        ? ThemeMode.light
        : ThemeMode.dark;

    return MaterialApp.router(
      title: '핀로그',
      theme: themeData,
      darkTheme: themeData,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: child!,
        );
      },
    );
  }
}
