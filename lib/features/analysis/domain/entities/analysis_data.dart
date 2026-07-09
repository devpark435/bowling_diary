import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/speed_result.dart';

class AnalysisData {
  final double? speedKmh;
  final double speedConfidence;
  final SpeedFailure? speedFailure;
  final int framesAnalyzed;
  final int fpsUsed;

  /// release~flight 단계에서 추적된 볼 궤적. 레인 실측좌표(LanePoint)가 아니라
  /// 프레임 정규화좌표(FramePoint)로 이미 변환되어 있다 — 파이프라인이
  /// homography.laneToFrame()을 미리 적용해서 UI가 호모그래피를 알 필요 없게
  /// 한다(spec §11). 결과 화면 영상 위에 곧바로 오버레이 가능한 형태.
  /// 각 점은 관측된 분석 프레임 번호를 함께 보존해(TrajectoryFramePoint) 재생
  /// 위치와 동기화된 점진적 렌더링(현재 프레임까지만 그리기)에 사용한다.
  final List<TrajectoryFramePoint> trajectory;

  const AnalysisData({
    this.speedKmh,
    this.speedConfidence = 0.0,
    this.speedFailure,
    required this.framesAnalyzed,
    required this.fpsUsed,
    this.trajectory = const [],
  });
}
