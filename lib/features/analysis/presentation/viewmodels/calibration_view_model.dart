import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/repositories/calibration_repository.dart';
import 'package:bowling_diary/features/analysis/domain/services/homography_solver.dart';

/// 캘리브레이션 화면 상태
class CalibrationState {
  /// 사용자가 탭한 프레임 정규화 좌표 목록 (최대 4개)
  final List<FramePoint> framePoints;

  /// 선택된 카메라 시점
  final CameraViewpoint viewpoint;

  /// 프로파일 이름
  final String name;

  /// 저장 진행 중 여부
  final bool saving;

  const CalibrationState({
    this.framePoints = const [],
    this.viewpoint = CameraViewpoint.backRight,
    this.name = '',
    this.saving = false,
  });

  CalibrationState copyWith({
    List<FramePoint>? framePoints,
    CameraViewpoint? viewpoint,
    String? name,
    bool? saving,
  }) {
    return CalibrationState(
      framePoints: framePoints ?? this.framePoints,
      viewpoint: viewpoint ?? this.viewpoint,
      name: name ?? this.name,
      saving: saving ?? this.saving,
    );
  }
}

/// 레인 캘리브레이션 뷰모델
///
/// 사용자가 참조 이미지에서 4개의 코너 점을 탭하면
/// [HomographySolver.solve4Point]로 호모그래피를 계산하고
/// [CalibrationRepository]에 저장한다.
class CalibrationViewModel extends StateNotifier<CalibrationState> {
  final CalibrationRepository repo;

  CalibrationViewModel(this.repo) : super(const CalibrationState());

  /// 탭 좌표를 추가한다. 이미 4개인 경우 무시한다.
  void addPoint(FramePoint p) {
    if (state.framePoints.length >= 4) return;
    state = state.copyWith(
      framePoints: [...state.framePoints, p],
    );
  }

  /// 마지막으로 추가된 점을 제거한다. 빈 상태이면 무시한다.
  void undo() {
    if (state.framePoints.isEmpty) return;
    state = state.copyWith(
      framePoints: state.framePoints.sublist(0, state.framePoints.length - 1),
    );
  }

  /// 카메라 시점을 설정한다.
  void setViewpoint(CameraViewpoint v) {
    state = state.copyWith(viewpoint: v);
  }

  /// 프로파일 이름을 설정한다.
  void setName(String n) {
    state = state.copyWith(name: n);
  }

  /// 4점 + 이름 있을 때만 호모그래피를 계산하고 저장한다.
  ///
  /// 성공 시 저장된 [CalibrationProfile]을 반환한다.
  /// 조건 미충족 시 null을 반환한다.
  Future<CalibrationProfile?> save() async {
    if (state.framePoints.length < 4 || state.name.trim().isEmpty) return null;

    state = state.copyWith(saving: true);

    try {
      // 레인 4개 대응점: foul-left, foul-right, pin-right, pin-left 순서
      const lanePts = [
        LanePoint(xM: 0, yM: 0),
        LanePoint(xM: 1.05, yM: 0),
        LanePoint(xM: 1.05, yM: 18.29),
        LanePoint(xM: 0, yM: 18.29),
      ];

      final homography = HomographySolver.solve4Point(state.framePoints, lanePts);

      final profile = CalibrationProfile(
        id: const Uuid().v4(),
        name: state.name.trim(),
        viewpoint: state.viewpoint,
        homography: homography,
        createdAt: DateTime.now(),
      );

      await repo.save(profile);
      return profile;
    } finally {
      state = state.copyWith(saving: false);
    }
  }
}
