import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';

/// 구속 신뢰도(회귀 R² × 임팩트 신호 × 릴리즈 신호, 0~1)를 사용자용 배지
/// 라벨로 변환한다. 파이프라인이 산출하는 신뢰도를 화면에 노출해
/// "이 숫자를 얼마나 믿어도 되는가"를 측정 실패와 별개로 전달한다.
String speedConfidenceBadgeLabel(double confidence) {
  if (confidence >= 0.75) return '신뢰도 높음';
  if (confidence >= 0.5) return '신뢰도 보통';
  return '참고용';
}

String speedFailureUserMessage(SpeedFailure? failure) {
  switch (failure) {
    case SpeedFailure.releaseNotFound:
    case SpeedFailure.impactNotFound:
    case SpeedFailure.lowConfidence:
      return '공을 인식하지 못했어요. 좀 더 밝은 곳에서 다시 찍어 주세요';
    case SpeedFailure.anchorMismatch:
    case SpeedFailure.outOfRange:
      return '분석에 실패했어요. 다시 촬영해 주세요';
    case null:
      return '';
  }
}
