class CatalogBallEntity {
  final String id;
  final String brand;
  final String name;
  final String? coverstock;
  final String? coreType;
  final double? rg;
  final double? differential;
  final String? imageUrl;
  final int? releasedYear;

  const CatalogBallEntity({
    required this.id,
    required this.brand,
    required this.name,
    this.coverstock,
    this.coreType,
    this.rg,
    this.differential,
    this.imageUrl,
    this.releasedYear,
  });

  String get displayName => '$brand $name';
}
