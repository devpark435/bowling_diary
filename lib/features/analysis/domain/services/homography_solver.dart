import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';

class HomographySolver {
  HomographySolver._();

  static HomographyMatrix solve4Point(List<FramePoint> frame, List<LanePoint> lane) {
    if (frame.length != 4 || lane.length != 4) {
      throw ArgumentError(
        '대응점은 정확히 4쌍이어야 합니다. frame.length=${frame.length}, lane.length=${lane.length}',
      );
    }
    final a = List.generate(8, (_) => List<double>.filled(9, 0.0));
    for (var i = 0; i < 4; i++) {
      final xi = frame[i].nx;
      final yi = frame[i].ny;
      final Xi = lane[i].xM;
      final Yi = lane[i].yM;
      a[2 * i][0] = xi; a[2 * i][1] = yi; a[2 * i][2] = 1.0;
      a[2 * i][3] = 0.0; a[2 * i][4] = 0.0; a[2 * i][5] = 0.0;
      a[2 * i][6] = -Xi * xi; a[2 * i][7] = -Xi * yi; a[2 * i][8] = Xi;
      a[2 * i + 1][0] = 0.0; a[2 * i + 1][1] = 0.0; a[2 * i + 1][2] = 0.0;
      a[2 * i + 1][3] = xi; a[2 * i + 1][4] = yi; a[2 * i + 1][5] = 1.0;
      a[2 * i + 1][6] = -Yi * xi; a[2 * i + 1][7] = -Yi * yi; a[2 * i + 1][8] = Yi;
    }
    final h = _gaussianElimination(a);
    final values = [h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1.0];
    return HomographyMatrix.fromRowMajor(values);
  }

  static List<double> _gaussianElimination(List<List<double>> augmented) {
    const n = 8;
    final a = [for (final row in augmented) List<double>.of(row)];
    for (var col = 0; col < n; col++) {
      var maxRow = col;
      var maxVal = a[col][col].abs();
      for (var row = col + 1; row < n; row++) {
        if (a[row][col].abs() > maxVal) {
          maxVal = a[row][col].abs();
          maxRow = row;
        }
      }
      if (maxVal < 1e-12) {
        throw ArgumentError(
          '호모그래피를 풀 수 없습니다: 행렬이 특이합니다 (열 $col의 피벗 ≈ 0). '
          '4개 대응점이 일반 위치(general position)에 있는지 확인하세요.',
        );
      }
      if (maxRow != col) {
        final tmp = a[col]; a[col] = a[maxRow]; a[maxRow] = tmp;
      }
      final pivot = a[col][col];
      for (var row = col + 1; row < n; row++) {
        final factor = a[row][col] / pivot;
        for (var j = col; j <= n; j++) {
          a[row][j] -= factor * a[col][j];
        }
      }
    }
    final x = List<double>.filled(n, 0.0);
    for (var i = n - 1; i >= 0; i--) {
      x[i] = a[i][n];
      for (var j = i + 1; j < n; j++) {
        x[i] -= a[i][j] * x[j];
      }
      x[i] /= a[i][i];
    }
    return x;
  }
}
