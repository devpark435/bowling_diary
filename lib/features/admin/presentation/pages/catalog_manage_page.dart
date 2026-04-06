import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/shared/widgets/loading_widget.dart';
import 'package:bowling_diary/features/balls/domain/entities/catalog_ball_entity.dart';
import 'package:bowling_diary/features/balls/presentation/providers/catalog_provider.dart';

class CatalogManagePage extends ConsumerStatefulWidget {
  const CatalogManagePage({super.key});

  @override
  ConsumerState<CatalogManagePage> createState() => _CatalogManagePageState();
}

class _CatalogManagePageState extends ConsumerState<CatalogManagePage> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncBalls = _searchQuery.isEmpty
        ? ref.watch(catalogAllBallsProvider)
        : ref.watch(catalogSearchProvider(_searchQuery));

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('카탈로그 관리'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '볼 이름 또는 브랜드 검색',
                prefixIcon: Icon(Icons.search, color: AppColors.textHint),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: AppColors.textHint, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          Expanded(
            child: asyncBalls.when(
              data: (balls) {
                if (balls.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isEmpty ? '카탈로그가 비어있습니다' : '"$_searchQuery" 검색 결과 없음',
                      style: AppTextStyles.bodySmall,
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: balls.length,
                  itemBuilder: (context, i) => _CatalogAdminTile(
                    ball: balls[i],
                    onEdit: () => _openForm(context, ball: balls[i]),
                    onDelete: () => _confirmDelete(context, balls[i]),
                  ),
                );
              },
              loading: () => const LoadingWidget(),
              error: (e, st) {
                debugPrint('카탈로그 로드 에러: $e\n$st');
                return Center(child: Text('데이터를 불러올 수 없습니다', style: TextStyle(color: AppColors.textSecondary)));
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'catalog_manage_fab',
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openForm(BuildContext context, {CatalogBallEntity? ball}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CatalogFormPage(ball: ball),
      ),
    ).then((result) {
      if (result == true) {
        ref.invalidate(catalogAllBallsProvider);
        ref.invalidate(catalogBrandsProvider);
      }
    });
  }

  Future<void> _confirmDelete(BuildContext context, CatalogBallEntity ball) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('카탈로그 볼 삭제'),
        content: Text('${ball.brand} ${ball.name}을(를) 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('삭제', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final ds = ref.read(catalogDataSourceProvider);
      await ds.deleteCatalogBall(ball.id);
      ref.invalidate(catalogAllBallsProvider);
      ref.invalidate(catalogBrandsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제되었습니다'), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      debugPrint('카탈로그 삭제 에러: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제에 실패했습니다'), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }
}

class _CatalogAdminTile extends StatelessWidget {
  final CatalogBallEntity ball;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CatalogAdminTile({required this.ball, required this.onEdit, required this.onDelete});

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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.darkDivider,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ball.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    ball.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(Icons.sports_baseball, color: AppColors.textHint, size: 22),
                  ),
                )
              : Icon(Icons.sports_baseball, color: AppColors.textHint, size: 22),
        ),
        title: Text(ball.name, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '${ball.brand}${ball.coverstock != null ? " · ${ball.coverstock}" : ""}',
          style: AppTextStyles.labelSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ball.imageUrl == null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('이미지 없음', style: TextStyle(color: AppColors.error, fontSize: 10)),
              ),
            const SizedBox(width: 4),
            IconButton(icon: Icon(Icons.edit, color: AppColors.mint, size: 20), onPressed: onEdit),
            IconButton(icon: Icon(Icons.delete_outline, color: AppColors.error, size: 20), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class _CatalogFormPage extends ConsumerStatefulWidget {
  final CatalogBallEntity? ball;

  const _CatalogFormPage({this.ball});

  @override
  ConsumerState<_CatalogFormPage> createState() => _CatalogFormPageState();
}

class _CatalogFormPageState extends ConsumerState<_CatalogFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _brandController = TextEditingController();
  final _nameController = TextEditingController();
  final _coverstockController = TextEditingController();
  final _coreTypeController = TextEditingController();
  final _rgController = TextEditingController();
  final _differentialController = TextEditingController();
  final _yearController = TextEditingController();
  String? _imagePath;
  String? _existingImageUrl;
  bool _isLoading = false;

  bool get _isEditing => widget.ball != null;

  @override
  void initState() {
    super.initState();
    if (widget.ball != null) {
      final b = widget.ball!;
      _brandController.text = b.brand;
      _nameController.text = b.name;
      _coverstockController.text = b.coverstock ?? '';
      _coreTypeController.text = b.coreType ?? '';
      _rgController.text = b.rg?.toString() ?? '';
      _differentialController.text = b.differential?.toString() ?? '';
      _yearController.text = b.releasedYear?.toString() ?? '';
      _existingImageUrl = b.imageUrl;
    }
  }

  @override
  void dispose() {
    _brandController.dispose();
    _nameController.dispose();
    _coverstockController.dispose();
    _coreTypeController.dispose();
    _rgController.dispose();
    _differentialController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 600);
    if (x != null) setState(() => _imagePath = x.path);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final ds = ref.read(catalogDataSourceProvider);

      String? imageUrl = _existingImageUrl;
      if (_imagePath != null) {
        final ballId = widget.ball?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
        imageUrl = await ds.uploadCatalogImage(ballId, _imagePath!);
      }

      if (_isEditing) {
        await ds.updateCatalogBall(
          id: widget.ball!.id,
          brand: _brandController.text.trim(),
          name: _nameController.text.trim(),
          coverstock: _coverstockController.text.trim().isEmpty ? null : _coverstockController.text.trim(),
          coreType: _coreTypeController.text.trim().isEmpty ? null : _coreTypeController.text.trim(),
          rg: double.tryParse(_rgController.text.trim()),
          differential: double.tryParse(_differentialController.text.trim()),
          imageUrl: imageUrl,
          releasedYear: int.tryParse(_yearController.text.trim()),
        );
      } else {
        await ds.insertCatalogBall(
          brand: _brandController.text.trim(),
          name: _nameController.text.trim(),
          coverstock: _coverstockController.text.trim().isEmpty ? null : _coverstockController.text.trim(),
          coreType: _coreTypeController.text.trim().isEmpty ? null : _coreTypeController.text.trim(),
          rg: double.tryParse(_rgController.text.trim()),
          differential: double.tryParse(_differentialController.text.trim()),
          imageUrl: imageUrl,
          releasedYear: int.tryParse(_yearController.text.trim()),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('카탈로그 저장 에러: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장에 실패했습니다'), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(title: Text(_isEditing ? '카탈로그 볼 수정' : '카탈로그 볼 추가')),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 이미지 선택
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.darkDivider),
                    ),
                    child: _imagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(File(_imagePath!), fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                          )
                        : _existingImageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  _existingImageUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
                                ),
                              )
                            : _buildImagePlaceholder(),
                  ),
                ),
                const SizedBox(height: 24),
                // 브랜드
                Text('브랜드 *', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _brandController,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(hintText: '예: Storm'),
                  validator: (v) => v == null || v.trim().isEmpty ? '브랜드를 입력하세요' : null,
                ),
                const SizedBox(height: 16),
                // 볼 이름
                Text('볼 이름 *', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(hintText: '예: Phaze V'),
                  validator: (v) => v == null || v.trim().isEmpty ? '이름을 입력하세요' : null,
                ),
                const SizedBox(height: 16),
                // 커버스톡
                Text('커버스톡', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _coverstockController,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(hintText: '예: R3S Hybrid'),
                ),
                const SizedBox(height: 16),
                // 코어 타입
                Text('코어 타입', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _coreTypeController,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(hintText: '예: Velocity Core'),
                ),
                const SizedBox(height: 16),
                // RG / Diff / Year
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('RG', style: AppTextStyles.labelLarge),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _rgController,
                            style: TextStyle(color: AppColors.textPrimary),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(hintText: '2.48'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Diff', style: AppTextStyles.labelLarge),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _differentialController,
                            style: TextStyle(color: AppColors.textPrimary),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(hintText: '0.053'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('출시년도', style: AppTextStyles.labelLarge),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _yearController,
                            style: TextStyle(color: AppColors.textPrimary),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(hintText: '2024'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: Text(_isEditing ? '수정하기' : '추가하기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate, size: 48, color: AppColors.textHint),
        const SizedBox(height: 8),
        Text('볼 이미지 추가', style: AppTextStyles.bodySmall),
        const SizedBox(height: 4),
        Text('탭하여 갤러리에서 선택', style: AppTextStyles.labelSmall),
      ],
    );
  }
}
