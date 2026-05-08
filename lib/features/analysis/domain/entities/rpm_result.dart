enum RpmFailure {
  featureDetectionFailed,
  trackingLost,
  inconsistentRotation,
  outOfRange,
}

class RpmResult {
  final int? rpm;
  final double confidence;
  final RpmFailure? failure;

  const RpmResult({
    required this.rpm,
    required this.confidence,
    required this.failure,
  });

  factory RpmResult.success(int rpm, double confidence) =>
      RpmResult(rpm: rpm, confidence: confidence, failure: null);

  factory RpmResult.failed(RpmFailure failure) =>
      RpmResult(rpm: null, confidence: 0.0, failure: failure);
}
