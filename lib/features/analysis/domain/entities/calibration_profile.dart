import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';

enum CameraViewpoint { backRight, backLeft, sideRight, sideLeft }

class CalibrationProfile {
  final String id;
  final String name;
  final CameraViewpoint viewpoint;
  final HomographyMatrix homography;
  final DateTime createdAt;

  /// 캘리브레이션 시점에 사용한 레퍼런스 이미지 경로.
  /// drift-check(CalibrationDriftChecker)가 촬영 영상 첫 프레임과 비교할 때 사용.
  final String referenceImagePath;

  /// 사용자가 탭한 4개 프레임 좌표 (foul-left, foul-right, pin-right, pin-left 순서).
  /// drift-check가 각 점 주변 패치를 재검출할 때 사용.
  final List<FramePoint> framePoints;

  const CalibrationProfile({
    required this.id,
    required this.name,
    required this.viewpoint,
    required this.homography,
    required this.createdAt,
    required this.referenceImagePath,
    required this.framePoints,
  });
}
