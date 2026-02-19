import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  String _selectedStyle = 'conventional';
  bool _isLoading = false;

  final _styles = [
    ('conventional', '컨벤셔널', '엄지, 중지, 약지 모두 사용'),
    ('thumbless', '썸리스', '엄지를 사용하지 않음'),
    ('two_hand', '투핸드', '두 손으로 투구'),
  ];

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('프로필 설정'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text('닉네임', style: AppTextStyles.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _nicknameController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: '닉네임을 입력하세요',
                ),
                maxLength: 20,
              ),
              const SizedBox(height: 32),
              Text('볼링 스타일', style: AppTextStyles.labelLarge),
              const SizedBox(height: 12),
              ...(_styles.map((style) => _buildStyleTile(style))),
              const Spacer(),
              SizedBox(
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
                      : const Text('완료'),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
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
              const Icon(Icons.check_circle, color: AppColors.neonOrange, size: 20),
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
      if (mounted) context.go('/');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
