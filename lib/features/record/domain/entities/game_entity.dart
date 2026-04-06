class GameEntity {
  final String id;
  final String sessionId;
  final int gameNumber;
  final String? ballId;
  final int totalScore;
  final List<FrameData>? frames;
  final DateTime createdAt;

  const GameEntity({
    required this.id,
    required this.sessionId,
    required this.gameNumber,
    this.ballId,
    required this.totalScore,
    this.frames,
    required this.createdAt,
  });
}

class FrameData {
  final int frameNumber;
  final int firstThrow;
  final int? secondThrow;
  final int? thirdThrow; // 10프레임 전용

  const FrameData({
    required this.frameNumber,
    required this.firstThrow,
    this.secondThrow,
    this.thirdThrow,
  });

  bool get isStrike => firstThrow == 10;
  bool get isSpare =>
      !isStrike && secondThrow != null && (firstThrow + secondThrow!) == 10;

  Map<String, dynamic> toJson() => {
    'frame': frameNumber,
    'first': firstThrow,
    if (secondThrow != null) 'second': secondThrow,
    if (thirdThrow != null) 'third': thirdThrow,
  };

  factory FrameData.fromJson(Map<String, dynamic> json) => FrameData(
    frameNumber: json['frame'] as int,
    firstThrow: json['first'] as int,
    secondThrow: json['second'] as int?,
    thirdThrow: json['third'] as int?,
  );
}
