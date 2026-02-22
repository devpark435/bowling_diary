import 'package:bowling_diary/features/balls/domain/entities/ball_entity.dart';

abstract class BallRepository {
  Future<List<BallEntity>> getBalls(String userId);
  Future<BallEntity?> getBallById(String id);
  Future<BallEntity> createBall(BallEntity ball, {String? imagePath});
  Future<BallEntity> updateBall(BallEntity ball, {String? imagePath});
  Future<void> deleteBall(String id);
  Future<String> uploadBallImage(String userId, String ballId, String filePath);
}
