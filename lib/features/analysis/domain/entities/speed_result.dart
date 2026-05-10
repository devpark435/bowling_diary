enum SpeedFailure { releaseNotFound, outOfRange, lowConfidence }

class SpeedResult {
  final double? kmh;
  final double confidence;
  final SpeedFailure? failure;

  const SpeedResult({
    required this.kmh,
    required this.confidence,
    required this.failure,
  });

  factory SpeedResult.success(double kmh, double confidence) =>
      SpeedResult(kmh: kmh, confidence: confidence, failure: null);

  factory SpeedResult.failed(SpeedFailure failure) =>
      SpeedResult(kmh: null, confidence: 0.0, failure: failure);
}
