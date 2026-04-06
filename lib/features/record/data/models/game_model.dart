import 'package:bowling_diary/features/record/domain/entities/game_entity.dart';

class GameModel extends GameEntity {
  const GameModel({
    required super.id,
    required super.sessionId,
    required super.gameNumber,
    super.ballId,
    required super.totalScore,
    super.frames,
    required super.createdAt,
  });

  factory GameModel.fromJson(Map<String, dynamic> json) {
    List<FrameData>? frames;
    if (json['frames'] != null) {
      frames = (json['frames'] as List)
          .map((f) => FrameData.fromJson(Map<String, dynamic>.from(f)))
          .toList();
    }
    return GameModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      gameNumber: json['game_number'] as int,
      ballId: json['ball_id'] as String?,
      totalScore: json['total_score'] as int,
      frames: frames,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
