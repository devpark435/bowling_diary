import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';

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
                    style: const TextStyle(color: AppColors.neonOrange, fontSize: 22, fontWeight: FontWeight.w800),
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
                              child: const Text('관리자', style: TextStyle(color: AppColors.neonOrange, fontSize: 10, fontWeight: FontWeight.w700)),
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

          // 로그아웃
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('로그아웃'),
            ),
          ),
        ],
      ),
    );
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
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: AppTextStyles.labelSmall),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
        onTap: onTap,
      ),
    );
  }
}
