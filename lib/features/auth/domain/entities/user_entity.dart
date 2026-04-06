enum UserRole {
  free,
  premium,
  admin;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UserRole.free,
    );
  }
}

class UserEntity {
  final String id;
  final String? nickname;
  final String? bowlingStyle;
  final String? profileImageUrl;
  final UserRole role;
  final DateTime createdAt;

  const UserEntity({
    required this.id,
    this.nickname,
    this.bowlingStyle,
    this.profileImageUrl,
    this.role = UserRole.free,
    required this.createdAt,
  });

  bool get isProfileComplete => nickname != null && nickname!.isNotEmpty;

  bool get isPremium => role == UserRole.premium || role == UserRole.admin;

  bool get isAdmin => role == UserRole.admin;

  UserEntity copyWith({
    String? id,
    String? nickname,
    String? bowlingStyle,
    String? profileImageUrl,
    UserRole? role,
    DateTime? createdAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      bowlingStyle: bowlingStyle ?? this.bowlingStyle,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
