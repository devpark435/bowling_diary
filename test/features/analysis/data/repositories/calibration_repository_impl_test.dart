import 'package:bowling_diary/features/analysis/data/repositories/calibration_repository_impl.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  CalibrationProfile buildProfile(String id) => CalibrationProfile(
        id: id,
        name: '테스트 프로파일',
        viewpoint: CameraViewpoint.backRight,
        homography: HomographyMatrix.identity(),
        createdAt: DateTime(2026, 1, 1),
        referenceImagePath: '/tmp/ref_$id.jpg',
        framePoints: const [
          FramePoint(nx: 0.1, ny: 0.1), FramePoint(nx: 0.9, ny: 0.1),
          FramePoint(nx: 0.9, ny: 0.9), FramePoint(nx: 0.1, ny: 0.9),
        ],
      );

  test('저장 후 getById로 동일 필드(referenceImagePath/framePoints 포함) 조회', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = CalibrationRepositoryImpl(prefs);
    final profile = buildProfile('p1');

    await repo.save(profile);
    final loaded = await repo.getById('p1');

    expect(loaded, isNotNull);
    expect(loaded!.referenceImagePath, '/tmp/ref_p1.jpg');
    expect(loaded.framePoints, profile.framePoints);
    expect(loaded.homography.toRowMajorList(), profile.homography.toRowMajorList());
  });

  test('setDefault/getDefault 라운드트립', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = CalibrationRepositoryImpl(prefs);
    await repo.save(buildProfile('p1'));
    await repo.setDefault('p1');

    final def = await repo.getDefault();
    expect(def?.id, 'p1');
  });

  test('delete 시 기본값도 함께 제거', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = CalibrationRepositoryImpl(prefs);
    await repo.save(buildProfile('p1'));
    await repo.setDefault('p1');

    await repo.delete('p1');

    expect(await repo.getById('p1'), isNull);
    expect(await repo.getDefault(), isNull);
  });
}
