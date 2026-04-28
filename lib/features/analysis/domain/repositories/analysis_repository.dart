import 'package:bowling_diary/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:bowling_diary/features/record/domain/entities/session_entity.dart';

abstract class AnalysisRepository {
  Future<List<AnalysisResultEntity>> getHistory(String userId);
  Future<void> save(AnalysisResultEntity result);
  Future<List<SessionEntity>> getSameDaySessions(String userId, DateTime date);
  Future<void> linkToSession(String analysisId, String sessionId);
  Future<void> delete(String id);
}
