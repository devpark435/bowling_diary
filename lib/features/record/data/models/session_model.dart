import 'package:bowling_diary/features/record/domain/entities/session_entity.dart';

class SessionModel extends SessionEntity {
  const SessionModel({
    required super.id,
    required super.userId,
    required super.date,
    super.alleyName,
    super.laneNumber,
    super.oilPattern,
    super.laneConditionMemo,
    super.memo,
    super.photoUrls,
    required super.createdAt,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    final photos = json['photo_urls'];
    return SessionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      date: DateTime.parse(json['date'] as String),
      alleyName: json['alley_name'] as String?,
      laneNumber: (json['lane_number'] as num?)?.toInt(),
      oilPattern: json['oil_pattern'] as String?,
      laneConditionMemo: json['lane_condition_memo'] as String?,
      memo: json['memo'] as String?,
      photoUrls: photos != null ? List<String>.from(photos) : [],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
