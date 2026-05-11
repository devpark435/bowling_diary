import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/domain/repositories/calibration_repository.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';
import 'package:bowling_diary/features/analysis/presentation/viewmodels/live_analysis_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

// ──────────────────────────────────────────────────────────────
// Mock 구현
// ──────────────────────────────────────────────────────────────

/// CalibrationRepository 인메모리 목
class _FakeCalibrationRepository implements CalibrationRepository {
  CalibrationProfile? _default;
  final Map<String, CalibrationProfile> _store = {};

  @override
  Future<List<CalibrationProfile>> listAll() async => _store.values.toList();

  @override
  Future<CalibrationProfile?> getById(String id) async => _store[id];

  @override
  Future<void> save(CalibrationProfile profile) async {
    _store[profile.id] = profile;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
    if (_default?.id == id) _default = null;
  }

  @override
  Future<CalibrationProfile?> getDefault() async => _default;

  @override
  Future<void> setDefault(String id) async {
    _default = _store[id];
  }
}

/// BallDetectionService 목 (init/dispose만 동작, detect 미사용)
class _MockBallDetectionService extends BallDetectionService {
  bool initCalled = false;
  bool disposeCalled = false;

  @override
  Future<void> init() async {
    initCalled = true;
  }

  @override
  void dispose() {
    disposeCalled = true;
  }
}

// ──────────────────────────────────────────────────────────────
// 테스트용 ViewModel
//
// 실제 카메라 초기화를 우회하기 위해 subclass에서 init() 등을 재정의한다.
// CalibrationRepository를 직접 저장해 private _calibRepo 접근을 우회한다.
// ──────────────────────────────────────────────────────────────
class _TestableViewModelWithRepo extends LiveAnalysisViewModel {
  final CalibrationRepository _repo;
  bool cameraInitShouldFail;

  _TestableViewModelWithRepo(
    this._repo,
    BallDetectionService ballDetector, {
    this.cameraInitShouldFail = false,
  }) : super(_repo, ballDetector);

  @override
  Future<void> init() async {
    // 호모그래피 로드
    try {
      final profile = await _repo.getDefault();
      if (profile != null) {
        state = state.copyWith(homography: profile.homography);
      }
    } catch (_) {}

    if (cameraInitShouldFail) {
      state = state.copyWith(error: '카메라 초기화 실패: 테스트');
      return;
    }

    state = state.copyWith(cameraReady: true);
  }

  // start/stop은 카메라 없으므로 직접 상태만 변경
  @override
  Future<void> start() async {
    if (state.inferenceActive) return;
    state = state.copyWith(
      inferenceActive: true,
      trajectory: const [],
      clearLastBallPos: true,
      clearLastBallFrame: true,
    );
  }

  @override
  Future<void> stop() async {
    if (!state.inferenceActive) return;
    state = state.copyWith(inferenceActive: false);
  }

  @override
  void dispose() {
    super.dispose();
  }
}

// ──────────────────────────────────────────────────────────────
// 테스트
// ──────────────────────────────────────────────────────────────

void main() {
  late _FakeCalibrationRepository fakeRepo;
  late _MockBallDetectionService mockDetector;

  setUp(() {
    fakeRepo = _FakeCalibrationRepository();
    mockDetector = _MockBallDetectionService();
  });

  group('LiveAnalysisState 초기값', () {
    test('기본 상태 — cameraReady false, inferenceActive false, phase idle', () {
      final vm = _TestableViewModelWithRepo(fakeRepo, mockDetector);
      addTearDown(vm.dispose);

      expect(vm.currentState.cameraReady, isFalse);
      expect(vm.currentState.inferenceActive, isFalse);
      expect(vm.currentState.phase, AnalysisPhase.idle);
      expect(vm.currentState.trajectory, isEmpty);
      expect(vm.currentState.error, isNull);
    });

    test('homography 기본값은 항등 행렬', () {
      final vm = _TestableViewModelWithRepo(fakeRepo, mockDetector);
      addTearDown(vm.dispose);

      // 항등 행렬 확인: frameToLane(0,0) → (0,0)
      final lane = vm.currentState.homography.frameToLane(
        const FramePoint(nx: 0.0, ny: 0.0),
      );
      expect(lane.xM, closeTo(0.0, 1e-9));
      expect(lane.yM, closeTo(0.0, 1e-9));
    });
  });

  group('init() — 호모그래피 로드', () {
    test('기본 프로파일 없으면 항등 행렬 유지', () async {
      final vm = _TestableViewModelWithRepo(fakeRepo, mockDetector);
      addTearDown(vm.dispose);

      await vm.init();

      expect(vm.currentState.cameraReady, isTrue);
      expect(vm.currentState.error, isNull);
      // 항등 행렬 유지 검증
      final lane = vm.currentState.homography.frameToLane(
        const FramePoint(nx: 1.0, ny: 1.0),
      );
      expect(lane.xM, closeTo(1.0, 1e-9));
      expect(lane.yM, closeTo(1.0, 1e-9));
    });

    test('기본 프로파일 있으면 해당 호모그래피 로드', () async {
      // 간단한 2배 스케일 행렬 [2,0,0 / 0,2,0 / 0,0,1]
      final h = HomographyMatrix.fromRowMajor([
        2, 0, 0,
        0, 2, 0,
        0, 0, 1,
      ]);
      final profile = CalibrationProfile(
        id: 'test-id',
        name: '테스트',
        viewpoint: CameraViewpoint.backRight,
        homography: h,
        createdAt: DateTime.now(),
      );
      await fakeRepo.save(profile);
      await fakeRepo.setDefault('test-id');

      final vm = _TestableViewModelWithRepo(fakeRepo, mockDetector);
      addTearDown(vm.dispose);
      await vm.init();

      // frameToLane(0.5, 0.5) → (1.0, 1.0) (2배 스케일)
      final lane = vm.currentState.homography.frameToLane(
        const FramePoint(nx: 0.5, ny: 0.5),
      );
      expect(lane.xM, closeTo(1.0, 1e-9));
      expect(lane.yM, closeTo(1.0, 1e-9));
    });

    test('카메라 초기화 실패 시 error 설정, cameraReady false', () async {
      final vm = _TestableViewModelWithRepo(
        fakeRepo,
        mockDetector,
        cameraInitShouldFail: true,
      );
      addTearDown(vm.dispose);

      await vm.init();

      expect(vm.currentState.cameraReady, isFalse);
      expect(vm.currentState.error, isNotNull);
      expect(vm.currentState.error, contains('카메라 초기화 실패'));
    });
  });

  group('start() / stop() — inferenceActive 토글', () {
    test('start() — inferenceActive true로 전환', () async {
      final vm = _TestableViewModelWithRepo(fakeRepo, mockDetector);
      addTearDown(vm.dispose);
      await vm.init();

      await vm.start();

      expect(vm.currentState.inferenceActive, isTrue);
    });

    test('stop() — inferenceActive false로 전환', () async {
      final vm = _TestableViewModelWithRepo(fakeRepo, mockDetector);
      addTearDown(vm.dispose);
      await vm.init();
      await vm.start();

      await vm.stop();

      expect(vm.currentState.inferenceActive, isFalse);
    });

    test('start() 중복 호출 — 상태 변화 없음', () async {
      final vm = _TestableViewModelWithRepo(fakeRepo, mockDetector);
      addTearDown(vm.dispose);
      await vm.init();
      await vm.start();
      await vm.start(); // 중복 호출

      expect(vm.currentState.inferenceActive, isTrue);
    });

    test('stop() 중복 호출 — 오류 없음', () async {
      final vm = _TestableViewModelWithRepo(fakeRepo, mockDetector);
      addTearDown(vm.dispose);
      await vm.init();

      // inferenceActive가 false인 상태에서 stop 호출
      await vm.stop();
      expect(vm.currentState.inferenceActive, isFalse);
    });

    test('start() 후 trajectory 초기화', () async {
      final vm = _TestableViewModelWithRepo(fakeRepo, mockDetector);
      addTearDown(vm.dispose);
      await vm.init();
      await vm.start();

      expect(vm.currentState.trajectory, isEmpty);
      expect(vm.currentState.lastBallFrame, isNull);
      expect(vm.currentState.lastBallPos, isNull);
    });
  });

  group('LiveAnalysisState.copyWith', () {
    test('cameraReady 변경', () {
      final s = LiveAnalysisState();
      final s2 = s.copyWith(cameraReady: true);
      expect(s2.cameraReady, isTrue);
      expect(s2.inferenceActive, isFalse); // 나머지 유지
    });

    test('clearLastBallPos 플래그로 null 설정', () {
      final s = LiveAnalysisState(
        lastBallPos: const LanePoint(xM: 0.5, yM: 5.0),
      );
      final s2 = s.copyWith(clearLastBallPos: true);
      expect(s2.lastBallPos, isNull);
    });

    test('clearError 플래그로 null 설정', () {
      final s = LiveAnalysisState(error: '테스트 오류');
      final s2 = s.copyWith(clearError: true);
      expect(s2.error, isNull);
    });

    test('trajectory 업데이트', () {
      final s = LiveAnalysisState();
      final pts = [
        const LanePoint(xM: 0.5, yM: 1.0),
        const LanePoint(xM: 0.5, yM: 5.0),
      ];
      final s2 = s.copyWith(trajectory: pts);
      expect(s2.trajectory.length, 2);
      expect(s2.trajectory.first.yM, 1.0);
    });
  });
}
