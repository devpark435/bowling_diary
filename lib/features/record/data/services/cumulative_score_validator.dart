import 'package:flutter/foundation.dart';

import 'package:bowling_diary/features/record/domain/entities/ocr_result.dart';

/// 검증 결과
class ValidationResult {
  final List<OcrFrameResult> correctedFrames;
  final List<int> mismatchedFrames;
  final bool isFullyValidated;

  const ValidationResult({
    required this.correctedFrames,
    required this.mismatchedFrames,
    required this.isFullyValidated,
  });
}

/// 프레임별 검증 상태
enum FrameValidationStatus {
  /// 순방향 계산과 누적 점수 일치
  validated,
  /// 역추론으로 보정됨
  corrected,
  /// 검증 불가 (데이터 부족)
  unverified,
  /// 순방향 계산과 불일치
  mismatched,
}

/// 누적 점수를 사용하여 프레임 데이터를 교차 검증하고 보정
class CumulativeScoreValidator {
  /// 프레임 목록과 누적 점수를 교차 검증
  ValidationResult validate({
    required List<OcrFrameResult> frames,
    required Map<int, int> cumulativeScores,
  }) {
    debugPrint('[Validator] === 검증 시작 ===');
    debugPrint('[Validator] 프레임 수: ${frames.length}, 누적 점수 수: ${cumulativeScores.length}');

    if (cumulativeScores.isEmpty) {
      debugPrint('[Validator] 누적 점수 없음 → 검증 불가');
      return ValidationResult(
        correctedFrames: frames,
        mismatchedFrames: [],
        isFullyValidated: false,
      );
    }

    final frameMap = <int, OcrFrameResult>{};
    for (final f in frames) {
      frameMap[f.frameNumber] = f;
    }

    final corrected = <int, OcrFrameResult>{};
    final mismatched = <int>[];

    // 각 프레임에 대해 순방향 계산 vs 누적 점수 비교
    for (int i = 1; i <= 10; i++) {
      final frame = frameMap[i];
      final cumScore = cumulativeScores[i];
      final prevCum = cumulativeScores[i - 1] ?? (i == 1 ? 0 : null);

      if (cumScore == null) {
        if (frame != null) corrected[i] = frame;
        continue;
      }

      if (prevCum == null) {
        if (frame != null) {
          corrected[i] = frame.copyWith(cumulativeScore: cumScore);
        } else {
          corrected[i] = OcrFrameResult(
            frameNumber: i,
            cumulativeScore: cumScore,
            confidence: OcrConfidence.unrecognized,
          );
        }
        continue;
      }

      final diff = cumScore - prevCum;
      debugPrint('[Validator] F$i: diff=$diff (누적=$cumScore, 이전=$prevCum)');

      if (frame != null && frame.firstThrow != null) {
        // 프레임 데이터 있음 → 순방향 검증
        final forwardScore = _calculateFrameScore(frame, frameMap, i);
        if (forwardScore != null && forwardScore == diff) {
          debugPrint('[Validator]   F$i: 순방향 계산 일치 ($forwardScore)');
          corrected[i] = frame.copyWith(
            cumulativeScore: cumScore,
            confidence: OcrConfidence.high,
            validationStatus: OcrValidationStatus.validated,
          );
        } else if (forwardScore == null && frame.confidence == OcrConfidence.high) {
          // 보너스 투구 미확정으로 순방향 계산 불가 + 고신뢰도 OCR → 덮어쓰지 않음
          debugPrint('[Validator]   F$i: 보너스 미확정, 고신뢰도 OCR 유지 (diff=$diff)');
          corrected[i] = frame.copyWith(
            cumulativeScore: cumScore,
            validationStatus: OcrValidationStatus.unverified,
          );
        } else {
          debugPrint('[Validator]   F$i: 불일치 (순방향=${forwardScore ?? "?"}, diff=$diff) → 역추론 시도');
          final reversed = _reverseInfer(i, diff, frame, frameMap);
          corrected[i] = reversed.copyWith(
            cumulativeScore: cumScore,
            validationStatus: (reversed.firstThrow != frame.firstThrow ||
                    reversed.secondThrow != frame.secondThrow)
                ? OcrValidationStatus.corrected
                : OcrValidationStatus.validated,
          );
          if (reversed.firstThrow != frame.firstThrow ||
              reversed.secondThrow != frame.secondThrow) {
            mismatched.add(i);
          }
        }
      } else {
        // 프레임 데이터 없음 → diff로 역추론
        debugPrint('[Validator]   F$i: 프레임 데이터 없음 → diff=$diff 역추론');
        final inferred = _inferFromDiff(i, diff, frameMap);
        corrected[i] = inferred.copyWith(
          cumulativeScore: cumScore,
          validationStatus: inferred.firstThrow != null
              ? OcrValidationStatus.corrected
              : OcrValidationStatus.unverified,
        );
      }
    }

    // === 다중 패스: 빈 프레임 연쇄 채우기 (역순 처리로 후반→전반 순서 보장) ===
    for (int pass = 0; pass < 3; pass++) {
      // 패스 시작 시 corrected 결과로 frameMap 갱신
      for (final entry in corrected.entries) {
        frameMap[entry.key] = entry.value;
      }
      bool anyFilled = false;

      // 역순 처리: F10 먼저 확정 후 앞 프레임을 연쇄 추론
      for (int i = 10; i >= 1; i--) {
        final frame = corrected[i];
        // 이미 고신뢰도로 채워진 프레임은 스킵 (isSpare/isStrike 포함)
        if (frame != null &&
            frame.confidence == OcrConfidence.high &&
            (frame.firstThrow != null || frame.isSpare || frame.isStrike)) {
          continue;
        }

        final cumScore = cumulativeScores[i];
        if (cumScore == null) continue;
        final prevCum = i == 1 ? 0 : cumulativeScores[i - 1];
        if (i > 1 && prevCum == null) continue;
        final diff = cumScore - (i == 1 ? 0 : prevCum!);

        final inferred = _inferFromDiff(i, diff, frameMap);
        if (inferred.firstThrow != null) {
          corrected[i] = inferred.copyWith(
            cumulativeScore: cumScore,
            validationStatus: OcrValidationStatus.corrected,
          );
          // 즉시 frameMap 반영 → 같은 패스 내 앞 프레임 연쇄 추론 가능
          frameMap[i] = corrected[i]!;
          if (inferred.confidence == OcrConfidence.high) anyFilled = true;
        }
      }
      if (!anyFilled) break;
    }

    final result = corrected.values.toList()
      ..sort((a, b) => a.frameNumber.compareTo(b.frameNumber));

    debugPrint('[Validator] 검증 완료: 불일치 ${mismatched.length}개, 보정됨');
    debugPrint('[Validator] === 검증 종료 ===');

    return ValidationResult(
      correctedFrames: result,
      mismatchedFrames: mismatched,
      isFullyValidated: mismatched.isEmpty && result.length == 10,
    );
  }

  /// 순방향 프레임 점수 계산 (보너스 포함)
  int? _calculateFrameScore(
    OcrFrameResult frame,
    Map<int, OcrFrameResult> allFrames,
    int frameNum,
  ) {
    if (frame.firstThrow == null) return null;

    if (frameNum == 10) {
      return (frame.firstThrow ?? 0) +
          (frame.secondThrow ?? 0) +
          (frame.thirdThrow ?? 0);
    }

    if (frame.firstThrow == 10) {
      // 스트라이크: 10 + 다음 2구
      final bonus = _getNextNBalls(allFrames, frameNum, 2);
      if (bonus == null) return null;
      return 10 + bonus;
    }

    final total = (frame.firstThrow ?? 0) + (frame.secondThrow ?? 0);
    if (total == 10) {
      // 스페어: 10 + 다음 1구
      final bonus = _getNextNBalls(allFrames, frameNum, 1);
      if (bonus == null) return null;
      return 10 + bonus;
    }

    return total;
  }

  /// 다음 N구의 핀 수 합계
  int? _getNextNBalls(Map<int, OcrFrameResult> allFrames, int currentFrame, int n) {
    final balls = <int>[];

    for (int f = currentFrame + 1; f <= 10 && balls.length < n; f++) {
      final frame = allFrames[f];
      if (frame == null || frame.firstThrow == null) return null;

      balls.add(frame.firstThrow!);
      if (balls.length < n) {
        if (f < 10) {
          if (frame.firstThrow != 10 && frame.secondThrow != null) {
            balls.add(frame.secondThrow!);
          } else if (frame.firstThrow == 10) {
            // 스트라이크 → 다음 프레임에서 추가 볼 수집
            continue;
          } else {
            return null;
          }
        } else {
          // 10프레임
          if (frame.secondThrow != null) balls.add(frame.secondThrow!);
          if (balls.length < n && frame.thirdThrow != null) {
            balls.add(frame.thirdThrow!);
          }
        }
      }
    }

    if (balls.length < n) return null;
    return balls.take(n).fold<int>(0, (sum, b) => sum + b);
  }

  /// diff 기반 역추론으로 프레임 보정
  OcrFrameResult _reverseInfer(
    int frameNum,
    int diff,
    OcrFrameResult existing,
    Map<int, OcrFrameResult> allFrames,
  ) {
    if (frameNum == 10) {
      // 10프레임은 diff 역산으로 투구값 채우기
      return _inferTenthFrame(diff, existing);
    }

    // diff <= 9: 오픈 프레임 확정
    if (diff >= 0 && diff <= 9) {
      debugPrint('[Validator]     → 오픈 프레임 (diff=$diff)');
      return _inferOpenFrame(frameNum, diff, existing);
    }

    // diff == 10~20: 스페어 가능성
    if (diff >= 10 && diff <= 20) {
      final nextFirst = _getNextFirstThrow(allFrames, frameNum);
      if (nextFirst != null && diff == 10 + nextFirst) {
        debugPrint('[Validator]     → 스페어 확정 (10+$nextFirst=$diff)');
        return OcrFrameResult(
          frameNumber: frameNum,
          firstThrow: existing.firstThrow,
          secondThrow: existing.firstThrow != null ? 10 - existing.firstThrow! : null,
          isSpare: true,
          confidence: OcrConfidence.high,
        );
      }
    }

    // diff >= 10: 스트라이크 가능성
    if (diff >= 10 && diff <= 30) {
      final nextTwo = _getNextNBalls(allFrames, frameNum, 2);
      if (nextTwo != null && diff == 10 + nextTwo) {
        debugPrint('[Validator]     → 스트라이크 확정 (10+$nextTwo=$diff)');
        return OcrFrameResult(
          frameNumber: frameNum,
          firstThrow: 10,
          isStrike: true,
          confidence: OcrConfidence.high,
        );
      }
    }

    debugPrint('[Validator]     → 역추론 실패, 기존 데이터 유지');
    return existing.copyWith(confidence: OcrConfidence.low);
  }

  /// diff만으로 프레임 추정 (프레임 데이터가 없을 때)
  OcrFrameResult _inferFromDiff(
    int frameNum,
    int diff,
    Map<int, OcrFrameResult> allFrames,
  ) {
    if (frameNum == 10) {
      return _inferTenthFrame(diff, allFrames[10]);
    }

    // diff <= 9: 오픈 프레임 (개별 투구 수 불명)
    if (diff >= 0 && diff <= 9) {
      final existing = allFrames[frameNum];
      if (existing?.firstThrow != null) {
        return existing!.copyWith(confidence: OcrConfidence.high);
      }
      return OcrFrameResult(frameNumber: frameNum, confidence: OcrConfidence.low);
    }

    // diff > 20: 수학적으로 스트라이크 확정 (스페어 최대 10+10=20 초과 불가)
    if (diff > 20 && diff <= 30) {
      debugPrint('[Validator] F$frameNum: diff=$diff → 스트라이크 자동 채움 (diff>20, confidence=high)');
      return OcrFrameResult(
        frameNumber: frameNum,
        firstThrow: 10,
        isStrike: true,
        confidence: OcrConfidence.high,
      );
    }

    // diff 10~20: 스트라이크 또는 스페어 판별
    // 스트라이크 체크 (다음 2구 합산)
    final nextTwo = _getNextNBalls(allFrames, frameNum, 2);
    if (nextTwo != null && diff == 10 + nextTwo) {
      debugPrint('[Validator] F$frameNum: diff=$diff → 스트라이크 자동 채움 (confidence=high)');
      return OcrFrameResult(
        frameNumber: frameNum,
        firstThrow: 10,
        isStrike: true,
        confidence: OcrConfidence.high,
      );
    }
    // 스페어 체크 (다음 1구)
    final nextFirst = _getNextFirstThrow(allFrames, frameNum);
    if (nextFirst != null && diff == 10 + nextFirst) {
      final existing = allFrames[frameNum];
      debugPrint('[Validator] F$frameNum: diff=$diff → 스페어 자동 채움 (confidence=high)');
      return OcrFrameResult(
        frameNumber: frameNum,
        firstThrow: existing?.firstThrow,
        secondThrow: existing?.firstThrow != null ? 10 - existing!.firstThrow! : null,
        isSpare: true,
        confidence: OcrConfidence.high,
      );
    }
    // 판정 불가: 보수적 스페어 가정 (diff 10~20은 스페어 가능성)
    debugPrint('[Validator] F$frameNum: diff=$diff → 스페어 가정 (보수적, confidence=low)');
    final existing = allFrames[frameNum];
    return OcrFrameResult(
      frameNumber: frameNum,
      firstThrow: existing?.firstThrow,
      secondThrow: existing?.firstThrow != null ? 10 - existing!.firstThrow! : null,
      isSpare: true,
      confidence: OcrConfidence.low,
    );
  }

  /// 누적 점수 diff로 10프레임 투구 역산
  OcrFrameResult _inferTenthFrame(int diff, OcrFrameResult? existing) {
    if (diff == 30) {
      debugPrint('[Validator] F10: diff=30 → X-X-X 자동 채움 (confidence=high)');
      return OcrFrameResult(
        frameNumber: 10,
        firstThrow: 10, secondThrow: 10, thirdThrow: 10,
        confidence: OcrConfidence.high,
      );
    }

    if (diff >= 20 && diff < 30) {
      // 1투 스트라이크, 나머지 두 투 합 = diff - 10
      final remaining = diff - 10;
      // OCR 힌트 활용: thirdThrow 우선, 없으면 secondThrow 중 유효 범위 값 사용
      int? hint = existing?.thirdThrow;
      if (hint == null &&
          existing?.secondThrow != null &&
          existing!.secondThrow! > 0 &&
          existing.secondThrow! <= remaining) {
        hint = existing.secondThrow;
      }
      if (hint != null && hint >= 0 && hint <= remaining) {
        final third = hint;
        final second = remaining - third;
        debugPrint('[Validator] F10: diff=$diff → X-$second-$third 자동 채움 (hint=$hint, confidence=high)');
        return OcrFrameResult(
          frameNumber: 10,
          firstThrow: 10,
          secondThrow: second,
          thirdThrow: third,
          confidence: OcrConfidence.high,
        );
      }
      // 힌트 없음: X-X-(diff-20) 추정
      debugPrint('[Validator] F10: diff=$diff → X-X-${diff - 20} 추정 (confidence=low)');
      return OcrFrameResult(
        frameNumber: 10,
        firstThrow: 10, secondThrow: 10, thirdThrow: diff - 20,
        confidence: OcrConfidence.low,
      );
    }

    if (diff >= 10 && diff < 20) {
      // 스페어 + 보너스 1투
      final bonus = diff - 10;
      final first = existing?.firstThrow ?? 0;
      final second = existing?.secondThrow ?? (10 - first);
      debugPrint('[Validator] F10: diff=$diff → 스페어+$bonus 자동 채움 (confidence=low)');
      return OcrFrameResult(
        frameNumber: 10,
        firstThrow: first, secondThrow: second, thirdThrow: bonus,
        confidence: OcrConfidence.low,
      );
    }

    // diff <= 9: 오픈
    final first = existing?.firstThrow ?? diff;
    final second = existing?.secondThrow ?? (diff - first).clamp(0, 10);
    debugPrint('[Validator] F10: diff=$diff → 오픈 자동 채움 (confidence=low)');
    return OcrFrameResult(
      frameNumber: 10,
      firstThrow: first, secondThrow: second,
      confidence: OcrConfidence.low,
    );
  }

  /// 오픈 프레임에서 diff로 1투/2투 추정
  OcrFrameResult _inferOpenFrame(int frameNum, int diff, OcrFrameResult existing) {
    if (existing.firstThrow != null && existing.secondThrow != null) {
      final total = existing.firstThrow! + existing.secondThrow!;
      if (total == diff) return existing.copyWith(confidence: OcrConfidence.high);
    }
    if (existing.firstThrow != null) {
      final second = diff - existing.firstThrow!;
      if (second >= 0 && second <= 10 - existing.firstThrow!) {
        return OcrFrameResult(
          frameNumber: frameNum,
          firstThrow: existing.firstThrow,
          secondThrow: second,
          confidence: OcrConfidence.high,
        );
      }
    }
    return existing.copyWith(confidence: OcrConfidence.low);
  }

  /// 다음 프레임의 1투 가져오기
  int? _getNextFirstThrow(Map<int, OcrFrameResult> allFrames, int currentFrame) {
    final next = allFrames[currentFrame + 1];
    return next?.firstThrow;
  }
}
