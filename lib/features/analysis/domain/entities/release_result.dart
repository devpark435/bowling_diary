class ReleaseResult {
  final int frame;
  final double confidence;

  const ReleaseResult({required this.frame, required this.confidence});

  static const ReleaseResult notFound =
      ReleaseResult(frame: 0, confidence: 0.0);

  bool get isFound => confidence > 0;
}
