import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/features/auth/presentation/pages/login_page.dart';
import 'package:bowling_diary/features/auth/presentation/pages/onboarding_page.dart';
import 'package:bowling_diary/features/auth/presentation/pages/profile_setup_page.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';
import 'package:bowling_diary/features/home/presentation/pages/home_page.dart';
import 'package:bowling_diary/features/record/presentation/pages/record_page.dart';
import 'package:bowling_diary/features/stats/presentation/pages/stats_page.dart';
import 'package:bowling_diary/features/balls/presentation/pages/ball_form_page.dart';
import 'package:bowling_diary/features/balls/presentation/pages/balls_page.dart';
import 'package:bowling_diary/features/settings/presentation/pages/settings_page.dart';
import 'package:bowling_diary/features/admin/presentation/pages/catalog_manage_page.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_tab_page.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_guide_page.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_camera_page.dart';
import 'package:bowling_diary/features/analysis/presentation/pages/analysis_result_page.dart';
import 'package:bowling_diary/features/analysis/data/services/video_analysis_service.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final location = state.matchedLocation;

      if (authState is AuthStateInitial || authState is AuthStateLoading) {
        return '/splash';
      }

      final isLoginRoute = location == '/login' || location == '/onboarding';
      final isProfileSetup = location == '/profile-setup';

      if (authState is AuthStateUnauthenticated) {
        if (!isLoginRoute) return '/login';
        return null;
      }

      if (authState is AuthStateNeedsProfile) {
        if (!isProfileSetup) return '/profile-setup';
        return null;
      }

      if (authState is AuthStateAuthenticated) {
        if (isLoginRoute) return '/';
        return null;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (context, state) => const ProfileSetupPage(),
      ),
      GoRoute(
        path: '/record',
        builder: (context, state) => const RecordPage(),
      ),
      GoRoute(
        path: '/ball/add',
        builder: (context, state) => const BallFormPage(),
      ),
      GoRoute(
        path: '/ball/edit/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return BallFormPage(ballId: id);
        },
      ),
      GoRoute(
        path: '/balls',
        builder: (context, state) => const BallsPage(),
      ),
      GoRoute(
        path: '/admin/catalog',
        builder: (context, state) => const CatalogManagePage(),
      ),
      // 분석 플로우 — 바텀 네비게이션 없음
      GoRoute(
        path: '/analysis/guide',
        builder: (context, state) => const AnalysisGuidePage(),
      ),
      GoRoute(
        path: '/analysis/camera',
        builder: (context, state) => const AnalysisCameraPage(),
      ),
      GoRoute(
        path: '/analysis/result',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AnalysisResultPage(
            analysisData: extra['analysisData'] as AnalysisData,
            videoPath: extra['videoPath'] as String,
            recordedAt: extra['recordedAt'] as DateTime,
          );
        },
      ),
      StatefulShellRoute(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        navigatorContainerBuilder: (context, navigationShell, children) {
          return _AnimatedTabContainer(
            currentIndex: navigationShell.currentIndex,
            children: children,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/analysis',
                builder: (context, state) => const AnalysisTabPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class ScaffoldWithNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _CustomNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

class _CustomNavBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const _CustomNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              _NavItem(
                icon: PhosphorIconsRegular.house,
                activeIcon: PhosphorIconsFill.house,
                label: '홈',
                isActive: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: PhosphorIconsRegular.chartBar,
                activeIcon: PhosphorIconsFill.chartBar,
                label: '통계',
                isActive: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavItem(
                icon: PhosphorIconsRegular.videoCamera,
                activeIcon: PhosphorIconsFill.videoCamera,
                label: '분석',
                isActive: currentIndex == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: PhosphorIconsRegular.user,
                activeIcon: PhosphorIconsFill.user,
                label: '마이페이지',
                isActive: currentIndex == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.neonOrange : AppColors.textHint;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.neonOrange.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                color: color,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  letterSpacing: isActive ? 0.1 : 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedTabContainer extends StatefulWidget {
  final int currentIndex;
  final List<Widget> children;

  const _AnimatedTabContainer({
    required this.currentIndex,
    required this.children,
  });

  @override
  State<_AnimatedTabContainer> createState() => _AnimatedTabContainerState();
}

class _AnimatedTabContainerState extends State<_AnimatedTabContainer>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _fades;
  late final List<Animation<double>> _scales;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.children.length,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 260),
        value: i == widget.currentIndex ? 1.0 : 0.0,
      ),
    );
    _fades = _controllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();
    _scales = _controllers
        .map((c) => Tween<double>(begin: 0.97, end: 1.0)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeOut)))
        .toList();
  }

  @override
  void didUpdateWidget(_AnimatedTabContainer old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _controllers[old.currentIndex].reverse();
      _controllers[widget.currentIndex].forward();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: List.generate(widget.children.length, (i) {
        return FadeTransition(
          opacity: _fades[i],
          child: ScaleTransition(
            scale: _scales[i],
            child: IgnorePointer(
              ignoring: i != widget.currentIndex,
              child: widget.children[i],
            ),
          ),
        );
      }),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: AppColors.neonOrange),
      ),
    );
  }
}
