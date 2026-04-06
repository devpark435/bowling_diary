import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';
import 'package:bowling_diary/features/balls/presentation/providers/ball_provider.dart';
import 'package:bowling_diary/features/record/data/datasources/session_remote_datasource.dart';
import 'package:bowling_diary/features/record/data/models/game_model.dart';
import 'package:bowling_diary/features/record/data/models/session_model.dart';

final sessionRemoteDataSourceProvider = Provider<SessionRemoteDataSource>((ref) {
  return SessionRemoteDataSource();
});

class RecentGameSummary {
  final SessionModel session;
  final List<GameModel> games;
  final String? ballName;

  const RecentGameSummary({
    required this.session,
    required this.games,
    this.ballName,
  });

  int get totalScore => games.fold<int>(0, (a, b) => a + b.totalScore);
  double get average => games.isEmpty ? 0 : totalScore / games.length;
}

final recentGamesProvider = FutureProvider<List<RecentGameSummary>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final dataSource = ref.read(sessionRemoteDataSourceProvider);
  final sessions = await dataSource.getRecentSessions(user.id);
    final ballRepo = ref.read(ballRepositoryProvider);
  final List<RecentGameSummary> results = [];
  for (final s in sessions) {
    final games = await dataSource.getGamesBySessionId(s.id);
    String? ballName;
    if (games.isNotEmpty && games.first.ballId != null) {
      final ball = await ballRepo.getBallById(games.first.ballId!);
      ballName = ball?.name;
    }
    results.add(RecentGameSummary(session: s, games: games, ballName: ballName));
  }
  return results;
});

final monthlySummaryProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return {'gameCount': 0, 'totalScore': 0, 'highScore': 0};
  final dataSource = ref.read(sessionRemoteDataSourceProvider);
  final now = DateTime.now();
  return dataSource.getMonthlySummary(user.id, now.year, now.month);
});
