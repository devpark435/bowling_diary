import 'dart:ui';

class ImpactResult {
  final int frame;
  final Rect roi;
  final double confidence;

  const ImpactResult({
    required this.frame,
    required this.roi,
    required this.confidence,
  });

  static const ImpactResult notFound =
      ImpactResult(frame: 0, roi: Rect.zero, confidence: 0.0);

  bool get isFound => confidence > 0;
}
