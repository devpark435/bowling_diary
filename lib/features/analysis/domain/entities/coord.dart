import 'package:equatable/equatable.dart';

class LanePoint extends Equatable {
  final double xM; // 0 ~ 1.05m (레인 너비)
  final double yM; // 0 ~ 18.29m (파울라인 → 핀덱)
  const LanePoint({required this.xM, required this.yM});
  @override
  List<Object?> get props => [xM, yM];
}

class FramePoint extends Equatable {
  final double nx; // 0=좌, 1=우
  final double ny; // 0=상단, 1=하단
  const FramePoint({required this.nx, required this.ny});
  @override
  List<Object?> get props => [nx, ny];
}
