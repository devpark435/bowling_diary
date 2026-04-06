import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bowling_diary/features/balls/data/datasources/catalog_remote_datasource.dart';
import 'package:bowling_diary/features/balls/domain/entities/catalog_ball_entity.dart';

final catalogDataSourceProvider = Provider<CatalogRemoteDataSource>((ref) {
  return CatalogRemoteDataSource();
});

final catalogSearchProvider = FutureProvider.family<List<CatalogBallEntity>, String>((ref, query) async {
  final ds = ref.watch(catalogDataSourceProvider);
  return ds.searchBalls(query);
});

final catalogBrandsProvider = FutureProvider<List<String>>((ref) async {
  final ds = ref.watch(catalogDataSourceProvider);
  return ds.getBrands();
});

final catalogAllBallsProvider = FutureProvider<List<CatalogBallEntity>>((ref) async {
  final ds = ref.watch(catalogDataSourceProvider);
  return ds.getAllBalls();
});
