import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/repositories/calibration_repository.dart';

/// 캘리브레이션 프로파일 목록 화면 상태
class CalibrationListState {
  final List<CalibrationProfile> profiles;
  final String? defaultId;
  final bool loading;
  final String? error;

  const CalibrationListState({
    this.profiles = const [],
    this.defaultId,
    this.loading = false,
    this.error,
  });

  CalibrationListState copyWith({
    List<CalibrationProfile>? profiles,
    String? defaultId,
    bool clearDefaultId = false,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return CalibrationListState(
      profiles: profiles ?? this.profiles,
      defaultId: clearDefaultId ? null : (defaultId ?? this.defaultId),
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 캘리브레이션 프로파일 목록 뷰모델
class CalibrationListViewModel extends StateNotifier<CalibrationListState> {
  final CalibrationRepository repo;

  CalibrationListViewModel(this.repo) : super(const CalibrationListState());

  /// 프로파일 목록과 기본 id를 다시 로드한다.
  Future<void> reload() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final profiles = await repo.listAll();
      final defaultProfile = await repo.getDefault();
      state = state.copyWith(
        profiles: profiles,
        defaultId: defaultProfile?.id,
        clearDefaultId: defaultProfile == null,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// 지정 id를 기본 프로파일로 설정한다.
  Future<void> setDefault(String id) async {
    try {
      await repo.setDefault(id);
      state = state.copyWith(defaultId: id);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// 지정 id의 프로파일을 삭제한다.
  Future<void> delete(String id) async {
    try {
      await repo.delete(id);
      final updated = state.profiles.where((p) => p.id != id).toList();
      final wasDefault = state.defaultId == id;
      state = state.copyWith(
        profiles: updated,
        clearDefaultId: wasDefault,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}
