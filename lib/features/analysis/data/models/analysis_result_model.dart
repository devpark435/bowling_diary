import 'package:bowling_diary/features/analysis/domain/entities/analysis_result_entity.dart';

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
    super.speedConfidence,
    super.speedFailureReason,
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
      speedConfidence: (json['speed_confidence'] as num?)?.toDouble() ?? 0.0,
      speedFailureReason: json['speed_failure_reason'] as String?,
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
    'speed_confidence': speedConfidence,
    if (speedFailureReason != null) 'speed_failure_reason': speedFailureReason,
  };
}
