import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

class AnalysisResultEntity {
  final String id;
  final String userId;
  final DateTime recordedAt;
  final double? speedKmh;
  final int? rpmEstimated;
  final int fpsUsed;
  final String? videoLocalPath;
  final String? linkedSessionId;
  final DateTime createdAt;

  /// 릴리즈 시점 볼 위치 (레인 평면 좌표, 미터)
  final LanePoint? releasePosM;

  /// 트래젝토리 곡률 최대 지점 (미터). 직선 비행이면 null.
  final LanePoint? breakPosM;

  /// 릴리즈 직후 진행각 (도). 레인 y축 기준 시계방향 양수.
  final double? aimAngleDeg;

  /// 비행 중 레인 좌표 시계열 (위치만 보관)
  final List<LanePoint> trajectoryLane;

  const AnalysisResultEntity({
    required this.id,
    required this.userId,
    required this.recordedAt,
    this.speedKmh,
    this.rpmEstimated,
    required this.fpsUsed,
    this.videoLocalPath,
    this.linkedSessionId,
    required this.createdAt,
    this.releasePosM,
    this.breakPosM,
    this.aimAngleDeg,
    this.trajectoryLane = const [],
  });
}
