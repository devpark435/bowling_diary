import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowling_diary/core/constants/supabase_constants.dart';
import 'package:bowling_diary/features/balls/data/models/catalog_ball_model.dart';

class CatalogRemoteDataSource {
  final _supabase = Supabase.instance.client;

  Future<List<CatalogBallModel>> searchBalls(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final res = await _supabase
        .from('bowling_ball_catalog')
        .select()
        .or('name.ilike.%$trimmed%,brand.ilike.%$trimmed%')
        .order('brand')
        .order('name')
        .limit(30);

    return (res as List)
        .map((e) => CatalogBallModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<CatalogBallModel>> getAllBalls() async {
    final res = await _supabase
        .from('bowling_ball_catalog')
        .select()
        .order('brand')
        .order('name');

    return (res as List)
        .map((e) => CatalogBallModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<CatalogBallModel>> getBallsByBrand(String brand) async {
    final res = await _supabase
        .from('bowling_ball_catalog')
        .select()
        .eq('brand', brand)
        .order('name');

    return (res as List)
        .map((e) => CatalogBallModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<String>> getBrands() async {
    final res = await _supabase
        .from('bowling_ball_catalog')
        .select('brand')
        .order('brand');

    final brands = (res as List)
        .map((e) => (e as Map)['brand'] as String)
        .toSet()
        .toList();
    return brands;
  }

  // 관리자 전용 메서드
  Future<CatalogBallModel> insertCatalogBall({
    required String brand,
    required String name,
    String? coverstock,
    String? coreType,
    double? rg,
    double? differential,
    String? imageUrl,
    int? releasedYear,
  }) async {
    final res = await _supabase.from('bowling_ball_catalog').insert({
      'brand': brand,
      'name': name,
      'coverstock': coverstock,
      'core_type': coreType,
      'rg': rg,
      'differential': differential,
      'image_url': imageUrl,
      'released_year': releasedYear,
    }).select().single();

    return CatalogBallModel.fromJson(Map<String, dynamic>.from(res));
  }

  Future<CatalogBallModel> updateCatalogBall({
    required String id,
    required String brand,
    required String name,
    String? coverstock,
    String? coreType,
    double? rg,
    double? differential,
    String? imageUrl,
    int? releasedYear,
  }) async {
    final res = await _supabase.from('bowling_ball_catalog').update({
      'brand': brand,
      'name': name,
      'coverstock': coverstock,
      'core_type': coreType,
      'rg': rg,
      'differential': differential,
      'image_url': imageUrl,
      'released_year': releasedYear,
    }).eq('id', id).select().single();

    return CatalogBallModel.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> deleteCatalogBall(String id) async {
    await _supabase.from('bowling_ball_catalog').delete().eq('id', id);
  }

  Future<String> uploadCatalogImage(String ballId, String filePath) async {
    final file = File(filePath);
    final ext = filePath.split('.').last;
    final name = '$ballId-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _supabase.storage.from(SupabaseConstants.ballCatalogBucket).upload(
          name,
          file,
          fileOptions: const FileOptions(upsert: true),
        );
    return _supabase.storage.from(SupabaseConstants.ballCatalogBucket).getPublicUrl(name);
  }
}
