import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/presentation/providers/calibration_providers.dart';
import 'package:bowling_diary/features/analysis/presentation/viewmodels/calibration_list_view_model.dart';

/// 캘리브레이션 프로파일 목록 및 관리 화면
class CalibrationListPage extends ConsumerStatefulWidget {
  const CalibrationListPage({super.key});

  @override
  ConsumerState<CalibrationListPage> createState() => _CalibrationListPageState();
}

class _CalibrationListPageState extends ConsumerState<CalibrationListPage> {
  bool _extracting = false;

  @override
  void initState() {
    super.initState();
    // 화면 진입 시 목록 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final repoAsync = ref.read(calibrationRepoProvider);
      if (repoAsync.hasValue) {
        ref.read(calibrationListVMProvider.notifier).reload();
      }
    });
  }

  /// 영상 선택 → 첫 프레임 추출 → 캘리브레이션 화면 이동
  Future<void> _createNew() async {
    final video = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (video == null || !mounted) return;

    setState(() => _extracting = true);
    try {
      final imagePath = await _extractFirstFrame(video.path);
      if (imagePath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('영상에서 프레임 추출에 실패했습니다'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      // 캘리브레이션 화면으로 이동 후 결과를 받아 목록 갱신
      final result = await context.push(
        '/analysis/calibration',
        extra: {'imagePath': imagePath},
      );
      if (result != null && mounted) {
        ref.read(calibrationListVMProvider.notifier).reload();
      }
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  /// ffmpeg로 영상 첫 프레임을 JPG 파일로 추출한다.
  Future<String?> _extractFirstFrame(String videoPath) async {
    final tempDir = await getTemporaryDirectory();
    final outPath = '${tempDir.path}/calib_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final session = await FFmpegKit.execute(
      '-i "$videoPath" -frames:v 1 -q:v 2 "$outPath"',
    );
    final rc = await session.getReturnCode();
    if (rc?.isValueSuccess() ?? false) return outPath;
    return null;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CalibrationListViewModel vm,
    CalibrationProfile profile,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('프로파일 삭제'),
        content: Text('"${profile.name}"을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('삭제', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await vm.delete(profile.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(calibrationRepoProvider);

    // 저장소 로드 중
    if (repoAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 저장소 로드 실패
    if (repoAsync.hasError) {
      return Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: _buildAppBar(),
        body: Center(
          child: Text(
            '저장소 초기화 실패: ${repoAsync.error}',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
          ),
        ),
      );
    }

    final state = ref.watch(calibrationListVMProvider);
    final vm = ref.read(calibrationListVMProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: _buildAppBar(),
      body: _extracting
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    '영상에서 프레임을 추출하는 중...',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.profiles.isEmpty
                  ? _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: state.profiles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final profile = state.profiles[i];
                        final isDefault = profile.id == state.defaultId;
                        return _ProfileCard(
                          profile: profile,
                          isDefault: isDefault,
                          onSetDefault: () => vm.setDefault(profile.id),
                          onDelete: () =>
                              _confirmDelete(context, vm, profile),
                        );
                      },
                    ),
      floatingActionButton: _extracting
          ? null
          : FloatingActionButton.extended(
              onPressed: _createNew,
              backgroundColor: AppColors.neonOrange,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add),
              label: const Text(
                '새로 만들기',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.darkCard,
      title: Text(
        '분석 캘리브레이션',
        style: AppTextStyles.headingSmall.copyWith(color: AppColors.textPrimary),
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    );
  }
}

// ─── 빈 상태 ──────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.crosshair,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 20),
            Text(
              '캘리브레이션 프로파일이 없습니다. 영상을 선택해서 시작하세요.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 프로파일 카드 ────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final CalibrationProfile profile;
  final bool isDefault;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  const _ProfileCard({
    required this.profile,
    required this.isDefault,
    required this.onSetDefault,
    required this.onDelete,
  });

  String _viewpointLabel(CameraViewpoint v) {
    switch (v) {
      case CameraViewpoint.backRight:
        return '뒤편 우측';
      case CameraViewpoint.backLeft:
        return '뒤편 좌측';
      case CameraViewpoint.sideRight:
        return '측면 우측';
      case CameraViewpoint.sideLeft:
        return '측면 좌측';
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSetDefault,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: isDefault
              ? Border.all(color: AppColors.neonOrange, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            // 기본 표시 아이콘
            Icon(
              isDefault ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
              color:
                  isDefault ? AppColors.neonOrange : AppColors.textHint,
              size: 22,
            ),
            const SizedBox(width: 14),
            // 프로파일 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _viewpointLabel(profile.viewpoint),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // 삭제 버튼
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                PhosphorIconsRegular.trash,
                color: AppColors.error,
                size: 20,
              ),
              tooltip: '삭제',
            ),
          ],
        ),
      ),
    );
  }
}
