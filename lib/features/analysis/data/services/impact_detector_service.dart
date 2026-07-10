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

    // 허용 창(diff<=3 high / <=12 medium): pinImpactDetector가 이제 "진짜
    // 핀 폭발"(씨드 대비 지속 변화)을 잡도록 재설계돼, 호모그래피 왜곡의
    // 영향을 받는 FSM 신호와는 다소 벌어질 수 있다. 실측(같은 영상)에서
    // FSM은 118을 잡았지만 실제 핀 폭발은 프레임 육안 판독 기준 ~127-129였다
    // — 중·원거리 호모그래피 스케일 왜곡 때문에 FSM이 실제보다 이르게
    // 잡히는 경향이 있어, 옛 창(diff<=2/<=5)이면 이런 정상 케이스도 low로
    // 격하돼 FSM 프레임(왜곡 영향권)이 채택되는 역설이 생겼다.
    final diff = (pinFrame - homographyImpactFrame).abs();
    final confidence = diff <= 3
        ? ImpactConfidence.high
        : diff <= 12
            ? ImpactConfidence.medium
            : ImpactConfidence.low;

    final frame = confidence == ImpactConfidence.low ? homographyImpactFrame : pinFrame;
    return ImpactResult(frame: frame, confidence: confidence);
  }
}
