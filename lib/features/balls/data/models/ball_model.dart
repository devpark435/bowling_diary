import 'package:bowling_diary/features/balls/domain/entities/ball_entity.dart';

class BallModel extends BallEntity {
  const BallModel({
    required super.id,
    required super.userId,
    required super.name,
    super.brand,
    super.weight,
    super.coverstock,
    super.rg,
    super.differential,
    super.layout,
    super.imageUrl,
    required super.createdAt,
  });

  factory BallModel.fromJson(Map<String, dynamic> json) {
    return BallModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      weight: (json['weight'] as num?)?.toInt(),
      coverstock: json['coverstock'] as String?,
      rg: (json['rg'] as num?)?.toDouble(),
      differential: (json['differential'] as num?)?.toDouble(),
      layout: json['layout'] as String?,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'brand': brand,
      'weight': weight,
      'coverstock': coverstock,
      'rg': rg,
      'differential': differential,
      'layout': layout,
      'image_url': imageUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
