import 'package:bowling_diary/features/record/domain/entities/game_entity.dart';

enum OcrConfidence { high, low, unrecognized }

/// 프레임별 검증 상태 (CumulativeScoreValidator 결과)
enum OcrValidationStatus {
  /// 아직 검증 안 됨
  none,
  /// 순방향 계산과 누적 점수 일치
  validated,
  /// 역추론으로 보정됨
  corrected,
  /// 검증 불가 (데이터 부족)
  unverified,
}

/// OCR로 인식된 개별 프레임 결과
class OcrFrameResult {
  final int frameNumber;
  final int? firstThrow;
  final int? secondThrow;
  final int? thirdThrow;
  final int? cumulativeScore;
  final OcrConfidence confidence;
  final OcrValidationStatus validationStatus;
  /// 스페어 확정 플래그 (firstThrow 미상일 때도 스페어임을 명시)
  final bool isSpare;
  /// 스트라이크 확정 플래그 (firstThrow=10과 함께 명시적으로 마킹)
  final bool isStrike;

  const OcrFrameResult({
    required this.frameNumber,
    this.firstThrow,
    this.secondThrow,
    this.thirdThrow,
    this.cumulativeScore,
    this.confidence = OcrConfidence.unrecognized,
    this.validationStatus = OcrValidationStatus.none,
    this.isSpare = false,
    this.isStrike = false,
  });

  bool get isComplete {
    if (frameNumber < 10) {
      // 스트라이크 (플래그 또는 firstThrow=10)
      if (isStrike || firstThrow == 10) return true;
      // 스페어 확정 (firstThrow 미상이어도 완료로 간주)
      if (isSpare) return true;
      return firstThrow != null && secondThrow != null;
    }
    // 10프레임: 스트라이크나 스페어 시 3투 필요
    if (firstThrow == null) return false;
    if (secondThrow == null) return false;
    final needsThird =
        firstThrow == 10 || (firstThrow! + secondThrow!) == 10;
    return needsThird ? thirdThrow != null : true;
  }

  FrameData? toFrameData() {
    // 스트라이크
    if (isStrike || firstThrow == 10) {
      return FrameData(
        frameNumber: frameNumber,
        firstThrow: firstThrow ?? 10,
        secondThrow: secondThrow,
        thirdThrow: thirdThrow,
      );
    }
    // 스페어 확정이지만 첫 번째 투구 미상 → 0/10으로 저장
    if (isSpare && firstThrow == null) {
      return FrameData(
        frameNumber: frameNumber,
        firstThrow: 0,
        secondThrow: 10,
        thirdThrow: thirdThrow,
      );
    }
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
    OcrValidationStatus? validationStatus,
    bool? isSpare,
    bool? isStrike,
  }) {
    return OcrFrameResult(
      frameNumber: frameNumber,
      firstThrow: firstThrow ?? this.firstThrow,
      secondThrow: secondThrow ?? this.secondThrow,
      thirdThrow: thirdThrow ?? this.thirdThrow,
      cumulativeScore: cumulativeScore ?? this.cumulativeScore,
      confidence: confidence ?? this.confidence,
      validationStatus: validationStatus ?? this.validationStatus,
      isSpare: isSpare ?? this.isSpare,
      isStrike: isStrike ?? this.isStrike,
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
    int? maxCumulative;
    for (final frame in frames) {
      final score = frame.cumulativeScore;
      if (score == null) continue;
      if (maxCumulative == null || score > maxCumulative) {
        maxCumulative = score;
      }
    }
    return maxCumulative;
  }

  int get completedFrameCount => frames.where((f) => f.isComplete).length;
  bool get isGameComplete => completedFrameCount == 10;

  List<FrameData> toFrameDataList() {
    return frames
        .map((f) => f.toFrameData())
        .whereType<FrameData>()
        .toList();
  }
}

/// OCR 결과 적용 방식 (총점만 vs 프레임 상세)
enum OcrApplyMode { totalOnly, frameDetail }

/// OCR 결과 적용 결과
class OcrApplyResult {
  final OcrApplyMode mode;
  final int? totalScore;
  final List<FrameData>? frames;

  const OcrApplyResult({
    required this.mode,
    this.totalScore,
    this.frames,
  });

  const OcrApplyResult.totalOnly(int score)
      : mode = OcrApplyMode.totalOnly,
        totalScore = score,
        frames = null;

  OcrApplyResult.frameDetail(List<FrameData> frameData)
      : mode = OcrApplyMode.frameDetail,
        totalScore = null,
        frames = frameData;
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
