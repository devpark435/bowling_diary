import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/homography_solver.dart';

/// 레인 실측 좌표계 기준선 하나 — 프레임 정규화 좌표로 투영된 두 끝점(폭
/// 방향 xM=0, xM=1.05)과 라벨을 담는다. [drawLine]이 false인 항목
/// (파울라인/핀덱)은 이미 레인 4코너 사각형의 변으로 그려지므로 호출부는
/// 라벨만 표시하면 된다 — 선을 다시 그리면 기존 코너 외곽선과 중복된다.
class LaneGuideLine {
  final double yM;
  final String label;
  final FramePoint left;
  final FramePoint right;
  final bool drawLine;

  const LaneGuideLine({
    required this.yM,
    required this.label,
    required this.left,
    required this.right,
    required this.drawLine,
  });
}

/// 레인 실측 좌표계(spec §10 기준: 파울라인=y0, 핀덱=y18.29m, 폭 1.05m).
/// 순서는 코너 리스트와 동일하게 foul-left, foul-right, pin-right, pin-left.
/// analysis_trim_page.dart의 `_laneCorners`와 동일한 값 — 실제 분석에 쓰이는
/// 대응관계를 캘리브레이션 미리보기에도 그대로 반영하기 위해 값을 맞춘다.
const _laneCorners = [
  LanePoint(xM: 0, yM: 0),
  LanePoint(xM: 1.05, yM: 0),
  LanePoint(xM: 1.05, yM: 18.29),
  LanePoint(xM: 0, yM: 18.29),
];

/// [corners](정확히 4점, foul-left/foul-right/pin-right/pin-left 순서)로부터
/// 실시간 호모그래피를 산출하고, 검증용 레인 기준선 4개(파울라인/에로우/
/// 레인지파인더/핀덱)를 프레임 좌표로 투영한다.
///
/// 핀덱 라벨은 "구석 핀 머리 높이"를 안내한다 — 광각 렌즈 원거리 압축 보정을
/// 위한 실측 경험칙(핀 발밑/바닥 기준으로 잡으면 구속이 과대 산출됨).
///
/// 코너가 4개가 아니거나 퇴화 사각형(예: 드래그 중 대각선 교차)이라
/// 호모그래피를 풀 수 없으면 null을 반환한다 — 호출부는 그리드 렌더링을
/// 생략하면 된다(크래시 금지가 우선).
List<LaneGuideLine>? computeLaneGuideLines(List<FramePoint> corners) {
  if (corners.length != 4) return null;
  try {
    final homography = HomographySolver.solve4Point(corners, _laneCorners);
    FramePoint at(double xM, double yM) => homography.laneToFrame(LanePoint(xM: xM, yM: yM));
    return [
      LaneGuideLine(yM: 0, label: '파울라인', left: at(0, 0), right: at(1.05, 0), drawLine: false),
      LaneGuideLine(yM: 4.57, label: '에로우(화살표)', left: at(0, 4.57), right: at(1.05, 4.57), drawLine: true),
      LaneGuideLine(yM: 12.19, label: '레인지파인더', left: at(0, 12.19), right: at(1.05, 12.19), drawLine: true),
      LaneGuideLine(yM: 18.29, label: '핀덱(구석 핀 머리 높이에)', left: at(0, 18.29), right: at(1.05, 18.29), drawLine: false),
    ];
  } catch (_) {
    return null;
  }
}
