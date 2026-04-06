import 'package:bowling_diary/features/record/domain/entities/game_entity.dart';

class GameModel extends GameEntity {
  const GameModel({
    required super.id,
    required super.sessionId,
    required super.gameNumber,
    super.ballId,
    required super.totalScore,
    required super.createdAt,
  });

  factory GameModel.fromJson(Map<String, dynamic> json) {
    return GameModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      gameNumber: json['game_number'] as int,
      ballId: json['ball_id'] as String?,
      totalScore: json['total_score'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
