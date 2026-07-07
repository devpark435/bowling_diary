enum ImpactConfidence { high, medium, low }

class ImpactResult {
  final int frame;
  final ImpactConfidence confidence;
  const ImpactResult({required this.frame, required this.confidence});
}
