import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';
import 'package:bowling_diary/features/balls/data/repositories/ball_repository_impl.dart';
import 'package:bowling_diary/features/balls/domain/entities/ball_entity.dart';
import 'package:bowling_diary/features/balls/domain/repositories/ball_repository.dart';

final ballRepositoryProvider = Provider<BallRepository>((ref) {
  return BallRepositoryImpl();
});

final ballsListProvider = FutureProvider<List<BallEntity>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final repo = ref.watch(ballRepositoryProvider);
  return repo.getBalls(user.id);
});

final ballDetailProvider = FutureProvider.family<BallEntity?, String>((ref, id) async {
  final repo = ref.watch(ballRepositoryProvider);
  return repo.getBallById(id);
});
