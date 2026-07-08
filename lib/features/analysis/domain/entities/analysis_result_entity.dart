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
  final double speedConfidence;
  final String? speedFailureReason;

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
    this.speedConfidence = 0.0,
    this.speedFailureReason,
  });
}
