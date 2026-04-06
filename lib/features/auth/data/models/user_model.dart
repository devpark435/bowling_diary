import 'package:bowling_diary/features/auth/domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required super.id,
    super.nickname,
    super.bowlingStyle,
    super.profileImageUrl,
    super.role,
    required super.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      nickname: json['nickname'] as String?,
      bowlingStyle: json['bowling_style'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      role: UserRole.fromString(json['role'] as String? ?? 'free'),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nickname': nickname,
      'bowling_style': bowlingStyle,
      'profile_image_url': profileImageUrl,
      'role': role.name,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
