import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/shared/providers/theme_provider.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';
import 'package:bowling_diary/features/settings/presentation/pages/theme_selection_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = user?.isAdmin ?? false;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _ProfileHeader(user: user, isAdmin: isAdmin)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 관리자
                  if (isAdmin) ...[
                    _SectionLabel('관리자'),
                    const SizedBox(height: 8),
                    _MenuItem(
                      icon: PhosphorIconsRegular.bowlingBall,
                      label: '카탈로그 관리',
                      onTap: () => context.push('/admin/catalog'),
                      accent: true,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 내 정보
                  _SectionLabel('내 정보'),
                  const SizedBox(height: 8),
                  _MenuGroup(items: [
                    _MenuItem(
                      icon: PhosphorIconsRegular.bowlingBall,
                      label: '내 볼',
                      onTap: () => context.push('/balls'),
                    ),
                    _MenuItem(
                      icon: PhosphorIconsRegular.pencilSimple,
                      label: '프로필 수정',
                      onTap: () => context.push('/profile-setup'),
                      isLast: true,
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // 앱 설정
                  _SectionLabel('앱 설정'),
                  const SizedBox(height: 8),
                  _MenuGroup(items: [
                    _MenuItem(
                      icon: PhosphorIconsRegular.palette,
                      label: '테마',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ThemeSelectionPage()),
                      ),
                      isLast: true,
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // 계정
                  _SectionLabel('계정'),
                  const SizedBox(height: 8),
                  _MenuGroup(items: [
                    _MenuItem(
                      icon: PhosphorIconsRegular.signOut,
                      label: '로그아웃',
                      onTap: () =>
                          ref.read(authNotifierProvider.notifier).signOut(),
                    ),
                    _MenuItem(
                      icon: PhosphorIconsRegular.trash,
                      label: '회원 탈퇴',
                      onTap: () => _confirmDeleteAccount(context, ref),
                      destructive: true,
                      isLast: true,
                    ),
                  ]),
                  const SizedBox(height: 40),

                  Center(child: _AppVersionInfo()),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.darkCard,
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
    if (first != true || !context.mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('마지막 확인'),
        content: const Text('삭제된 데이터는 절대 복구할 수 없습니다.\n정말로 진행하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('삭제 및 탈퇴',
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (second != true || !context.mounted) return;

    try {
      await ref.read(authNotifierProvider.notifier).deleteAccount();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('탈퇴 처리 중 오류가 발생했습니다'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }
}

// ─── 프로필 헤더 ─────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final dynamic user;
  final bool isAdmin;

  const _ProfileHeader({required this.user, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.neonOrange.withValues(alpha: 0.2),
            AppColors.darkBg,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '마이페이지',
                style: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                user?.nickname ?? '닉네임 없음',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              if (user?.bowlingStyle != null &&
                  (user!.bowlingStyle as String).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  user!.bowlingStyle as String,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
              if (isAdmin) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.neonOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'ADMIN',
                    style: TextStyle(
                      color: AppColors.neonOrange,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 공통 위젯 ────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textHint,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
      ),
    );
  }
}

/// 항목들을 하나의 카드로 묶어주는 그룹
class _MenuGroup extends StatelessWidget {
  final List<_MenuItem> items;
  const _MenuGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: items),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool accent;
  final bool isLast;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.accent = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppColors.error
        : accent
            ? AppColors.neonOrange
            : AppColors.textPrimary;

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (!destructive)
                  Icon(PhosphorIconsRegular.caretRight,
                      color: AppColors.textHint, size: 18),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 50,
            color: AppColors.darkDivider,
          ),
      ],
    );
  }
}

class _AppVersionInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (_, snapshot) {
        final version = snapshot.data?.version ?? '-';
        final build = snapshot.data?.buildNumber ?? '-';
        return Text(
          '핀로그 v$version ($build)',
          style: TextStyle(color: AppColors.textHint, fontSize: 12),
        );
      },
    );
  }
}
