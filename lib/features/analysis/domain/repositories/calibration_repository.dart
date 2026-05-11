import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';

/// 캘리브레이션 프로파일 저장소 추상 인터페이스
abstract class CalibrationRepository {
  /// 저장된 모든 프로파일을 반환한다.
  Future<List<CalibrationProfile>> listAll();

  /// [id]에 해당하는 프로파일을 반환한다. 없으면 null을 반환한다.
  Future<CalibrationProfile?> getById(String id);

  /// 프로파일을 저장한다. 동일 [id]가 존재하면 덮어쓴다(upsert).
  Future<void> save(CalibrationProfile profile);

  /// [id]에 해당하는 프로파일을 삭제한다.
  /// 해당 프로파일이 기본값으로 설정되어 있으면 기본값도 함께 제거한다.
  Future<void> delete(String id);

  /// 기본 프로파일을 반환한다. 설정되지 않았거나 존재하지 않으면 null을 반환한다.
  Future<CalibrationProfile?> getDefault();

  /// [id]에 해당하는 프로파일을 기본값으로 설정한다.
  Future<void> setDefault(String id);
}
