import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/rpm_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';

// TODO(Phase 6.1 DB persistence): AnalysisResultEntity 및 analysis_result_model.dart,
// Supabase 마이그레이션도 동일 필드를 추가해야 함. 사용자 승인 후 별도 작업으로 진행.

class AnalysisData {
  final double? speedKmh;
  final int? rpmEstimated;
  final int framesAnalyzed;
  final int fpsUsed;
  final SpeedFailure? speedFailure;
  final RpmFailure? rpmFailure;
  final double speedConfidence;
  final double rpmConfidence;

  /// 릴리즈 시점 볼 위치 (레인 평면 좌표, 미터). Phase 5.2에서 채워짐.
  final LanePoint? releasePosM;

  /// 트래젝토리 곡률 최대 지점 (미터). 직선 비행이면 null. Phase 5.2에서 채워짐.
  final LanePoint? breakPosM;

  /// 릴리즈 직후 진행각 (도). 레인 y축 기준 시계방향 양수. Phase 5.2에서 채워짐.
  final double? aimAngleDeg;

  /// 비행 중 레인 좌표 시계열 (frame 인덱스 제거, 위치만 보관). Phase 5.2에서 채워짐.
  final List<LanePoint> trajectoryLane;

  const AnalysisData({
    this.speedKmh,
    this.rpmEstimated,
    required this.framesAnalyzed,
    required this.fpsUsed,
    this.speedFailure,
    this.rpmFailure,
    this.speedConfidence = 0.0,
    this.rpmConfidence = 0.0,
    this.releasePosM,
    this.breakPosM,
    this.aimAngleDeg,
    this.trajectoryLane = const [],
  });
}
