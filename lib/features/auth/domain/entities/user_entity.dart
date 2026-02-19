class UserEntity {
  final String id;
  final String? nickname;
  final String? bowlingStyle;
  final String? profileImageUrl;
  final DateTime createdAt;

  const UserEntity({
    required this.id,
    this.nickname,
    this.bowlingStyle,
    this.profileImageUrl,
    required this.createdAt,
  });

  bool get isProfileComplete => nickname != null && nickname!.isNotEmpty;

  UserEntity copyWith({
    String? id,
    String? nickname,
    String? bowlingStyle,
    String? profileImageUrl,
    DateTime? createdAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      bowlingStyle: bowlingStyle ?? this.bowlingStyle,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
