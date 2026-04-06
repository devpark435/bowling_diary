import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';
import 'package:bowling_diary/features/home/presentation/providers/home_provider.dart';

enum StatsPeriod { oneMonth, threeMonths, all }

final statsPeriodProvider = StateProvider<StatsPeriod>((ref) => StatsPeriod.oneMonth);

class GameStatPoint {
  final DateTime date;
  final int score;

  const GameStatPoint({required this.date, required this.score});
}

class StatsData {
  final List<GameStatPoint> games;

  const StatsData({required this.games});

  int get gameCount => games.length;
  int get totalScore => games.fold<int>(0, (a, b) => a + b.score);
  double get average => games.isEmpty ? 0 : totalScore / gameCount;
  int get highScore => games.isEmpty ? 0 : games.map((g) => g.score).reduce((a, b) => a > b ? a : b);
  int get lowScore => games.isEmpty ? 0 : games.map((g) => g.score).reduce((a, b) => a < b ? a : b);

  /// 일별 평균 점수 (차트용)
  List<GameStatPoint> get dailyAverages {
    final grouped = <String, List<int>>{};
    for (final g in games) {
      final key = '${g.date.year}-${g.date.month.toString().padLeft(2, '0')}-${g.date.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(g.score);
    }
    final result = grouped.entries.map((e) {
      final avg = e.value.fold<int>(0, (a, b) => a + b) ~/ e.value.length;
      return GameStatPoint(date: DateTime.parse(e.key), score: avg);
    }).toList();
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  /// 점수 분포 (구간별 게임 수)
  Map<String, int> get scoreDistribution {
    final dist = <String, int>{
      '0-100': 0,
      '101-130': 0,
      '131-160': 0,
      '161-190': 0,
      '191-220': 0,
      '221-260': 0,
      '261-300': 0,
    };
    for (final g in games) {
      if (g.score <= 100) {
        dist['0-100'] = dist['0-100']! + 1;
      } else if (g.score <= 130) {
        dist['101-130'] = dist['101-130']! + 1;
      } else if (g.score <= 160) {
        dist['131-160'] = dist['131-160']! + 1;
      } else if (g.score <= 190) {
        dist['161-190'] = dist['161-190']! + 1;
      } else if (g.score <= 220) {
        dist['191-220'] = dist['191-220']! + 1;
      } else if (g.score <= 260) {
        dist['221-260'] = dist['221-260']! + 1;
      } else {
        dist['261-300'] = dist['261-300']! + 1;
      }
    }
    return dist;
  }
}

final statsDataProvider = FutureProvider<StatsData>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const StatsData(games: []);

  final period = ref.watch(statsPeriodProvider);
  final ds = ref.read(sessionRemoteDataSourceProvider);

  DateTime? since;
  final now = DateTime.now();
  switch (period) {
    case StatsPeriod.oneMonth:
      since = DateTime(now.year, now.month - 1, now.day);
      break;
    case StatsPeriod.threeMonths:
      since = DateTime(now.year, now.month - 3, now.day);
      break;
    case StatsPeriod.all:
      since = null;
      break;
  }

  final rawGames = await ds.getGamesWithDate(user.id, since: since);
  final games = rawGames.map((g) {
    return GameStatPoint(
      date: DateTime.parse(g['date'] as String),
      score: g['total_score'] as int,
    );
  }).toList();

  return StatsData(games: games);
});
