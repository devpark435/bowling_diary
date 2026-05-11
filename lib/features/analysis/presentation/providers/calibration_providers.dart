import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bowling_diary/features/analysis/data/repositories/calibration_repository_impl.dart';
import 'package:bowling_diary/features/analysis/domain/repositories/calibration_repository.dart';
import 'package:bowling_diary/features/analysis/presentation/viewmodels/calibration_list_view_model.dart';
import 'package:bowling_diary/features/analysis/presentation/viewmodels/calibration_view_model.dart';

/// 캘리브레이션 저장소 프로바이더 (SharedPreferences 기반)
final calibrationRepoProvider = FutureProvider<CalibrationRepository>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return CalibrationRepositoryImpl(prefs);
});

/// 캘리브레이션 뷰모델 프로바이더 (autoDispose)
final calibrationVMProvider = StateNotifierProvider.autoDispose<
    CalibrationViewModel, CalibrationState>((ref) {
  final repoAsync = ref.watch(calibrationRepoProvider);
  final repo = repoAsync.maybeWhen(data: (r) => r, orElse: () => null);
  if (repo == null) {
    throw StateError('캘리브레이션 저장소 로드 실패');
  }
  return CalibrationViewModel(repo);
});

/// 캘리브레이션 프로파일 목록 뷰모델 프로바이더 (autoDispose)
final calibrationListVMProvider = StateNotifierProvider.autoDispose<
    CalibrationListViewModel, CalibrationListState>((ref) {
  final repoAsync = ref.watch(calibrationRepoProvider);
  final repo = repoAsync.maybeWhen(data: (r) => r, orElse: () => null);
  if (repo == null) {
    throw StateError('캘리브레이션 저장소 로드 실패');
  }
  return CalibrationListViewModel(repo);
});
