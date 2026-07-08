import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomographyMatrix', () {
    test('identity는 좌표를 그대로 반환', () {
      final h = HomographyMatrix.identity();
      final result = h.frameToLane(const FramePoint(nx: 0.3, ny: 0.7));
      expect(result.xM, closeTo(0.3, 1e-9));
      expect(result.yM, closeTo(0.7, 1e-9));
    });

    test('frameToLane 후 laneToFrame은 원래 좌표로 복원', () {
      final h = HomographyMatrix.fromRowMajor([2, 0, 1, 0, 3, 1, 0, 0, 1]);
      const original = FramePoint(nx: 0.4, ny: 0.6);
      final lane = h.frameToLane(original);
      final restored = h.laneToFrame(lane);
      expect(restored.nx, closeTo(original.nx, 1e-9));
      expect(restored.ny, closeTo(original.ny, 1e-9));
    });

    test('9개가 아닌 리스트는 ArgumentError', () {
      expect(() => HomographyMatrix.fromRowMajor([1, 2, 3]), throwsArgumentError);
    });
  });
}
