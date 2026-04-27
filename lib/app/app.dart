import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/app/router/app_router.dart';
import 'package:bowling_diary/app/theme/app_theme.dart';
import 'package:bowling_diary/shared/providers/theme_provider.dart';

class BowlingDiaryApp extends ConsumerStatefulWidget {
  const BowlingDiaryApp({super.key});

  @override
  ConsumerState<BowlingDiaryApp> createState() => _BowlingDiaryAppState();
}

class _BowlingDiaryAppState extends ConsumerState<BowlingDiaryApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    ref.read(platformBrightnessProvider.notifier).state = brightness;
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final palette = ref.watch(activePaletteProvider);
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
