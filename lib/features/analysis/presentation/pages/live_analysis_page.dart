import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';
import 'package:bowling_diary/features/analysis/presentation/providers/calibration_providers.dart';
import 'package:bowling_diary/features/analysis/presentation/viewmodels/live_analysis_view_model.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/live_hud_overlay.dart';

/// 라이브 카메라 분석 페이지
///
/// 카메라 프리뷰 위에 HUD 오버레이를 얹고 실시간으로 볼 감지 + FSM 상태를
/// 표시한다. 영상 저장 없이 라이브 추론만 수행하는 별도 플로우.
class LiveAnalysisPage extends ConsumerStatefulWidget {
  const LiveAnalysisPage({super.key});

  @override
  ConsumerState<LiveAnalysisPage> createState() => _LiveAnalysisPageState();
}

class _LiveAnalysisPageState extends ConsumerState<LiveAnalysisPage> {
  LiveAnalysisViewModel? _vm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryInit());
  }

  Future<void> _tryInit() async {
    if (_vm != null || !mounted) return;

    final repoAsync = ref.read(calibrationRepoProvider);
    final repo = repoAsync.maybeWhen(data: (r) => r, orElse: () => null);
    if (repo == null) {
      // 저장소 아직 로드 중 — build()에서 ref.watch가 재트리거
      return;
    }

    final vm = LiveAnalysisViewModel(repo, BallDetectionService());
    if (!mounted) {
      vm.dispose();
      return;
    }
    setState(() => _vm = vm);
    await vm.init();
  }

  @override
  void dispose() {
    _vm?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 저장소 로드 완료 감시 — vm 없을 때 재시도
    ref.watch(calibrationRepoProvider).whenData((_) {
      if (_vm == null) _tryInit();
    });

    if (_vm == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.neonOrange),
        ),
      );
    }

    return ValueListenableBuilder<LiveAnalysisState>(
      valueListenable: _vm!.stateNotifier,
      builder: (context, s, _) => _buildBody(context, s),
    );
  }

  Widget _buildBody(BuildContext context, LiveAnalysisState s) {
    if (s.error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(PhosphorIconsRegular.arrowLeft,
                color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            '라이브 분석',
            style: AppTextStyles.headingSmall
                .copyWith(color: Colors.white),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              s.error!,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 카메라 프리뷰
          if (s.cameraReady && _vm!.camera != null)
            CameraPreview(_vm!.camera!)
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                      color: AppColors.neonOrange),
                  const SizedBox(height: 16),
                  Text(
                    '카메라 초기화 중...',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),

          // HUD 오버레이
          if (s.cameraReady)
            Positioned.fill(child: LiveHudOverlay(state: s)),

          // 상단 바
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // 뒤로가기 버튼
                  GestureDetector(
                    onTap: () async {
                      if (s.inferenceActive) await _vm!.stop();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white24, width: 1),
                      ),
                      child: const Icon(
                          PhosphorIconsRegular.arrowLeft,
                          color: Colors.white,
                          size: 20),
                    ),
                  ),
                  const Spacer(),
                  // LIVE 배지
                  if (s.inferenceActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red
                            .withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(PhosphorIconsFill.record,
                              color: Colors.white, size: 10),
                          const SizedBox(width: 4),
                          Text(
                            'LIVE',
                            style: AppTextStyles.bodySmall
                                .copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 하단 버튼
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 힌트 텍스트
                  if (!s.cameraReady)
                    const SizedBox.shrink()
                  else if (!s.inferenceActive)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '시작 버튼을 눌러 라이브 분석을 시작하세요',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.white70),
                      ),
                    )
                  else if (s.phase == AnalysisPhase.idle)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '볼을 카메라에 비춰주세요',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.white70),
                      ),
                    )
                  else
                    const SizedBox(height: 24),

                  // 시작 / 중지 버튼
                  GestureDetector(
                    onTap: s.cameraReady
                        ? (s.inferenceActive
                            ? _vm!.stop
                            : _vm!.start)
                        : null,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: s.inferenceActive
                            ? Colors.red
                            : AppColors.neonOrange,
                        border: Border.all(
                            color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: (s.inferenceActive
                                    ? Colors.red
                                    : AppColors.neonOrange)
                                .withValues(alpha: 0.4),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        s.inferenceActive
                            ? PhosphorIconsFill.stop
                            : PhosphorIconsFill.play,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
