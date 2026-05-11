import 'package:bowling_diary/features/analysis/data/repositories/calibration_repository_impl.dart';
import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/presentation/viewmodels/calibration_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CalibrationViewModel vm;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    vm = CalibrationViewModel(CalibrationRepositoryImpl(prefs));
  });

  test('초기 상태 — 점 0개, 빈 이름, backRight', () {
    expect(vm.state.framePoints, isEmpty);
    expect(vm.state.name, '');
    expect(vm.state.viewpoint, CameraViewpoint.backRight);
  });

  test('addPoint — 최대 4개까지', () {
    for (var i = 0; i < 6; i++) {
      vm.addPoint(FramePoint(nx: i * 0.1, ny: i * 0.1));
    }
    expect(vm.state.framePoints.length, 4);
  });

  test('undo — 마지막 점 제거', () {
    vm.addPoint(const FramePoint(nx: 0.1, ny: 0.1));
    vm.addPoint(const FramePoint(nx: 0.2, ny: 0.2));
    vm.undo();
    expect(vm.state.framePoints.length, 1);
    expect(vm.state.framePoints.first.nx, 0.1);
  });

  test('undo — 빈 상태에서 호출 시 무시', () {
    vm.undo();
    expect(vm.state.framePoints, isEmpty);
  });

  test('save — 4점 미만이면 null 반환', () async {
    vm.setName('test');
    vm.addPoint(const FramePoint(nx: 0.1, ny: 0.1));
    final result = await vm.save();
    expect(result, isNull);
  });

  test('save — 이름 비어있으면 null 반환', () async {
    for (var i = 0; i < 4; i++) {
      vm.addPoint(FramePoint(nx: 0.1 + i * 0.1, ny: 0.1));
    }
    final result = await vm.save();
    expect(result, isNull);
  });

  test('save — 4점 + 이름 있으면 프로파일 생성 후 저장', () async {
    vm.setName('테스트 프로파일');
    vm.setViewpoint(CameraViewpoint.sideRight);
    // 합리적인 4점 (foul-left, foul-right, pin-right, pin-left)
    vm.addPoint(const FramePoint(nx: 0.30, ny: 0.95));
    vm.addPoint(const FramePoint(nx: 0.70, ny: 0.95));
    vm.addPoint(const FramePoint(nx: 0.55, ny: 0.30));
    vm.addPoint(const FramePoint(nx: 0.45, ny: 0.30));
    final profile = await vm.save();
    expect(profile, isNotNull);
    expect(profile!.name, '테스트 프로파일');
    expect(profile.viewpoint, CameraViewpoint.sideRight);
    expect(profile.id.length, greaterThan(0));
  });
}
