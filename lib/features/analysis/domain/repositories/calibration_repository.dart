import 'package:bowling_diary/features/analysis/domain/entities/calibration_profile.dart';

abstract class CalibrationRepository {
  Future<List<CalibrationProfile>> listAll();
  Future<CalibrationProfile?> getById(String id);
  Future<void> save(CalibrationProfile profile);
  Future<void> delete(String id);
  Future<CalibrationProfile?> getDefault();
  Future<void> setDefault(String id);
}
