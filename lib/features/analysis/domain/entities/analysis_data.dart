import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';

/// 궤적 리본을 어느 경로로 만들었는지.
///
/// 내부 QA용 — 테플(릴리즈 빌드)에서는 debugPrint를 볼 수 없어 결과 화면에
/// 뱃지로 노출한다. 정식 릴리즈 전에 뱃지와 함께 걷어낼 수 있는 진단 필드다.
enum TrajectorySource {
  /// 픽셀 공간 투영 모델. 캘리브레이션 무관, 핀 충돌 프레임까지 곡선 연장.
  projective('픽셀투영'),

  /// 레인 좌표 폴백 — 투영 적합 실패. 연장 길이·리본 폭이 캘리브레이션 정확도에
  /// 그대로 물린다(예전 동작).
  laneFallback('레인폴백');

  const TrajectorySource(this.label);

  final String label;
}

/// 구속을 어느 코어가 냈는지. [TrajectorySource]와 같은 내부 QA용 진단값.
enum SpeedSource {
  /// 랜드마크 통과-시각 코어. 에로우 iso-u 선 통과 프레임 ~ 핀 충돌 프레임.
  /// 원근 압축에 영향받지 않는다.
  landmark('랜드마크'),

  /// 기존 이벤트-시간/회귀 코어. 파울라인 통과를 궤적 회귀로 외삽하므로
  /// 원근 압축이 그대로 실린다.
  legacy('기존');

  const SpeedSource(this.label);

  final String label;
}

class AnalysisData {
  final double? speedKmh;
  final double speedConfidence;
  final SpeedFailure? speedFailure;
  final int framesAnalyzed;
  final int fpsUsed;

  /// release~flight 단계에서 추적된 볼 궤적을 정제(trajectory_refiner) 후
  /// 레인 평면 리본으로 변환한 것. 레인 실측좌표(LanePoint)가 아니라 프레임
  /// 정규화좌표(FramePoint)로 이미 변환되어 있다 — 파이프라인이
  /// homography.laneToFrame()을 미리 적용해서 UI가 호모그래피를 알 필요 없게
  /// 한다(spec §11). 각 단면은 공 폭만큼 좌우로 벌린 두 가장자리(left/right)를
  /// 가져, 균일 두께 폴리라인이 아니라 레인에 투영된 리본(원근 반영)으로
  /// 그릴 수 있다. 결과 화면 영상 위에 곧바로 오버레이 가능한 형태.
  /// 각 단면은 관측된 분석 프레임 번호를 함께 보존해(TrajectoryRibbonPoint)
  /// 재생 위치와 동기화된 점진적 렌더링(현재 프레임까지만 그리기)에 사용한다.
  final List<TrajectoryRibbonPoint> trajectory;

  /// 핀덱 진입각(도). 피팅 곡선 끝(핀덱 쪽)의 기울기에서 산출 — 통상 3~6°.
  /// x/y가 캘리브레이션 좌표라 스케일 왜곡의 영향을 받는다: 구속(이벤트-시간,
  /// 캘리브레이션 독립)과 달리 참고치 성격. 산출 불가 시 null.
  final double? entryAngleDeg;

  // ── 내부 QA 진단 필드 ────────────────────────────────────────────
  // 테플(릴리즈 빌드)에서 debugPrint를 볼 수 없어 결과 화면 뱃지로 노출한다.
  // 정식 릴리즈 전에 뱃지와 함께 걷어낼 수 있다.

  /// 궤적 리본 생성 경로.
  final TrajectorySource? trajectorySource;

  /// 픽셀 투영 모델의 ny 잔차 rms(정규화 단위 — 화면 높이 대비).
  /// [TrajectorySource.laneFallback]이면 null.
  final double? trajectoryFitRms;

  /// 구속 채택 경로.
  final SpeedSource? speedSource;

  /// 랜드마크 통과-시각 코어가 낸 구속. 채택 여부와 무관하게 기록해
  /// 기존 코어와 나란히 비교할 수 있게 한다. 산출 실패 시 null.
  final double? landmarkSpeedKmh;

  /// 기존(이벤트-시간/회귀) 코어가 낸 구속. 산출 실패 시 null.
  final double? legacySpeedKmh;

  const AnalysisData({
    this.speedKmh,
    this.speedConfidence = 0.0,
    this.speedFailure,
    required this.framesAnalyzed,
    required this.fpsUsed,
    this.trajectory = const [],
    this.entryAngleDeg,
    this.trajectorySource,
    this.trajectoryFitRms,
    this.speedSource,
    this.landmarkSpeedKmh,
    this.legacySpeedKmh,
  });
}
