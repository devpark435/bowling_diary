import 'dart:typed_data';

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

/// 3×3 단응 행렬 (Homography Matrix)
///
/// 정규화 프레임 좌표(FramePoint)와 레인 평면 좌표(LanePoint, 단위 m) 사이의
/// 원근 변환을 표현한다. 내부적으로 [Float64List]를 사용하여 행-우선 순서로
/// 9개 원소를 저장하며, 역행렬은 생성 시 한 번 계산하여 캐시한다.
///
/// 사용 예:
/// ```dart
/// final h = HomographyMatrix.fromRowMajor(values);
/// final lane = h.frameToLane(framePoint);
/// final frame = h.laneToFrame(lanePoint);
/// ```
class HomographyMatrix {
  /// 행-우선 순서의 3×3 순방향 행렬 (9원소)
  final Float64List _m;

  /// 행-우선 순서의 3×3 역행렬 (생성 시 캐시)
  final Float64List _inv;

  HomographyMatrix._(this._m, this._inv);

  // ──────────────────────────── 팩토리 ────────────────────────────

  /// 항등 행렬로 초기화된 [HomographyMatrix]를 반환한다.
  factory HomographyMatrix.identity() {
    final m = Float64List(9);
    m[0] = 1; m[4] = 1; m[8] = 1; // 대각 원소만 1
    final inv = Float64List.fromList(m); // 항등 행렬의 역행렬 = 항등 행렬
    return HomographyMatrix._(m, inv);
  }

  /// 행-우선 순서로 나열된 [values] (9개 double) 로부터 [HomographyMatrix]를 생성한다.
  ///
  /// - [values] 길이가 9가 아니면 [ArgumentError]를 던진다.
  /// - 행렬이 특이(det ≈ 0)하면 역행렬을 구할 수 없으므로 [ArgumentError]를 던진다.
  factory HomographyMatrix.fromRowMajor(List<double> values) {
    if (values.length != 9) {
      throw ArgumentError(
        '행렬 원소는 정확히 9개여야 합니다. 현재 길이: ${values.length}',
      );
    }

    final m = Float64List.fromList(values);
    final inv = _computeInverse(m); // 특이 행렬이면 내부에서 ArgumentError
    return HomographyMatrix._(m, inv);
  }

  // ──────────────────────────── 변환 메서드 ────────────────────────────

  /// 정규화 프레임 좌표 [p]를 레인 평면 좌표로 변환한다.
  LanePoint frameToLane(FramePoint p) {
    final (x, y) = _applyHomography(_m, p.nx, p.ny);
    return LanePoint(xM: x, yM: y);
  }

  /// 레인 평면 좌표 [p]를 정규화 프레임 좌표로 변환한다.
  FramePoint laneToFrame(LanePoint p) {
    final (x, y) = _applyHomography(_inv, p.xM, p.yM);
    return FramePoint(nx: x, ny: y);
  }

  /// 행렬 원소를 행-우선 순서의 [List<double>]로 반환한다 (직렬화용).
  List<double> toRowMajorList() => List<double>.unmodifiable(_m);

  // ──────────────────────────── 내부 유틸 ────────────────────────────

  /// 3×3 동차 좌표 변환: H * [x, y, 1]^T → [x', y', w'] → (x'/w', y'/w')
  static (double, double) _applyHomography(
    Float64List h,
    double x,
    double y,
  ) {
    final xp = h[0] * x + h[1] * y + h[2];
    final yp = h[3] * x + h[4] * y + h[5];
    final wp = h[6] * x + h[7] * y + h[8];
    return (xp / wp, yp / wp);
  }

  /// 3×3 행렬의 역행렬을 여인수(cofactor) / 행렬식(determinant) 방식으로 계산한다.
  ///
  /// |det| < 1e-10 이면 특이 행렬로 판정하고 [ArgumentError]를 던진다.
  static Float64List _computeInverse(Float64List m) {
    // 원소 명명: m = [a b c / d e f / g h i]
    final a = m[0], b = m[1], c = m[2];
    final d = m[3], e = m[4], f = m[5];
    final g = m[6], h = m[7], i = m[8];

    // 행렬식
    final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);

    if (det.abs() < 1e-10) {
      throw ArgumentError('특이 행렬(det ≈ 0)은 역행렬을 구할 수 없습니다. det=$det');
    }

    final invDet = 1.0 / det;

    // 여인수 행렬의 전치 (adjugate)
    final inv = Float64List(9);
    inv[0] = (e * i - f * h) * invDet;
    inv[1] = (c * h - b * i) * invDet;
    inv[2] = (b * f - c * e) * invDet;
    inv[3] = (f * g - d * i) * invDet;
    inv[4] = (a * i - c * g) * invDet;
    inv[5] = (c * d - a * f) * invDet;
    inv[6] = (d * h - e * g) * invDet;
    inv[7] = (b * g - a * h) * invDet;
    inv[8] = (a * e - b * d) * invDet;

    return inv;
  }
}
