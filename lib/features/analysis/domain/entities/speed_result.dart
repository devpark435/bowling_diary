enum SpeedFailure {
  releaseNotFound,
  impactNotFound,
  // 옛 앵커 기반(release→impact 거리/시간) 산식 시절의 하드 게이트였다.
  // 현재 속도 산출은 정제 궤적 선형회귀라 임팩트 프레임 자체를 계산에 쓰지
  // 않으므로 이 사유로는 더 이상 실패가 발생하지 않는다(대신 신뢰도 차감으로
  // 반영 — speed_estimator_service.dart 참조). 과거 저장 데이터 호환을 위해
  // enum 값만 남겨둔다.
  anchorMismatch,
  outOfRange,
  lowConfidence,
}

class SpeedResult {
  final double? kmh;
  final double confidence;
  final SpeedFailure? failure;
  const SpeedResult({required this.kmh, required this.confidence, required this.failure});

  factory SpeedResult.success(double kmh, double confidence) =>
      SpeedResult(kmh: kmh, confidence: confidence, failure: null);
  factory SpeedResult.failed(SpeedFailure failure) =>
      SpeedResult(kmh: null, confidence: 0.0, failure: failure);
}
