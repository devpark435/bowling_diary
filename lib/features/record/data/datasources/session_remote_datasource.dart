import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowling_diary/features/record/data/models/session_model.dart';
import 'package:bowling_diary/features/record/data/models/game_model.dart';

class SessionRemoteDataSource {
  final _supabase = Supabase.instance.client;

  Future<List<SessionModel>> getRecentSessions(String userId, {int limit = 10}) async {
    final res = await _supabase
        .from('sessions')
        .select()
        .eq('user_id', userId)
        .order('date', ascending: false)
        .limit(limit);
    return (res as List).map((e) => SessionModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<GameModel>> getGamesBySessionId(String sessionId) async {
    final res = await _supabase
        .from('games')
        .select()
        .eq('session_id', sessionId)
        .order('game_number');
    return (res as List).map((e) => GameModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> createSession({
    required String id,
    required String userId,
    required DateTime date,
    String? alleyName,
    int? laneNumber,
    String? oilPattern,
    String? laneConditionMemo,
    String? memo,
  }) async {
    await _supabase.from('sessions').insert({
      'id': id,
      'user_id': userId,
      'date': date.toIso8601String().split('T').first,
      'alley_name': alleyName,
      'lane_number': laneNumber,
      'oil_pattern': oilPattern,
      'lane_condition_memo': laneConditionMemo,
      'memo': memo,
    });
  }

  Future<void> createGame({
    required String id,
    required String sessionId,
    required int gameNumber,
    String? ballId,
    required int totalScore,
  }) async {
    await _supabase.from('games').insert({
      'id': id,
      'session_id': sessionId,
      'game_number': gameNumber,
      'ball_id': ballId,
      'total_score': totalScore,
    });
  }

  Future<void> updateSession({
    required String id,
    required DateTime date,
    String? alleyName,
    int? laneNumber,
    String? oilPattern,
    String? memo,
  }) async {
    await _supabase.from('sessions').update({
      'date': date.toIso8601String().split('T').first,
      'alley_name': alleyName,
      'lane_number': laneNumber,
      'oil_pattern': oilPattern,
      'memo': memo,
    }).eq('id', id);
  }

  Future<void> deleteGamesBySessionId(String sessionId) async {
    await _supabase.from('games').delete().eq('session_id', sessionId);
  }

  Future<void> deleteSession(String sessionId) async {
    await deleteGamesBySessionId(sessionId);
    await _supabase.from('sessions').delete().eq('id', sessionId);
  }

  /// 기간별 게임 데이터 조회 (통계용)
  /// [since] 가 null이면 전체 기간
  Future<List<Map<String, dynamic>>> getGamesWithDate(String userId, {DateTime? since}) async {
    var query = _supabase
        .from('sessions')
        .select('id, date');

    query = query.eq('user_id', userId);

    if (since != null) {
      query = query.gte('date', since.toIso8601String().split('T').first);
    }

    final sessionsRes = await query.order('date');
    final sessions = (sessionsRes as List).cast<Map<String, dynamic>>();
    if (sessions.isEmpty) return [];

    final sessionIds = sessions.map((e) => e['id'] as String).toList();
    final gamesRes = await _supabase
        .from('games')
        .select('session_id, total_score, game_number')
        .inFilter('session_id', sessionIds)
        .order('game_number');

    final sessionDateMap = {for (final s in sessions) s['id'] as String: s['date'] as String};

    return (gamesRes as List).map((g) {
      final game = Map<String, dynamic>.from(g);
      game['date'] = sessionDateMap[game['session_id']];
      return game;
    }).toList();
  }

  Future<Map<String, dynamic>> getMonthlySummary(String userId, int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);
    final sessionsRes = await _supabase
        .from('sessions')
        .select('id')
        .eq('user_id', userId)
        .gte('date', start.toIso8601String().split('T').first)
        .lte('date', end.toIso8601String().split('T').first);
    final sessionIds = (sessionsRes as List).map((e) => (e as Map)['id'] as String).toList();
    if (sessionIds.isEmpty) {
      return {'gameCount': 0, 'totalScore': 0, 'highScore': 0};
    }
    final gamesRes = await _supabase
        .from('games')
        .select('total_score')
        .inFilter('session_id', sessionIds);
    final scores = (gamesRes as List).map((e) => (e as Map)['total_score'] as int).toList();
    final total = scores.fold<int>(0, (a, b) => a + b);
    final high = scores.isEmpty ? 0 : scores.reduce((a, b) => a > b ? a : b);
    return {'gameCount': scores.length, 'totalScore': total, 'highScore': high};
  }
}
