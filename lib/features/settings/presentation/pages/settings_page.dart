import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/app/theme/color_themes.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';
import 'package:bowling_diary/shared/providers/theme_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = user?.isAdmin ?? false;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 프로필 카드
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.darkDivider),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.neonOrange.withValues(alpha: 0.15),
                  child: Text(
                    (user?.nickname ?? '?')[0].toUpperCase(),
                    style: TextStyle(color: AppColors.neonOrange, fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.nickname ?? '닉네임 없음', style: AppTextStyles.labelLarge),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (user?.bowlingStyle != null && user!.bowlingStyle!.isNotEmpty)
                            Text(user.bowlingStyle!, style: AppTextStyles.bodySmall),
                          if (isAdmin) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.neonOrange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('관리자', style: TextStyle(color: AppColors.neonOrange, fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 관리자 섹션
          if (isAdmin) ...[
            Text('관리자', style: AppTextStyles.labelSmall.copyWith(color: AppColors.neonOrange)),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.sports_baseball,
              title: '카탈로그 관리',
              subtitle: '볼링볼 카탈로그 추가/수정/삭제',
              onTap: () => context.push('/admin/catalog'),
            ),
            const SizedBox(height: 24),
          ],

          // 테마 섹션
          Text('테마', style: AppTextStyles.labelSmall),
          const SizedBox(height: 8),
          _ColorThemeSelector(ref: ref),
          const SizedBox(height: 24),

          // 일반 섹션
          Text('일반', style: AppTextStyles.labelSmall),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.person_outline,
            title: '프로필 수정',
            subtitle: '닉네임, 투구 스타일 변경',
            onTap: () => context.push('/profile-setup'),
          ),
          const SizedBox(height: 32),

          // 계정 섹션
          Text('계정', style: AppTextStyles.labelSmall),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: BorderSide(color: AppColors.darkDivider),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('로그아웃'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () => _confirmDeleteAccount(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('회원 탈퇴'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text('정말 탈퇴하시겠습니까?\n모든 기록과 데이터가 삭제되며 복구할 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('탈퇴하기', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (firstConfirm != true || !context.mounted) return;

    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('마지막 확인'),
        content: const Text('삭제된 데이터는 절대 복구할 수 없습니다.\n정말로 진행하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('삭제 및 탈퇴', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (secondConfirm != true || !context.mounted) return;

    try {
      await ref.read(authNotifierProvider.notifier).deleteAccount();
    } catch (e) {
      debugPrint('회원 탈퇴 에러: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('탈퇴 처리 중 오류가 발생했습니다'), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.darkDivider,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 20),
        ),
        title: Text(title, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: AppTextStyles.labelSmall),
        trailing: Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
        onTap: onTap,
      ),
    );
  }
}

class _ColorThemeSelector extends StatelessWidget {
  final WidgetRef ref;

  const _ColorThemeSelector({required this.ref});

  @override
  Widget build(BuildContext context) {
    final currentTheme = ref.watch(colorThemeProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: AppColorTheme.values.map((theme) {
          final palette = ColorThemes.fromTheme(theme);
          final isSelected = theme == currentTheme;
          return GestureDetector(
            onTap: () => ref.read(colorThemeProvider.notifier).setTheme(theme),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? palette.primary : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [palette.primary, palette.secondary],
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _themeName(theme),
                  style: TextStyle(
                    color: isSelected ? AppColors.textPrimary : AppColors.textHint,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _themeName(AppColorTheme theme) {
    switch (theme) {
      case AppColorTheme.dark:
        return '다크';
      case AppColorTheme.light:
        return '라이트';
      case AppColorTheme.lavender:
        return '라벤더';
      case AppColorTheme.tossBlue:
        return '블루';
    }
  }
}
