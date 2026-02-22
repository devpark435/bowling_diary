import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowling_diary/core/constants/supabase_constants.dart';
import 'package:bowling_diary/features/balls/data/models/ball_model.dart';

class BallRemoteDataSource {
  final _supabase = Supabase.instance.client;

  Future<List<BallModel>> getBalls(String userId) async {
    final res = await _supabase
        .from('balls')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (res as List).map((e) => BallModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<BallModel?> getBallById(String id) async {
    final res = await _supabase.from('balls').select().eq('id', id).maybeSingle();
    if (res == null) return null;
    return BallModel.fromJson(Map<String, dynamic>.from(res));
  }

  Future<BallModel> insert(BallModel ball) async {
    final data = ball.toJson();
    final res = await _supabase.from('balls').insert(data).select().single();
    return BallModel.fromJson(Map<String, dynamic>.from(res));
  }

  Future<BallModel> update(BallModel ball) async {
    final data = ball.toJson();
    data.remove('id');
    data.remove('user_id');
    data.remove('created_at');
    final res = await _supabase.from('balls').update(data).eq('id', ball.id).select().single();
    return BallModel.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> delete(String id) async {
    await _supabase.from('balls').delete().eq('id', id);
  }

  Future<String> uploadImage(String userId, String ballId, String filePath) async {
    final file = File(filePath);
    final ext = filePath.split('.').last;
    final name = '$ballId-${DateTime.now().millisecondsSinceEpoch}.$ext';
    final path = '$userId/$name';
    await _supabase.storage.from(SupabaseConstants.ballImagesBucket).upload(
          path,
          file,
          fileOptions: const FileOptions(upsert: true),
        );
    return _supabase.storage.from(SupabaseConstants.ballImagesBucket).getPublicUrl(path);
  }
}
