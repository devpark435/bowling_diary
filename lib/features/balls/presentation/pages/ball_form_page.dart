import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/shared/widgets/loading_widget.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';
import 'package:bowling_diary/features/balls/domain/entities/ball_entity.dart';
import 'package:bowling_diary/features/balls/presentation/providers/ball_provider.dart';

class BallFormPage extends ConsumerStatefulWidget {
  const BallFormPage({super.key, this.ball, this.ballId});

  final BallEntity? ball;
  final String? ballId;

  @override
  ConsumerState<BallFormPage> createState() => _BallFormPageState();
}

class _BallFormPageState extends ConsumerState<BallFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _weightController = TextEditingController();
  final _coverstockController = TextEditingController();
  final _rgController = TextEditingController();
  final _differentialController = TextEditingController();
  final _layoutController = TextEditingController();
  String? _imagePath;
  bool _isLoading = false;

  BallEntity? get _ball => widget.ball ?? (widget.ballId != null ? _loadedBall : null);
  BallEntity? _loadedBall;

  @override
  void initState() {
    super.initState();
    _fillFromBall(widget.ball);
  }

  void _fillFromBall(BallEntity? b) {
    if (b != null) {
      _nameController.text = b.name;
      _brandController.text = b.brand ?? '';
      _weightController.text = b.weight?.toString() ?? '';
      _coverstockController.text = b.coverstock ?? '';
      _rgController.text = b.rg?.toString() ?? '';
      _differentialController.text = b.differential?.toString() ?? '';
      _layoutController.text = b.layout ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _weightController.dispose();
    _coverstockController.dispose();
    _rgController.dispose();
    _differentialController.dispose();
    _layoutController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _imagePath = x.path);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(ballRepositoryProvider);
      final now = DateTime.now();
      final currentBall = _ball;
      if (currentBall != null) {
        final ball = currentBall.copyWith(
          name: _nameController.text.trim(),
          brand: _brandController.text.trim().isEmpty ? null : _brandController.text.trim(),
          weight: int.tryParse(_weightController.text.trim()),
          coverstock: _coverstockController.text.trim().isEmpty ? null : _coverstockController.text.trim(),
          rg: double.tryParse(_rgController.text.trim()),
          differential: double.tryParse(_differentialController.text.trim()),
          layout: _layoutController.text.trim().isEmpty ? null : _layoutController.text.trim(),
        );
        await repo.updateBall(ball, imagePath: _imagePath);
      } else {
        final ball = BallEntity(
          id: const Uuid().v4(),
          userId: user.id,
          name: _nameController.text.trim(),
          brand: _brandController.text.trim().isEmpty ? null : _brandController.text.trim(),
          weight: int.tryParse(_weightController.text.trim()),
          coverstock: _coverstockController.text.trim().isEmpty ? null : _coverstockController.text.trim(),
          rg: double.tryParse(_rgController.text.trim()),
          differential: double.tryParse(_differentialController.text.trim()),
          layout: _layoutController.text.trim().isEmpty ? null : _layoutController.text.trim(),
          createdAt: now,
        );
        await repo.createBall(ball, imagePath: _imagePath);
      }
      ref.invalidate(ballsListProvider);
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ballId != null && widget.ball == null) {
      final asyncBall = ref.watch(ballDetailProvider(widget.ballId!));
      return asyncBall.when(
        data: (ball) {
          if (ball == null) return const Scaffold(body: Center(child: Text('볼을 찾을 수 없습니다')));
          if (_loadedBall?.id != ball.id) {
            _loadedBall = ball;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fillFromBall(ball);
              setState(() {});
            });
          }
          return _buildForm(ball);
        },
        loading: () => Scaffold(
          backgroundColor: AppColors.darkBg,
          appBar: AppBar(title: const Text('볼 수정')),
          body: const Center(child: CircularProgressIndicator(color: AppColors.neonOrange)),
        ),
        error: (e, st) {
          debugPrint('볼 상세 로드 에러: $e\n$st');
          return Scaffold(
            backgroundColor: AppColors.darkBg,
            appBar: AppBar(title: const Text('볼 수정')),
            body: const Center(child: Text('데이터를 불러올 수 없습니다', style: TextStyle(color: AppColors.textSecondary))),
          );
        },
      );
    }
    return _buildForm(widget.ball);
  }

  Widget _buildForm(BallEntity? ball) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: Text(ball == null ? '볼 추가' : '볼 수정'),
        actions: [
          if (ball != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('볼 삭제'),
                    content: const Text('이 볼을 삭제할까요?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('삭제', style: TextStyle(color: AppColors.error))),
                    ],
                  ),
                );
                if (ok != true || !mounted) return;
                await ref.read(ballRepositoryProvider).deleteBall(ball.id);
                ref.invalidate(ballsListProvider);
                if (mounted) context.pop();
              },
            ),
        ],
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.darkDivider),
                    ),
                    child: _imagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(_imagePath!),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          )
                        : _ball?.imageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  _ball!.imageUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate, size: 48, color: AppColors.textHint),
                                  const SizedBox(height: 8),
                                  Text('사진 추가', style: AppTextStyles.bodySmall),
                                ],
                              ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('볼 이름 *', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(hintText: '예: 허리케인 프로'),
                  validator: (v) => v == null || v.trim().isEmpty ? '이름을 입력하세요' : null,
                ),
                const SizedBox(height: 16),
                Text('브랜드', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _brandController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(hintText: '예: Storm'),
                ),
                const SizedBox(height: 16),
                Text('무게 (lb)', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _weightController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '예: 14'),
                ),
                const SizedBox(height: 16),
                Text('커버스톡', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _coverstockController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(hintText: '커버스톡 종류'),
                ),
                const SizedBox(height: 16),
                Text('RG', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _rgController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: '예: 2.49'),
                ),
                const SizedBox(height: 16),
                Text('디퍼렌셜', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _differentialController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: '예: 0.050'),
                ),
                const SizedBox(height: 16),
                Text('레이아웃', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _layoutController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: '레이아웃 정보'),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: Text(_ball == null ? '추가하기' : '저장하기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
