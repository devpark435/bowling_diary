import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/repositories/calibration_repository.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';
import 'package:bowling_diary/features/analysis/presentation/providers/calibration_providers.dart';

// ──────────────────────────────────────────────────────────────
// 상태
// ──────────────────────────────────────────────────────────────

/// 라이브 분석 화면 상태
class LiveAnalysisState {
  /// 카메라 초기화 완료 여부
  final bool cameraReady;

  /// 추론 루프 실행 중 여부
  final bool inferenceActive;

  /// 현재 적용 중인 호모그래피 행렬
  final HomographyMatrix homography;

  /// 상태머신 단계
  final AnalysisPhase phase;

  /// flight/release 단계에서 누적된 레인 좌표 궤적
  final List<LanePoint> trajectory;

  /// 가장 최근 감지된 공의 레인 좌표 (null = 미감지)
  final LanePoint? lastBallPos;

  /// 가장 최근 감지된 공의 프레임 정규화 좌표 (null = 미감지)
  final FramePoint? lastBallFrame;

  /// 오류 메시지 (null = 정상)
  final String? error;

  LiveAnalysisState({
    this.cameraReady = false,
    this.inferenceActive = false,
    HomographyMatrix? homography,
    this.phase = AnalysisPhase.idle,
    this.trajectory = const [],
    this.lastBallPos,
    this.lastBallFrame,
    this.error,
  }) : homography = homography ?? HomographyMatrix.identity();

  LiveAnalysisState copyWith({
    bool? cameraReady,
    bool? inferenceActive,
    HomographyMatrix? homography,
    AnalysisPhase? phase,
    List<LanePoint>? trajectory,
    LanePoint? lastBallPos,
    bool clearLastBallPos = false,
    FramePoint? lastBallFrame,
    bool clearLastBallFrame = false,
    String? error,
    bool clearError = false,
  }) {
    return LiveAnalysisState(
      cameraReady: cameraReady ?? this.cameraReady,
      inferenceActive: inferenceActive ?? this.inferenceActive,
      homography: homography ?? this.homography,
      phase: phase ?? this.phase,
      trajectory: trajectory ?? this.trajectory,
      lastBallPos: clearLastBallPos ? null : (lastBallPos ?? this.lastBallPos),
      lastBallFrame:
          clearLastBallFrame ? null : (lastBallFrame ?? this.lastBallFrame),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// ViewModel
// ──────────────────────────────────────────────────────────────

/// 라이브 분석 뷰모델
///
/// 카메라 스트림을 열고 매 프레임마다 YOLO 추론 + FSM 업데이트를 수행한다.
class LiveAnalysisViewModel extends StateNotifier<LiveAnalysisState> {
  // ── 공개 읽기용 ValueNotifier ───────────────────────────────
  /// 외부(Page)에서 상태를 구독하기 위한 ValueNotifier.
  ///
  /// [state] 는 StateNotifier 내부 전용(@protected)이므로,
  /// 외부 위젯은 이 notifier를 통해 변경을 감지한다.
  final ValueNotifier<LiveAnalysisState> stateNotifier;

  final CalibrationRepository _calibRepo;
  final BallDetectionService _ballDetector;

  CameraController? _camera;
  AnalysisStateMachine? _fsm;

  /// 동시 추론 방지 플래그
  bool _processing = false;

  /// 프레임 카운터 (짝수 프레임만 처리 — 2배 스킵)
  int _frameCounter = 0;

  LiveAnalysisViewModel(this._calibRepo, this._ballDetector)
      : stateNotifier = ValueNotifier(LiveAnalysisState()),
        super(LiveAnalysisState());

  /// state 변경 시 stateNotifier도 함께 갱신
  @override
  set state(LiveAnalysisState value) {
    super.state = value;
    stateNotifier.value = value;
  }

  // ── 공개 API ────────────────────────────────────────────────

  /// 현재 상태 (공개 읽기 전용)
  LiveAnalysisState get currentState => state;

  /// 카메라 컨트롤러 (HUD 외부에서 [CameraPreview] 빌드용)
  CameraController? get camera => _camera;

  /// 초기화: 기본 호모그래피 로드 + 볼 감지기 로드 + 카메라 초기화
  Future<void> init() async {
    // 기본 캘리브레이션 프로파일 로드
    try {
      final profile = await _calibRepo.getDefault();
      if (profile != null) {
        state = state.copyWith(homography: profile.homography);
        debugPrint('[LiveAnalysis] 기본 호모그래피 로드 완료: ${profile.name}');
      } else {
        debugPrint('[LiveAnalysis] 기본 프로파일 없음 — 항등 행렬 사용');
      }
    } catch (e) {
      debugPrint('[LiveAnalysis] 호모그래피 로드 실패: $e (항등 행렬 사용)');
    }

    // 볼 감지기 초기화
    try {
      await _ballDetector.init();
    } catch (e) {
      state = state.copyWith(error: '볼 감지기 초기화 실패: $e');
      return;
    }

    // 카메라 초기화
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();
      _camera = ctrl;
      _fsm = AnalysisStateMachine();
      state = state.copyWith(cameraReady: true, clearError: true);
      debugPrint('[LiveAnalysis] 카메라 초기화 완료');
    } catch (e) {
      state = state.copyWith(error: '카메라 초기화 실패: $e');
    }
  }

  /// 추론 루프 시작
  Future<void> start() async {
    if (state.inferenceActive || _camera == null || !_camera!.value.isInitialized) {
      return;
    }
    _fsm?.reset();
    _frameCounter = 0;
    state = state.copyWith(
      inferenceActive: true,
      trajectory: const [],
      clearLastBallPos: true,
      clearLastBallFrame: true,
    );
    await _camera!.startImageStream(_onFrame);
    debugPrint('[LiveAnalysis] 추론 루프 시작');
  }

  /// 추론 루프 중지
  Future<void> stop() async {
    if (!state.inferenceActive || _camera == null) return;
    await _camera!.stopImageStream();
    state = state.copyWith(inferenceActive: false);
    debugPrint('[LiveAnalysis] 추론 루프 중지');
  }

  @override
  void dispose() {
    _safeStopCamera();
    _camera?.dispose();
    _ballDetector.dispose();
    debugPrint('[LiveAnalysis] dispose');
    super.dispose();
  }

  // ── 프레임 처리 ──────────────────────────────────────────────

  void _onFrame(CameraImage img) {
    if (_processing) return; // 이전 프레임 처리 중이면 드롭
    _processing = true;
    _frameCounter++;

    // 홀수 프레임 스킵 (2배 다운샘플)
    if (_frameCounter % 2 != 0) {
      _processing = false;
      return;
    }

    try {
      final dartImg = _cameraImageToImage(img);
      final det = _ballDetector.detect(dartImg);

      final lanePos = det != null
          ? state.homography.frameToLane(FramePoint(nx: det.cx, ny: det.cy))
          : null;

      _fsm!.onFrame(
        frameIdx: _frameCounter,
        detection: det,
        lanePos: lanePos,
      );

      state = state.copyWith(
        phase: _fsm!.phase,
        trajectory: _fsm!.trajectory.map((e) => e.lane).toList(),
        lastBallFrame:
            det != null ? FramePoint(nx: det.cx, ny: det.cy) : null,
        clearLastBallFrame: det == null,
        lastBallPos: lanePos,
        clearLastBallPos: lanePos == null,
      );
    } catch (e) {
      debugPrint('[LiveAnalysis] 추론 오류: $e');
    } finally {
      _processing = false;
    }
  }

  // ── YUV → RGB 변환 (Dart 구현, 느림) ───────────────────────

  /// CameraImage YUV420 / BGRA8888 → image.Image RGB.
  ///
  /// 단순 Dart 픽셀 루프. 추후 [NativeYuvConverter]로 대체 가능.
  img.Image _cameraImageToImage(CameraImage cameraImg) {
    final width = cameraImg.width;
    final height = cameraImg.height;
    final result = img.Image(width: width, height: height);

    if (cameraImg.format.group == ImageFormatGroup.yuv420) {
      final yPlane = cameraImg.planes[0];
      final uPlane = cameraImg.planes[1];
      final vPlane = cameraImg.planes[2];
      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;

      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final yIdx = y * yPlane.bytesPerRow + x;
          final uvIdx =
              (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
          final Y = yPlane.bytes[yIdx];
          final U = uPlane.bytes[uvIdx] - 128;
          final V = vPlane.bytes[uvIdx] - 128;
          final r = (Y + 1.402 * V).round().clamp(0, 255);
          final g = (Y - 0.344 * U - 0.714 * V).round().clamp(0, 255);
          final b = (Y + 1.772 * U).round().clamp(0, 255);
          result.setPixelRgb(x, y, r, g, b);
        }
      }
    } else if (cameraImg.format.group == ImageFormatGroup.bgra8888) {
      // iOS 경로 — BGRA
      final bytes = cameraImg.planes[0].bytes;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = y * cameraImg.planes[0].bytesPerRow + x * 4;
          final b = bytes[i];
          final g = bytes[i + 1];
          final r = bytes[i + 2];
          result.setPixelRgb(x, y, r, g, b);
        }
      }
    }

    return result;
  }

  void _safeStopCamera() {
    try {
      if (_camera != null && _camera!.value.isStreamingImages) {
        _camera!.stopImageStream();
      }
    } catch (_) {}
  }
}

// ──────────────────────────────────────────────────────────────
// Provider
// ──────────────────────────────────────────────────────────────

/// 라이브 분석 뷰모델 프로바이더 (autoDispose)
///
/// calibrationRepoProvider 로드 전에 접근하면 StateError를 던진다.
final liveAnalysisVMProvider = StateNotifierProvider.autoDispose<
    LiveAnalysisViewModel, LiveAnalysisState>((ref) {
  final repoAsync = ref.watch(calibrationRepoProvider);
  final repo = repoAsync.maybeWhen(data: (r) => r, orElse: () => null);
  if (repo == null) {
    throw StateError('캘리브레이션 저장소 로드 실패');
  }
  return LiveAnalysisViewModel(repo, BallDetectionService());
});
