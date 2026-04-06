class SessionEntity {
  final String id;
  final String userId;
  final DateTime date;
  final String? alleyName;
  final int? laneNumber;
  final String? oilPattern;
  final String? laneConditionMemo;
  final String? memo;
  final List<String> photoUrls;
  final DateTime createdAt;

  const SessionEntity({
    required this.id,
    required this.userId,
    required this.date,
    this.alleyName,
    this.laneNumber,
    this.oilPattern,
    this.laneConditionMemo,
    this.memo,
    this.photoUrls = const [],
    required this.createdAt,
  });
}
