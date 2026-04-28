import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';

class ProfileSetupPage extends ConsumerStatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  ConsumerState<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends ConsumerState<ProfileSetupPage> {
  final _nicknameController = TextEditingController();
  String _selectedStyle = 'classic';
  bool _isLoading = false;
  bool _isEditMode = false;

  final _styles = [
    ('classic', '클래식', '기본 원핸드 투구'),
    ('classic_wrist', '아대 클래식', '손목 보호대를 착용한 원핸드'),
    ('two_hand', '투핸드', '두 손으로 투구'),
    ('thumbless', '덤리스', '엄지를 넣지 않는 원핸드'),
    ('tweener', '트위너', '스트로커와 크랭커의 중간'),
    ('cranker', '크랭커', '높은 회전과 강한 훅'),
  ];

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    if (user != null && user.isProfileComplete) {
      _isEditMode = true;
      _nicknameController.text = user.nickname ?? '';
      final saved = user.bowlingStyle ?? 'classic';
      _selectedStyle = saved == 'conventional' ? 'classic' : saved;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? '프로필 수정' : '프로필 설정'),
        automaticallyImplyLeading: _isEditMode,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    if (!_isEditMode) ...[
                      Text('환영합니다!', style: AppTextStyles.headingLarge),
                      const SizedBox(height: 8),
                      Text('프로필을 설정하고 시작하세요', style: AppTextStyles.bodySmall),
                      const SizedBox(height: 32),
                    ],
                    Text('닉네임', style: AppTextStyles.labelLarge),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nicknameController,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: '닉네임을 입력하세요',
                      ),
                      maxLength: 20,
                    ),
                    const SizedBox(height: 32),
                    Text('볼링 스타일', style: AppTextStyles.labelLarge),
                    const SizedBox(height: 12),
                    ...(_styles.map((style) => _buildStyleTile(style))),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_isEditMode ? '저장' : '완료'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleTile((String, String, String) style) {
    final (value, label, description) = style;
    final isSelected = _selectedStyle == value;

    return GestureDetector(
      onTap: () => setState(() => _selectedStyle = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.neonOrange.withValues(alpha: 0.1) : AppColors.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.neonOrange : AppColors.darkDivider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: isSelected ? AppColors.neonOrange : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(description, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            if (isSelected)
              Icon(PhosphorIconsFill.checkCircle, color: AppColors.neonOrange, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('닉네임을 입력해주세요')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).updateProfile(
        nickname: nickname,
        bowlingStyle: _selectedStyle,
      );
      if (mounted) {
        if (_isEditMode) {
          context.pop();
        } else {
          context.go('/');
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
