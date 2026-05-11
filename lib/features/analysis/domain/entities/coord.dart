import 'package:equatable/equatable.dart';

/// 레인 평면 좌표 (단위: 미터)
///
/// x: 레인 좌→우 방향 (0 ~ 1.05m, 레인 너비)
/// y: 파울 라인 → 핀 덱 방향 (0 ~ 18.29m)
class LanePoint extends Equatable {
  /// x 좌표 (미터) — 레인 좌측 끝이 0, 우측 끝이 약 1.05m
  final double xM;

  /// y 좌표 (미터) — 파울 라인이 0, 핀 덱이 약 18.29m
  final double yM;

  const LanePoint({required this.xM, required this.yM});

  @override
  List<Object?> get props => [xM, yM];
}

/// 영상 프레임 정규화 좌표 (0~1 범위)
///
/// 좌상단이 (0, 0), 우하단이 (1, 1)
class FramePoint extends Equatable {
  /// 정규화 x 좌표 (0 = 좌측, 1 = 우측)
  final double nx;

  /// 정규화 y 좌표 (0 = 상단, 1 = 하단)
  final double ny;

  const FramePoint({required this.nx, required this.ny});

  @override
  List<Object?> get props => [nx, ny];
}
