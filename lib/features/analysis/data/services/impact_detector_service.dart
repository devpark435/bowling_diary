import 'dart:ui';

import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/data/services/pin_impact_detector_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';

class ImpactDetectorService {
  final PinImpactDetectorService pinImpactDetector;
  const ImpactDetectorService({required this.pinImpactDetector});

  /// [homographyImpactFrame]은 FSM(절대 y 기준)이 잡은 임팩트 프레임이다.
  /// 캘리브레이션 스케일이 사용자/시도마다 크게 흔들리는 게 실측으로
  /// 확인돼(같은 영상이 최대 y 17.5m 또는 11.5m로 분석되는 사례), FSM이
  /// 절대 y 게이트(18.29m 도달 또는 14m 이상에서 소실)를 못 넘겨 침묵할 수
  /// 있다 — 이때도 null을 넘겨 받는다. 핀 폭발 감지(pinImpactDetector, 호모그래피
  /// 존 경로)는 영구변화 게이트(창 끝 중앙값>=15%) + Δd argmax로 자체 오탐
  /// 방어가 있어 FSM 없이도 독립 신호로 신뢰할 수 있다 — 임팩트 시간축을
  /// 절대 y 스케일 오류에서 분리하는 것이 이 분기의 목적이다.
  ImpactResult? detect({
    required List<img.Image> frames,
    required int releaseFrame,
    required int? homographyImpactFrame,
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
      if (homographyImpactFrame == null) return null;
      return ImpactResult(frame: homographyImpactFrame, confidence: ImpactConfidence.low);
    }

    if (homographyImpactFrame == null) {
      // FSM이 침묵(캘리브레이션 스케일 오류로 절대 y 게이트 미발동)해도 핀
      // 폭발은 픽셀 증거(씨드 대비 지속 변화)라 시간축으로 신뢰할 수 있다 —
      // 다만 교차검증 신호가 없는 단독 판정이므로 high가 아닌 medium.
      return ImpactResult(frame: pinFrame, confidence: ImpactConfidence.medium);
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
