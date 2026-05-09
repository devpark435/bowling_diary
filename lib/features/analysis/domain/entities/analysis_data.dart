import 'package:bowling_diary/features/analysis/domain/entities/rpm_result.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';

class AnalysisData {
  final double? speedKmh;
  final int? rpmEstimated;
  final int framesAnalyzed;
  final int fpsUsed;
  final SpeedFailure? speedFailure;
  final RpmFailure? rpmFailure;
  final double speedConfidence;
  final double rpmConfidence;

  const AnalysisData({
    this.speedKmh,
    this.rpmEstimated,
    required this.framesAnalyzed,
    required this.fpsUsed,
    this.speedFailure,
    this.rpmFailure,
    this.speedConfidence = 0.0,
    this.rpmConfidence = 0.0,
  });
}
