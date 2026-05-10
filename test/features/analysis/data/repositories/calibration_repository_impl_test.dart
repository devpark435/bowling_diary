import 'package:bowling_diary/features/analysis/data/repositories/calibration_repository_impl.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CalibrationRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = CalibrationRepositoryImpl(prefs);
  });

  test('save 후 listAll 라운드트립', () async {
    final profile = CalibrationProfile(
      id: 'p1',
      name: '우측 거치',
      viewpoint: CameraViewpoint.sideRight,
      homography: HomographyMatrix.identity(),
      createdAt: DateTime(2026, 1, 1),
    );
    await repo.save(profile);
    final all = await repo.listAll();
    expect(all.length, 1);
    expect(all.first.id, 'p1');
    expect(all.first.viewpoint, CameraViewpoint.sideRight);
  });

  test('save 같은 id는 upsert', () async {
    final p1 = CalibrationProfile(
      id: 'p1',
      name: '원본',
      viewpoint: CameraViewpoint.backRight,
      homography: HomographyMatrix.identity(),
      createdAt: DateTime(2026, 1, 1),
    );
    final p1Updated = CalibrationProfile(
      id: 'p1',
      name: '수정',
      viewpoint: CameraViewpoint.sideLeft,
      homography: HomographyMatrix.identity(),
      createdAt: DateTime(2026, 1, 2),
    );
    await repo.save(p1);
    await repo.save(p1Updated);
    final all = await repo.listAll();
    expect(all.length, 1);
    expect(all.first.name, '수정');
  });

  test('getById 조회', () async {
    final p = CalibrationProfile(
      id: 'p2',
      name: 'x',
      viewpoint: CameraViewpoint.backRight,
      homography: HomographyMatrix.identity(),
      createdAt: DateTime(2026, 1, 1),
    );
    await repo.save(p);
    final got = await repo.getById('p2');
    expect(got?.id, 'p2');
    expect(await repo.getById('none'), isNull);
  });

  test('delete 시 default도 제거', () async {
    final p = CalibrationProfile(
      id: 'p3',
      name: 'x',
      viewpoint: CameraViewpoint.backRight,
      homography: HomographyMatrix.identity(),
      createdAt: DateTime(2026, 1, 1),
    );
    await repo.save(p);
    await repo.setDefault('p3');
    await repo.delete('p3');
    expect(await repo.getDefault(), isNull);
    expect((await repo.listAll()).length, 0);
  });

  test('default 설정/조회', () async {
    final p = CalibrationProfile(
      id: 'p4',
      name: 'x',
      viewpoint: CameraViewpoint.backRight,
      homography: HomographyMatrix.identity(),
      createdAt: DateTime.now(),
    );
    await repo.save(p);
    await repo.setDefault('p4');
    final got = await repo.getDefault();
    expect(got?.id, 'p4');
  });

  test('homography 직렬화 라운드트립', () async {
    final h = HomographyMatrix.fromRowMajor([
      1.2, 0.3, -0.5,
      0.1, 0.9, 0.2,
      0.004, 0.002, 1.0,
    ]);
    final p = CalibrationProfile(
      id: 'p5',
      name: 'h',
      viewpoint: CameraViewpoint.backLeft,
      homography: h,
      createdAt: DateTime(2026, 1, 1),
    );
    await repo.save(p);
    final loaded = (await repo.listAll()).first;
    expect(loaded.homography.toRowMajorList(), h.toRowMajorList());
  });

  test('초기 상태는 빈 목록', () async {
    expect(await repo.listAll(), isEmpty);
  });

  test('손상된 JSON은 빈 목록으로 복구', () async {
    SharedPreferences.setMockInitialValues({'calibration_profiles_v1': '{not a list}'});
    final prefs = await SharedPreferences.getInstance();
    final badRepo = CalibrationRepositoryImpl(prefs);
    expect(await badRepo.listAll(), isEmpty);
  });

  test('알 수 없는 viewpoint는 디코딩 실패로 누락', () async {
    SharedPreferences.setMockInitialValues({
      'calibration_profiles_v1': '[{"id":"bad","name":"x","viewpoint":"unknown","homography":[1,0,0,0,1,0,0,0,1],"createdAt":"2026-01-01T00:00:00.000"}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final badRepo = CalibrationRepositoryImpl(prefs);
    expect(await badRepo.listAll(), isEmpty);
  });

  test('존재하지 않는 id를 기본값으로 설정하면 getDefault는 null', () async {
    await repo.setDefault('ghost');
    expect(await repo.getDefault(), isNull);
  });
}
