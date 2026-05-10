import 'package:bowling_diary/features/analysis/domain/entities/homography_matrix.dart';

/// 카메라 시점 방향을 나타내는 열거형
enum CameraViewpoint {
  /// 우측 후방
  backRight,

  /// 좌측 후방
  backLeft,

  /// 우측 측면
  sideRight,

  /// 좌측 측면
  sideLeft,
}

/// 캘리브레이션 프로파일 엔티티
///
/// 단응 행렬([HomographyMatrix])과 메타데이터(id, name, viewpoint, createdAt)를
/// 하나로 묶어 저장 및 조회에 사용한다.
class CalibrationProfile {
  /// 고유 식별자
  final String id;

  /// 사용자 지정 이름
  final String name;

  /// 카메라 시점 방향
  final CameraViewpoint viewpoint;

  /// 캘리브레이션 단응 행렬
  final HomographyMatrix homography;

  /// 생성 일시
  final DateTime createdAt;

  const CalibrationProfile({
    required this.id,
    required this.name,
    required this.viewpoint,
    required this.homography,
    required this.createdAt,
  });
}
