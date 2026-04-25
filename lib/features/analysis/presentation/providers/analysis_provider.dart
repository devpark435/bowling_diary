import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/features/analysis/data/datasources/analysis_remote_datasource.dart';
import 'package:bowling_diary/features/analysis/data/repositories/analysis_repository_impl.dart';
import 'package:bowling_diary/features/analysis/domain/entities/analysis_result_entity.dart';
import 'package:bowling_diary/features/analysis/domain/repositories/analysis_repository.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';
import 'package:bowling_diary/features/record/domain/entities/session_entity.dart';

final analysisRepositoryProvider = Provider<AnalysisRepository>((ref) {
  return AnalysisRepositoryImpl(AnalysisRemoteDataSource());
});

final analysisHistoryProvider =
    FutureProvider<List<AnalysisResultEntity>>((ref) async {
  final auth = ref.watch(authNotifierProvider);
  if (auth is! AuthStateAuthenticated) return [];
  final repo = ref.watch(analysisRepositoryProvider);
  return repo.getHistory(auth.user.id);
});

final sameDaySessionsProvider =
    FutureProvider.family<List<SessionEntity>, DateTime>((ref, date) async {
  final auth = ref.watch(authNotifierProvider);
  if (auth is! AuthStateAuthenticated) return [];
  final repo = ref.watch(analysisRepositoryProvider);
  return repo.getSameDaySessions(auth.user.id, date);
});
