import 'package:bowling_diary/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

// ── JSON 헬퍼 함수 ──────────────────────────────────────────────────────────

Map<String, dynamic>? _lanePointToJson(LanePoint? p) =>
    p == null ? null : {'xM': p.xM, 'yM': p.yM};

LanePoint? _lanePointFromJson(dynamic raw) {
  if (raw is! Map) return null;
  final m = Map<String, dynamic>.from(raw);
  final xM = (m['xM'] as num?)?.toDouble();
  final yM = (m['yM'] as num?)?.toDouble();
  if (xM == null || yM == null) return null;
  return LanePoint(xM: xM, yM: yM);
}

List<Map<String, dynamic>> _trajectoryToJson(List<LanePoint> list) =>
    list.map((p) => {'xM': p.xM, 'yM': p.yM}).toList();

List<LanePoint> _trajectoryFromJson(dynamic raw) {
  if (raw is! List) return const [];
  final result = <LanePoint>[];
  for (final e in raw) {
    final p = _lanePointFromJson(e);
    if (p != null) result.add(p);
  }
  return result;
}

// ── Model ───────────────────────────────────────────────────────────────────

class AnalysisResultModel extends AnalysisResultEntity {
  const AnalysisResultModel({
    required super.id,
    required super.userId,
    required super.recordedAt,
    super.speedKmh,
    super.rpmEstimated,
    required super.fpsUsed,
    super.videoLocalPath,
    super.linkedSessionId,
    required super.createdAt,
    super.releasePosM,
    super.breakPosM,
    super.aimAngleDeg,
    super.trajectoryLane = const [],
  });

  factory AnalysisResultModel.fromJson(Map<String, dynamic> json) {
    return AnalysisResultModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
      rpmEstimated: json['rpm_estimated'] as int?,
      fpsUsed: (json['fps_used'] as num?)?.toInt() ?? 30,
      videoLocalPath: json['video_local_path'] as String?,
      linkedSessionId: json['linked_session_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      releasePosM: _lanePointFromJson(json['release_pos_m']),
      breakPosM: _lanePointFromJson(json['break_pos_m']),
      aimAngleDeg: (json['aim_angle_deg'] as num?)?.toDouble(),
      trajectoryLane: _trajectoryFromJson(json['trajectory_lane']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'recorded_at': recordedAt.toIso8601String(),
    if (speedKmh != null) 'speed_kmh': speedKmh,
    if (rpmEstimated != null) 'rpm_estimated': rpmEstimated,
    'fps_used': fpsUsed,
    if (videoLocalPath != null) 'video_local_path': videoLocalPath,
    if (linkedSessionId != null) 'linked_session_id': linkedSessionId,
    if (releasePosM != null) 'release_pos_m': _lanePointToJson(releasePosM),
    if (breakPosM != null) 'break_pos_m': _lanePointToJson(breakPosM),
    if (aimAngleDeg != null) 'aim_angle_deg': aimAngleDeg,
    if (trajectoryLane.isNotEmpty) 'trajectory_lane': _trajectoryToJson(trajectoryLane),
  };
}
