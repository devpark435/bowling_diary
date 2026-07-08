import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';

enum DriftStatus { ok, autoCorrected, recalibrationRequired }

class DriftCheckResult {
  final DriftStatus status;
  final HomographyMatrix homography;
  final double driftScoreNormalized; // 프레임 대각선 대비 평균 오프셋 비율
  const DriftCheckResult({
    required this.status,
    required this.homography,
    required this.driftScoreNormalized,
  });
}
