import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/presentation/providers/calibration_providers.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/calibration_overlay.dart';

const _stepGuides = [
  '① 파울라인 왼쪽 끝을 탭하세요',
  '② 파울라인 오른쪽 끝을 탭하세요',
  '③ 핀 쪽 레인 오른쪽 끝을 탭하세요',
  '④ 핀 쪽 레인 왼쪽 끝을 탭하세요',
];

class CalibrationPage extends ConsumerStatefulWidget {
  final String referenceImagePath;
  const CalibrationPage({super.key, required this.referenceImagePath});

  @override
  ConsumerState<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends ConsumerState<CalibrationPage> {
  Size? _imageSize;
  bool _imageLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    try {
      final bytes = await File(widget.referenceImagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (!mounted) return;
      if (decoded == null) {
        setState(() => _imageLoadFailed = true);
        return;
      }
      setState(() {
        _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _imageLoadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(calibrationVMProvider.notifier);
    final state = ref.watch(calibrationVMProvider);
    final repoAsync = ref.watch(calibrationRepoProvider);

    if (repoAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (repoAsync.hasError) {
      return Scaffold(
        body: Center(child: Text('저장소 초기화 실패: ${repoAsync.error}', style: AppTextStyles.bodyMedium)),
      );
    }
    if (_imageLoadFailed) {
      return Scaffold(
        body: Center(child: Text('이미지를 불러올 수 없습니다', style: AppTextStyles.bodyMedium)),
      );
    }

    final step = state.framePoints.length;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkCard,
        title: Text('레인 캘리브레이션', style: AppTextStyles.headingSmall.copyWith(color: AppColors.textPrimary)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(icon: const Icon(Icons.undo), tooltip: '마지막 점 제거', onPressed: vm.undo),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _imageSize == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(File(widget.referenceImagePath), fit: BoxFit.contain),
                      CalibrationOverlay(
                        points: state.framePoints,
                        onTap: vm.addPoint,
                        imageSize: _imageSize!,
                      ),
                    ],
                  ),
          ),
          Container(
            color: AppColors.darkCard,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  step < 4
                      ? _stepGuides[step]
                      : '4점 입력 완료. 이름과 시점 선택 후 저장.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: step < 4 ? AppColors.neonOrange : AppColors.mint,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (step == 4) ...[
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: vm.setName,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: '프로파일 이름',
                      labelStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
                      filled: true,
                      fillColor: AppColors.darkSurface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<CameraViewpoint>(
                    initialValue: state.viewpoint,
                    onChanged: (v) { if (v != null) vm.setViewpoint(v); },
                    dropdownColor: AppColors.darkSurface,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: '카메라 시점',
                      labelStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
                      filled: true,
                      fillColor: AppColors.darkSurface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(value: CameraViewpoint.backRight, child: Text('뒤편 우측')),
                      DropdownMenuItem(value: CameraViewpoint.backLeft, child: Text('뒤편 좌측')),
                      DropdownMenuItem(value: CameraViewpoint.sideRight, child: Text('측면 우측')),
                      DropdownMenuItem(value: CameraViewpoint.sideLeft, child: Text('측면 좌측')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: (state.saving || state.name.trim().isEmpty)
                        ? null
                        : () async {
                            final profile = await vm.save(referenceImagePath: widget.referenceImagePath);
                            if (profile != null && context.mounted) {
                              Navigator.of(context).pop(profile);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonOrange,
                      disabledBackgroundColor: AppColors.darkDivider,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: state.saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('저장', style: AppTextStyles.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
