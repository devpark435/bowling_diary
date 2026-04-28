import 'package:bowling_diary/features/analysis/data/datasources/analysis_remote_datasource.dart';
import 'package:bowling_diary/features/analysis/data/models/analysis_result_model.dart';
import 'package:bowling_diary/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:bowling_diary/features/analysis/domain/repositories/analysis_repository.dart';
import 'package:bowling_diary/features/record/domain/entities/session_entity.dart';

class AnalysisRepositoryImpl implements AnalysisRepository {
  final AnalysisRemoteDataSource _remote;

  AnalysisRepositoryImpl(this._remote);

  @override
  Future<List<AnalysisResultEntity>> getHistory(String userId) =>
      _remote.getHistory(userId);

  @override
  Future<void> save(AnalysisResultEntity result) =>
      _remote.save(AnalysisResultModel(
        id: result.id,
        userId: result.userId,
        recordedAt: result.recordedAt,
        speedKmh: result.speedKmh,
        rpmEstimated: result.rpmEstimated,
        fpsUsed: result.fpsUsed,
        videoLocalPath: result.videoLocalPath,
        linkedSessionId: result.linkedSessionId,
        createdAt: result.createdAt,
      ));

  @override
  Future<List<SessionEntity>> getSameDaySessions(
    String userId,
    DateTime date,
  ) async {
    final models = await _remote.getSameDaySessions(userId, date);
    return models;
  }

  @override
  Future<void> linkToSession(String analysisId, String sessionId) =>
      _remote.linkToSession(analysisId, sessionId);

  @override
  Future<void> delete(String id) => _remote.delete(id);
}
