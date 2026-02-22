class BallEntity {
  final String id;
  final String userId;
  final String name;
  final String? brand;
  final int? weight;
  final String? coverstock;
  final double? rg;
  final double? differential;
  final String? layout;
  final String? imageUrl;
  final DateTime createdAt;

  const BallEntity({
    required this.id,
    required this.userId,
    required this.name,
    this.brand,
    this.weight,
    this.coverstock,
    this.rg,
    this.differential,
    this.layout,
    this.imageUrl,
    required this.createdAt,
  });

  BallEntity copyWith({
    String? id,
    String? userId,
    String? name,
    String? brand,
    int? weight,
    String? coverstock,
    double? rg,
    double? differential,
    String? layout,
    String? imageUrl,
    DateTime? createdAt,
  }) {
    return BallEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      weight: weight ?? this.weight,
      coverstock: coverstock ?? this.coverstock,
      rg: rg ?? this.rg,
      differential: differential ?? this.differential,
      layout: layout ?? this.layout,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
