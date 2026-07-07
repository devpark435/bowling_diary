import 'dart:typed_data';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

class HomographyMatrix {
  final Float64List _m;
  final Float64List _inv;
  HomographyMatrix._(this._m, this._inv);

  factory HomographyMatrix.identity() {
    final m = Float64List(9);
    m[0] = 1; m[4] = 1; m[8] = 1;
    final inv = Float64List.fromList(m);
    return HomographyMatrix._(m, inv);
  }

  factory HomographyMatrix.fromRowMajor(List<double> values) {
    if (values.length != 9) {
      throw ArgumentError('행렬 원소는 정확히 9개여야 합니다. 현재 길이: ${values.length}');
    }
    final m = Float64List.fromList(values);
    final inv = _computeInverse(m);
    return HomographyMatrix._(m, inv);
  }

  LanePoint frameToLane(FramePoint p) {
    final (x, y) = _applyHomography(_m, p.nx, p.ny);
    return LanePoint(xM: x, yM: y);
  }

  FramePoint laneToFrame(LanePoint p) {
    final (x, y) = _applyHomography(_inv, p.xM, p.yM);
    return FramePoint(nx: x, ny: y);
  }

  List<double> toRowMajorList() => List<double>.unmodifiable(_m);

  static (double, double) _applyHomography(Float64List h, double x, double y) {
    final xp = h[0] * x + h[1] * y + h[2];
    final yp = h[3] * x + h[4] * y + h[5];
    final wp = h[6] * x + h[7] * y + h[8];
    return (xp / wp, yp / wp);
  }

  static Float64List _computeInverse(Float64List m) {
    final a = m[0], b = m[1], c = m[2];
    final d = m[3], e = m[4], f = m[5];
    final g = m[6], h = m[7], i = m[8];
    final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if (det.abs() < 1e-10) {
      throw ArgumentError('특이 행렬(det ≈ 0)은 역행렬을 구할 수 없습니다. det=$det');
    }
    final invDet = 1.0 / det;
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
