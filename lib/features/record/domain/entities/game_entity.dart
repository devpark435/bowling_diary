class GameEntity {
  final String id;
  final String sessionId;
  final int gameNumber;
  final String? ballId;
  final int totalScore;
  final DateTime createdAt;

  const GameEntity({
    required this.id,
    required this.sessionId,
    required this.gameNumber,
    this.ballId,
    required this.totalScore,
    required this.createdAt,
  });
}
