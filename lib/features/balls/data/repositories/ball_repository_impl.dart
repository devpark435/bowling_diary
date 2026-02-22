import 'package:bowling_diary/features/balls/data/datasources/ball_remote_datasource.dart';
import 'package:bowling_diary/features/balls/domain/entities/ball_entity.dart';
import 'package:bowling_diary/features/balls/domain/repositories/ball_repository.dart';
import 'package:bowling_diary/features/balls/data/models/ball_model.dart';

class BallRepositoryImpl implements BallRepository {
  BallRepositoryImpl([BallRemoteDataSource? dataSource])
      : _dataSource = dataSource ?? BallRemoteDataSource();

  final BallRemoteDataSource _dataSource;

  @override
  Future<List<BallEntity>> getBalls(String userId) async {
    return _dataSource.getBalls(userId);
  }

  @override
  Future<BallEntity?> getBallById(String id) async {
    return _dataSource.getBallById(id);
  }

  @override
  Future<BallEntity> createBall(BallEntity ball, {String? imagePath}) async {
    BallModel model = BallModel(
      id: ball.id,
      userId: ball.userId,
      name: ball.name,
      brand: ball.brand,
      weight: ball.weight,
      coverstock: ball.coverstock,
      rg: ball.rg,
      differential: ball.differential,
      layout: ball.layout,
      imageUrl: ball.imageUrl,
      createdAt: ball.createdAt,
    );
    if (imagePath != null && imagePath.isNotEmpty) {
      final url = await _dataSource.uploadImage(ball.userId, ball.id, imagePath);
      model = BallModel(
        id: model.id,
        userId: model.userId,
        name: model.name,
        brand: model.brand,
        weight: model.weight,
        coverstock: model.coverstock,
        rg: model.rg,
        differential: model.differential,
        layout: model.layout,
        imageUrl: url,
        createdAt: model.createdAt,
      );
    }
    return _dataSource.insert(model);
  }

  @override
  Future<BallEntity> updateBall(BallEntity ball, {String? imagePath}) async {
    BallModel model = BallModel(
      id: ball.id,
      userId: ball.userId,
      name: ball.name,
      brand: ball.brand,
      weight: ball.weight,
      coverstock: ball.coverstock,
      rg: ball.rg,
      differential: ball.differential,
      layout: ball.layout,
      imageUrl: ball.imageUrl,
      createdAt: ball.createdAt,
    );
    if (imagePath != null && imagePath.isNotEmpty) {
      final url = await _dataSource.uploadImage(ball.userId, ball.id, imagePath);
      model = BallModel(
        id: model.id,
        userId: model.userId,
        name: model.name,
        brand: model.brand,
        weight: model.weight,
        coverstock: model.coverstock,
        rg: model.rg,
        differential: model.differential,
        layout: model.layout,
        imageUrl: url,
        createdAt: model.createdAt,
      );
    }
    return _dataSource.update(model);
  }

  @override
  Future<void> deleteBall(String id) async {
    await _dataSource.delete(id);
  }

  @override
  Future<String> uploadBallImage(String userId, String ballId, String filePath) async {
    return _dataSource.uploadImage(userId, ballId, filePath);
  }
}
