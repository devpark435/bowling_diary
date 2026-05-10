import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomographyMatrix', () {
    test('항등 행렬은 입력=출력', () {
      final h = HomographyMatrix.identity();
      final out = h.frameToLane(const FramePoint(nx: 0.5, ny: 0.5));
      expect(out.xM, closeTo(0.5, 1e-9));
      expect(out.yM, closeTo(0.5, 1e-9));
    });

    test('역변환 라운드트립', () {
      final h = HomographyMatrix.identity();
      const lane = LanePoint(xM: 0.3, yM: 12.0);
      final frame = h.laneToFrame(lane);
      final back = h.frameToLane(frame);
      expect(back.xM, closeTo(lane.xM, 1e-6));
      expect(back.yM, closeTo(lane.yM, 1e-6));
    });

    test('toRowMajorList 9개 원소 반환', () {
      final h = HomographyMatrix.identity();
      final list = h.toRowMajorList();
      expect(list.length, 9);
      expect(list, [1, 0, 0, 0, 1, 0, 0, 0, 1]);
    });

    test('원소 9개 아니면 ArgumentError', () {
      expect(() => HomographyMatrix.fromRowMajor([1, 2, 3]),
          throwsArgumentError);
    });

    test('특이 행렬은 ArgumentError', () {
      expect(
          () => HomographyMatrix.fromRowMajor(
              [0, 0, 0, 0, 0, 0, 0, 0, 0]),
          throwsArgumentError);
    });
  });
}
