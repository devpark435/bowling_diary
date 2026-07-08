import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/repositories/calibration_repository.dart';
import 'package:bowling_diary/features/analysis/domain/services/homography_solver.dart';

class CalibrationState {
  final List<FramePoint> framePoints;
  final CameraViewpoint viewpoint;
  final String name;
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

class CalibrationViewModel extends StateNotifier<CalibrationState> {
  final CalibrationRepository repo;
  CalibrationViewModel(this.repo) : super(const CalibrationState());

  void addPoint(FramePoint p) {
    if (state.framePoints.length >= 4) return;
    state = state.copyWith(framePoints: [...state.framePoints, p]);
  }

  void undo() {
    if (state.framePoints.isEmpty) return;
    state = state.copyWith(framePoints: state.framePoints.sublist(0, state.framePoints.length - 1));
  }

  void setViewpoint(CameraViewpoint v) => state = state.copyWith(viewpoint: v);
  void setName(String n) => state = state.copyWith(name: n);

  /// [referenceImagePath]는 drift-check(CalibrationDriftChecker)가 나중에 재사용할
  /// 캘리브레이션 시점 프레임 이미지 경로다.
  Future<CalibrationProfile?> save({required String referenceImagePath}) async {
    if (state.framePoints.length < 4 || state.name.trim().isEmpty) return null;

    state = state.copyWith(saving: true);
    try {
      const lanePts = [
        LanePoint(xM: 0, yM: 0), LanePoint(xM: 1.05, yM: 0),
        LanePoint(xM: 1.05, yM: 18.29), LanePoint(xM: 0, yM: 18.29),
      ];
      final homography = HomographySolver.solve4Point(state.framePoints, lanePts);
      final profile = CalibrationProfile(
        id: const Uuid().v4(),
        name: state.name.trim(),
        viewpoint: state.viewpoint,
        homography: homography,
        createdAt: DateTime.now(),
        referenceImagePath: referenceImagePath,
        framePoints: state.framePoints,
      );
      await repo.save(profile);
      await repo.setDefault(profile.id);
      return profile;
    } finally {
      state = state.copyWith(saving: false);
    }
  }
}
