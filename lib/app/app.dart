import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/app/router/app_router.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_theme.dart';

/// ProviderScope를 포함한 앱 전체 재시작 위젯
class AppRestarter extends StatefulWidget {
  const AppRestarter({super.key});

  static _AppRestarterState of(BuildContext context) =>
      context.findAncestorStateOfType<_AppRestarterState>()!;

  @override
  State<AppRestarter> createState() => _AppRestarterState();
}

class _AppRestarterState extends State<AppRestarter> {
  Key _key = UniqueKey();

  /// 호출 시 ProviderScope 포함 전체 재빌드 → 테마 재로드
  void restart() => setState(() => _key = UniqueKey());

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
