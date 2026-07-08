import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';

class AnalysisData {
  final double? speedKmh;
  final double speedConfidence;
  final SpeedFailure? speedFailure;
  final int framesAnalyzed;
  final int fpsUsed;

  const AnalysisData({
    this.speedKmh,
    this.speedConfidence = 0.0,
    this.speedFailure,
    required this.framesAnalyzed,
    required this.fpsUsed,
  });
}
