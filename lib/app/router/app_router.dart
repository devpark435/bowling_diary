import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.darkDivider, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: navigationShell.currentIndex,
          onTap: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: '홈',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart),
              label: '통계',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.videocam_outlined),
              activeIcon: Icon(Icons.videocam),
              label: '분석',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: '마이페이지',
            ),
          ],
        ),
      ),
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
