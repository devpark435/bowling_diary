import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

/// 레인 4코너 자동검출 결과 신뢰도 등급.
enum LaneDetectionQuality {
  /// 에지 라인 피팅 잔차가 작고, 파울라인을 어두운 국소최소값으로 실제 검출했으며,
  /// 유지된 스캔 레코드 수도 충분한 경우.
  good,

  /// 유효한 사다리꼴이긴 하나 위 조건 중 일부를 충족하지 못한 경우
  /// (예: 파울라인을 못 찾아 최하단 레코드로 대체).
  rough,

  /// 레인을 검출하지 못한 경우. corners에는 기본 사다리꼴이 채워진다.
  notFound,
}

/// 레인 4코너 자동검출 결과.
///
/// 검출은 항상 사용자 확인/보정 UI를 거친 뒤에만 실제 분석에 쓰인다 — 여기서는
/// "쓸만한 초기값"을 만드는 것이 목표이므로 recall을 precision보다 우선한다.
class LaneDetectionResult {
  /// foul-left, foul-right, pin-right, pin-left 순서.
  /// notFound여도 기본 사다리꼴을 채워서 반환한다(UI가 이 초기값에서 드래그 시작).
  final List<FramePoint> corners;
  final LaneDetectionQuality quality;

  const LaneDetectionResult({required this.corners, required this.quality});
}
