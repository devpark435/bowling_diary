import 'dart:ui';

import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';

class ImpactDetectorService {
  final PinImpactDetectorService pinImpactDetector;
  const ImpactDetectorService({required this.pinImpactDetector});

  ImpactResult detect({
    required List<img.Image> frames,
    required int releaseFrame,
    required int homographyImpactFrame,
    Rect? pinZone,
    int? pinSearchStart,
  }) {
    final pinFrame = pinImpactDetector.findImpactFrame(
      frames,
      releaseFrame,
      pinZone: pinZone,
      searchStartOverride: pinSearchStart,
    );

    if (pinFrame == null) {
      return ImpactResult(frame: homographyImpactFrame, confidence: ImpactConfidence.low);
    }

    final diff = (pinFrame - homographyImpactFrame).abs();
    final confidence = diff <= 2
        ? ImpactConfidence.high
        : diff <= 5
            ? ImpactConfidence.medium
            : ImpactConfidence.low;

    final frame = confidence == ImpactConfidence.low ? homographyImpactFrame : pinFrame;
    return ImpactResult(frame: frame, confidence: confidence);
  }
}
