import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';

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
