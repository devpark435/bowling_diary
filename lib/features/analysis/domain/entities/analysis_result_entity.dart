class AnalysisResultEntity {
  final String id;
  final String userId;
  final DateTime recordedAt;
  final double speedKmh;
  final int? rpmEstimated;
  final int fpsUsed;
  final String? videoLocalPath;
  final String? linkedSessionId;
  final DateTime createdAt;

  const AnalysisResultEntity({
    required this.id,
    required this.userId,
    required this.recordedAt,
    required this.speedKmh,
    this.rpmEstimated,
    required this.fpsUsed,
    this.videoLocalPath,
    this.linkedSessionId,
    required this.createdAt,
  });
}
