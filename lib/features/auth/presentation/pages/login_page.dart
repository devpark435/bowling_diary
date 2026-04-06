import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              _buildLogo(),
              const SizedBox(height: 48),
              _buildTitle(),
              const Spacer(flex: 3),
              _buildLoginButtons(context, ref, authState),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.darkCard,
            border: Border.all(color: AppColors.neonOrange, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonOrange.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            Icons.sports_baseball,
            size: 52,
            color: AppColors.neonOrange,
          ),
        ),
        const SizedBox(height: 20),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppColors.neonOrange, AppColors.mint],
          ).createShader(bounds),
          child: const Text(
            '핀로그',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        Text(
          '나의 볼링 성장 일기장',
          style: AppTextStyles.headingSmall.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '프레임별 기록부터 통계 분석까지\n볼링 실력을 체계적으로 관리하세요',
          style: AppTextStyles.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLoginButtons(
    BuildContext context,
    WidgetRef ref,
    AuthState authState,
  ) {
    final isLoading = authState is AuthStateLoading;

    return Column(
      children: [
        _SocialLoginButton(
          icon: Icons.apple,
          label: 'Apple로 계속하기',
          backgroundColor: Colors.white,
          textColor: Colors.black,
          iconColor: Colors.black,
          isLoading: isLoading,
          onTap: () =>
              ref.read(authNotifierProvider.notifier).signInWithApple(),
        ),
        const SizedBox(height: 12),
        _SocialLoginButton(
          icon: Icons.g_mobiledata,
          label: 'Google로 계속하기',
          backgroundColor: const Color(0xFF4285F4),
          textColor: Colors.white,
          iconColor: Colors.white,
          isLoading: isLoading,
          onTap: () =>
              ref.read(authNotifierProvider.notifier).signInWithGoogle(),
        ),
        if (authState is AuthStateError) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Text(
              authState.message,
              style: TextStyle(color: AppColors.error, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;
  final bool isLoading;
  final VoidCallback onTap;

  const _SocialLoginButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.iconColor,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
