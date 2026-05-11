import 'package:bowling_diary/features/analysis/data/repositories/calibration_repository_impl.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:bowling_diary/features/analysis/presentation/viewmodels/calibration_list_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CalibrationListViewModel vm;
  late CalibrationRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = CalibrationRepositoryImpl(prefs);
    vm = CalibrationListViewModel(repo);
  });

  test('초기 상태 — 빈 리스트', () async {
    await vm.reload();
    expect(vm.state.profiles, isEmpty);
    expect(vm.state.defaultId, isNull);
  });

  test('reload — 저장된 프로파일 + default 노출', () async {
    final p = CalibrationProfile(
      id: 'p1',
      name: 'x',
      viewpoint: CameraViewpoint.backRight,
      homography: HomographyMatrix.identity(),
      createdAt: DateTime.now(),
    );
    await repo.save(p);
    await repo.setDefault('p1');
    await vm.reload();
    expect(vm.state.profiles.length, 1);
    expect(vm.state.defaultId, 'p1');
  });

  test('setDefault — defaultId 변경', () async {
    final p1 = CalibrationProfile(
      id: 'p1',
      name: 'a',
      viewpoint: CameraViewpoint.backRight,
      homography: HomographyMatrix.identity(),
      createdAt: DateTime(2026, 1, 1),
    );
    final p2 = CalibrationProfile(
      id: 'p2',
      name: 'b',
      viewpoint: CameraViewpoint.sideRight,
      homography: HomographyMatrix.identity(),
      createdAt: DateTime(2026, 1, 2),
    );
    await repo.save(p1);
    await repo.save(p2);
    await vm.reload();
    await vm.setDefault('p2');
    expect(vm.state.defaultId, 'p2');
  });

  test('delete — 프로파일 제거', () async {
    final p = CalibrationProfile(
      id: 'p1',
      name: 'x',
      viewpoint: CameraViewpoint.backRight,
      homography: HomographyMatrix.identity(),
      createdAt: DateTime.now(),
    );
    await repo.save(p);
    await vm.reload();
    await vm.delete('p1');
    expect(vm.state.profiles, isEmpty);
  });
}
