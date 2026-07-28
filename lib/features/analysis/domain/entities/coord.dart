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

/// 궤적 리본의 한 단면 — 분석 프레임 번호와, 레인 평면 위에서 공 폭만큼
/// 좌우로 벌린 두 가장자리의 프레임 정규화좌표. 균일 두께 폴리라인 대신
/// 레인 평면에 투영된 리본(가까우면 넓고 멀면 좁은 원근)을 그리기 위한 형태.
/// frame은 재생 위치와 동기화된 점진적 오버레이 렌더링(현재 프레임까지만 그리기)에 쓰인다.
class TrajectoryRibbonPoint extends Equatable {
  final int frame;
  final FramePoint left;
  final FramePoint right;
  const TrajectoryRibbonPoint({required this.frame, required this.left, required this.right});
  @override
  List<Object?> get props => [frame, left, right];
}
