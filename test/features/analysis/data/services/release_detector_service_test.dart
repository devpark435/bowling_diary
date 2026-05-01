import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/data/services/release_detector_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _d = BallDetection(cx: 0.5, cy: 0.5, bw: 0.1, bh: 0.1, confidence: 0.9);

void main() {
  late ReleaseDetectorService sut;

  setUp(() => sut = ReleaseDetectorService());

  test('감지 없으면 null 반환', () {
    expect(sut.findReleaseFrame([null, null, null]), isNull);
  });

  test('연속 3프레임 미만이면 null', () {
    expect(sut.findReleaseFrame([_d, _d, null, _d, null]), isNull);
  });

  test('연속 3프레임 시작 인덱스 반환', () {
    // frames: null, null, ball, ball, ball, ball
    final detections = [null, null, _d, _d, _d, _d];
    expect(sut.findReleaseFrame(detections), equals(2));
  });

  test('중간 끊김 후 연속 3프레임이면 그 첫 인덱스 반환', () {
    // frames: ball, null, ball, ball, ball
    final detections = [_d, null, _d, _d, _d];
    expect(sut.findReleaseFrame(detections), equals(2));
  });

  test('리스트 시작부터 연속이면 0 반환', () {
    expect(sut.findReleaseFrame([_d, _d, _d]), equals(0));
  });
}
