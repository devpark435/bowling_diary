import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';

/// 4점 DLT(Direct Linear Transform) 호모그래피 솔버
///
/// 영상 프레임의 4개 코너 좌표(FramePoint)와 레인 평면의 4개 대응점(LanePoint)을
/// 받아 3×3 호모그래피 행렬을 계산한다.
///
/// 알고리즘: h22 = 1 고정 기반 DLT. 4쌍의 대응점에서 8×8 선형 시스템을 구성하고
/// 부분 피벗 가우스 소거법으로 풀어 8개의 미지수 [h00..h21]을 구한다.
class HomographySolver {
  // 인스턴스 생성 불가 — 정적 메서드만 제공
  HomographySolver._();

  /// 4쌍의 대응점으로부터 [HomographyMatrix]를 계산한다.
  ///
  /// - [frame]: 영상 프레임의 정규화 좌표 4개
  /// - [lane]: 레인 평면의 실제 좌표 4개 (단위: 미터)
  ///
  /// [frame] 또는 [lane]의 길이가 4가 아니면 [ArgumentError]를 던진다.
  ///
  /// 반환된 [HomographyMatrix]는 [HomographyMatrix.frameToLane] 및
  /// [HomographyMatrix.laneToFrame] 변환을 지원한다.
  static HomographyMatrix solve4Point(
    List<FramePoint> frame,
    List<LanePoint> lane,
  ) {
    if (frame.length != 4 || lane.length != 4) {
      throw ArgumentError(
        '대응점은 정확히 4쌍이어야 합니다. '
        'frame.length=${frame.length}, lane.length=${lane.length}',
      );
    }

    // ── 8×9 행렬 A 구성 (각 대응점마다 행 2개) ──
    // 미지수 h = [h00, h01, h02, h10, h11, h12, h20, h21], h22 = 1 고정
    //
    // 행 2i:   [xi  yi  1   0   0   0   -Xi*xi  -Xi*yi] · h = Xi
    // 행 2i+1: [0   0   0   xi  yi  1   -Yi*xi  -Yi*yi] · h = Yi
    //
    // (xi, yi) = 프레임 정규화 좌표, (Xi, Yi) = 레인 좌표
    final a = List.generate(8, (_) => List<double>.filled(9, 0.0));

    for (var i = 0; i < 4; i++) {
      final xi = frame[i].nx;
      final yi = frame[i].ny;
      // ignore: non_constant_identifier_names — 수학 관례: 대문자 = 레인(월드) 좌표
      final Xi = lane[i].xM;
      // ignore: non_constant_identifier_names
      final Yi = lane[i].yM;

      // 첫 번째 행: X 방정식
      a[2 * i][0] = xi;
      a[2 * i][1] = yi;
      a[2 * i][2] = 1.0;
      a[2 * i][3] = 0.0;
      a[2 * i][4] = 0.0;
      a[2 * i][5] = 0.0;
      a[2 * i][6] = -Xi * xi;
      a[2 * i][7] = -Xi * yi;
      a[2 * i][8] = Xi; // 우변

      // 두 번째 행: Y 방정식
      a[2 * i + 1][0] = 0.0;
      a[2 * i + 1][1] = 0.0;
      a[2 * i + 1][2] = 0.0;
      a[2 * i + 1][3] = xi;
      a[2 * i + 1][4] = yi;
      a[2 * i + 1][5] = 1.0;
      a[2 * i + 1][6] = -Yi * xi;
      a[2 * i + 1][7] = -Yi * yi;
      a[2 * i + 1][8] = Yi; // 우변
    }

    // ── 부분 피벗 가우스 소거 (8×8, 우변 포함하여 8×9) ──
    final h = _gaussianElimination(a);

    // ── 9원소 행렬 구성: h22 = 1 추가 ──
    final values = [
      h[0], h[1], h[2],
      h[3], h[4], h[5],
      h[6], h[7], 1.0,
    ];

    return HomographyMatrix.fromRowMajor(values);
  }

  /// 부분 피벗 가우스 소거법으로 8×8 연립방정식을 푼다.
  ///
  /// [augmented]: 8×9 확장 행렬 (마지막 열이 우변 b)
  ///
  /// 행렬이 특이하거나 수치적으로 불안정하면 [ArgumentError]를 던진다.
  static List<double> _gaussianElimination(List<List<double>> augmented) {
    const n = 8;
    final a = [for (final row in augmented) List<double>.of(row)];

    // 전진 소거
    for (var col = 0; col < n; col++) {
      // 부분 피벗: 현재 열에서 절댓값이 가장 큰 행 찾기
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

      // 행 교환
      if (maxRow != col) {
        final tmp = a[col];
        a[col] = a[maxRow];
        a[maxRow] = tmp;
      }

      // 소거
      final pivot = a[col][col];
      for (var row = col + 1; row < n; row++) {
        final factor = a[row][col] / pivot;
        for (var j = col; j <= n; j++) {
          a[row][j] -= factor * a[col][j];
        }
      }
    }

    // 후진 대입
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
