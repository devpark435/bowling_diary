import 'package:bowling_diary/features/balls/domain/entities/catalog_ball_entity.dart';

class CatalogBallModel extends CatalogBallEntity {
  const CatalogBallModel({
    required super.id,
    required super.brand,
    required super.name,
    super.coverstock,
    super.coreType,
    super.rg,
    super.differential,
    super.imageUrl,
    super.releasedYear,
  });

  factory CatalogBallModel.fromJson(Map<String, dynamic> json) {
    return CatalogBallModel(
      id: json['id'] as String,
      brand: json['brand'] as String,
      name: json['name'] as String,
      coverstock: json['coverstock'] as String?,
      coreType: json['core_type'] as String?,
      rg: (json['rg'] as num?)?.toDouble(),
      differential: (json['differential'] as num?)?.toDouble(),
      imageUrl: json['image_url'] as String?,
      releasedYear: (json['released_year'] as num?)?.toInt(),
    );
  }
}
