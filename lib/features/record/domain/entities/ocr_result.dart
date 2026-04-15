import 'package:bowling_diary/features/record/domain/entities/game_entity.dart';

enum OcrConfidence { high, low, unrecognized }

/// OCR로 인식된 개별 프레임 결과
class OcrFrameResult {
  final int frameNumber;
  final int? firstThrow;
  final int? secondThrow;
  final int? thirdThrow;
  final int? cumulativeScore;
  final OcrConfidence confidence;

  const OcrFrameResult({
    required this.frameNumber,
    this.firstThrow,
    this.secondThrow,
    this.thirdThrow,
    this.cumulativeScore,
    this.confidence = OcrConfidence.unrecognized,
  });

  bool get isComplete {
    if (frameNumber < 10) {
      return firstThrow != null && (firstThrow == 10 || secondThrow != null);
    }
    // 10프레임: 스트라이크나 스페어 시 3투 필요
    if (firstThrow == null) return false;
    if (secondThrow == null) return false;
    final needsThird =
        firstThrow == 10 || (firstThrow! + secondThrow!) == 10;
    return needsThird ? thirdThrow != null : true;
  }

  FrameData? toFrameData() {
    if (firstThrow == null) return null;
    return FrameData(
      frameNumber: frameNumber,
      firstThrow: firstThrow!,
      secondThrow: secondThrow,
      thirdThrow: thirdThrow,
    );
  }

  OcrFrameResult copyWith({
    int? firstThrow,
    int? secondThrow,
    int? thirdThrow,
    int? cumulativeScore,
    OcrConfidence? confidence,
  }) {
    return OcrFrameResult(
      frameNumber: frameNumber,
      firstThrow: firstThrow ?? this.firstThrow,
      secondThrow: secondThrow ?? this.secondThrow,
      thirdThrow: thirdThrow ?? this.thirdThrow,
      cumulativeScore: cumulativeScore ?? this.cumulativeScore,
      confidence: confidence ?? this.confidence,
    );
  }
}

/// OCR로 인식된 플레이어 한 명의 결과
class OcrPlayerResult {
  final String playerName;
  final List<OcrFrameResult> frames;

  const OcrPlayerResult({
    required this.playerName,
    required this.frames,
  });

  int? get totalScore {
    if (frames.isEmpty) return null;
    final last = frames.lastWhere(
      (f) => f.cumulativeScore != null,
      orElse: () => frames.last,
    );
    return last.cumulativeScore;
  }

  int get completedFrameCount => frames.where((f) => f.isComplete).length;
  bool get isGameComplete => completedFrameCount == 10;

  List<FrameData> toFrameDataList() {
    return frames
        .where((f) => f.firstThrow != null)
        .map((f) => f.toFrameData()!)
        .toList();
  }
}

/// OCR 전체 결과
class OcrResult {
  final List<OcrPlayerResult> players;
  final String imagePath;

  const OcrResult({
    required this.players,
    required this.imagePath,
  });

  bool get hasMultiplePlayers => players.length > 1;
  bool get isEmpty => players.isEmpty;
}
