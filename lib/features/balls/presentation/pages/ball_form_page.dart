import 'dart:async';
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
import 'package:bowling_diary/features/balls/domain/entities/catalog_ball_entity.dart';
import 'package:bowling_diary/features/balls/presentation/providers/ball_provider.dart';
import 'package:bowling_diary/features/balls/presentation/providers/catalog_provider.dart';

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
  String? _catalogImageUrl;
  bool _isLoading = false;
  bool _isEditing = false;

  BallEntity? get _ball => widget.ball ?? (widget.ballId != null ? _loadedBall : null);
  BallEntity? _loadedBall;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.ball != null || widget.ballId != null;
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

  void _fillFromCatalog(CatalogBallEntity catalog) {
    setState(() {
      _nameController.text = catalog.name;
      _brandController.text = catalog.brand;
      _coverstockController.text = catalog.coverstock ?? '';
      _rgController.text = catalog.rg?.toString() ?? '';
      _differentialController.text = catalog.differential?.toString() ?? '';
      _catalogImageUrl = catalog.imageUrl;
    });
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
          imageUrl: _catalogImageUrl,
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

  void _openCatalogSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _CatalogSearchSheet(
          scrollController: scrollController,
          onSelected: (catalog) {
            Navigator.pop(context);
            _fillFromCatalog(catalog);
          },
        ),
      ),
    );
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
                // 카탈로그 검색 버튼 (새 볼 추가 시에만)
                if (!_isEditing) ...[
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _openCatalogSearch,
                      icon: const Icon(Icons.search, size: 20),
                      label: const Text('카탈로그에서 볼 검색'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.neonOrange,
                        side: const BorderSide(color: AppColors.neonOrange),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text('또는 직접 입력', style: AppTextStyles.bodySmall),
                  ),
                  const SizedBox(height: 16),
                ],
                // 이미지
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
                        : _catalogImageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  _catalogImageUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
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
                                : _buildImagePlaceholder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text('볼 이름 *', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(hintText: '예: Phaze V'),
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
                            style: const TextStyle(color: AppColors.textPrimary),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(hintText: '예: 2.49'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('디퍼렌셜', style: AppTextStyles.labelLarge),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _differentialController,
                            style: const TextStyle(color: AppColors.textPrimary),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(hintText: '예: 0.050'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('레이아웃', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _layoutController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: '예: 50° x 4½" x 30°',
                  ),
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

  Widget _buildImagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate, size: 48, color: AppColors.textHint),
        const SizedBox(height: 8),
        Text('사진 추가', style: AppTextStyles.bodySmall),
      ],
    );
  }
}

class _CatalogSearchSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final void Function(CatalogBallEntity) onSelected;

  const _CatalogSearchSheet({
    required this.scrollController,
    required this.onSelected,
  });

  @override
  ConsumerState<_CatalogSearchSheet> createState() => _CatalogSearchSheetState();
}

class _CatalogSearchSheetState extends ConsumerState<_CatalogSearchSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 핸들
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.darkDivider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('볼링볼 카탈로그', style: AppTextStyles.headingSmall),
        ),
        // 검색 바
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '볼 이름 또는 브랜드 검색',
              prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.textHint, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        const SizedBox(height: 12),
        // 검색 결과
        Expanded(
          child: _query.isEmpty
              ? _buildBrandList()
              : _buildSearchResults(),
        ),
      ],
    );
  }

  Widget _buildBrandList() {
    final asyncBrands = ref.watch(catalogBrandsProvider);
    return asyncBrands.when(
      data: (brands) {
        if (brands.isEmpty) {
          return const Center(child: Text('카탈로그가 비어있습니다', style: TextStyle(color: AppColors.textSecondary)));
        }
        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: brands.length,
          itemBuilder: (context, i) {
            final brand = brands[i];
            return ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.neonOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.sports_baseball, color: AppColors.neonOrange, size: 20),
              ),
              title: Text(brand, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
              onTap: () {
                _searchController.text = brand;
                setState(() => _query = brand);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.neonOrange)),
      error: (e, st) {
        debugPrint('브랜드 로드 에러: $e\n$st');
        return const Center(child: Text('데이터를 불러올 수 없습니다', style: TextStyle(color: AppColors.textSecondary)));
      },
    );
  }

  Widget _buildSearchResults() {
    final asyncResults = ref.watch(catalogSearchProvider(_query));
    return asyncResults.when(
      data: (balls) {
        if (balls.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 48, color: AppColors.textHint),
                const SizedBox(height: 12),
                Text('"$_query" 검색 결과가 없습니다', style: AppTextStyles.bodySmall),
                const SizedBox(height: 8),
                Text('직접 입력하여 추가할 수 있습니다', style: AppTextStyles.labelSmall),
              ],
            ),
          );
        }
        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: balls.length,
          itemBuilder: (context, i) {
            final ball = balls[i];
            return _CatalogBallTile(
              ball: ball,
              onTap: () => widget.onSelected(ball),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.neonOrange)),
      error: (e, st) {
        debugPrint('카탈로그 검색 에러: $e\n$st');
        return const Center(child: Text('검색 중 오류가 발생했습니다', style: TextStyle(color: AppColors.textSecondary)));
      },
    );
  }
}

class _CatalogBallTile extends StatelessWidget {
  final CatalogBallEntity ball;
  final VoidCallback onTap;

  const _CatalogBallTile({required this.ball, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkDivider),
        ),
        child: Row(
          children: [
            // 이미지 또는 플레이스홀더
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.darkDivider,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ball.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        ball.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.sports_baseball, color: AppColors.neonOrange, size: 24),
                      ),
                    )
                  : const Icon(Icons.sports_baseball, color: AppColors.neonOrange, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ball.name,
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(ball.brand, style: AppTextStyles.bodySmall),
                  if (ball.coverstock != null) ...[
                    const SizedBox(height: 4),
                    Text(ball.coverstock!, style: AppTextStyles.labelSmall),
                  ],
                ],
              ),
            ),
            // 스펙 요약
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (ball.rg != null)
                  Text('RG ${ball.rg}', style: AppTextStyles.labelSmall.copyWith(color: AppColors.mint)),
                if (ball.differential != null)
                  Text('Diff ${ball.differential}', style: AppTextStyles.labelSmall.copyWith(color: AppColors.neonOrange)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
