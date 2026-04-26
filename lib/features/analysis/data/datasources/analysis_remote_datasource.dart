import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowling_diary/features/analysis/data/models/analysis_result_model.dart';
import 'package:bowling_diary/features/record/data/models/session_model.dart';

class AnalysisRemoteDataSource {
  final _supabase = Supabase.instance.client;

  Future<List<AnalysisResultModel>> getHistory(String userId) async {
    final res = await _supabase
        .from('ball_analysis')
        .select()
        .eq('user_id', userId)
        .order('recorded_at', ascending: false);
    return (res as List)
        .map((e) => AnalysisResultModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> save(AnalysisResultModel model) async {
    await _supabase.from('ball_analysis').insert(model.toJson());
  }

  Future<List<SessionModel>> getSameDaySessions(
    String userId,
    DateTime date,
  ) async {
    final dateStr = date.toIso8601String().split('T').first;
    final res = await _supabase
        .from('sessions')
        .select()
        .eq('user_id', userId)
        .eq('date', dateStr);
    return (res as List)
        .map((e) => SessionModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> linkToSession(String analysisId, String sessionId) async {
    await _supabase
        .from('ball_analysis')
        .update({'linked_session_id': sessionId})
        .eq('id', analysisId);
  }
}
