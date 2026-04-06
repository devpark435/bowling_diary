import 'package:bowling_diary/features/record/domain/entities/game_entity.dart';
import 'package:bowling_diary/features/record/domain/entities/session_entity.dart';

class SessionWithGames {
  final SessionEntity session;
  final List<GameEntity> games;

  const SessionWithGames({required this.session, required this.games});
}

abstract class SessionRepository {
  Future<List<SessionWithGames>> getRecentSessions(String userId, {int limit = 5});
  Future<Map<String, dynamic>> getMonthlySummary(String userId, int year, int month);
}
