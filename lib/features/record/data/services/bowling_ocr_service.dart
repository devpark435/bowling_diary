import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:bowling_diary/features/record/domain/entities/ocr_result.dart';

class BowlingOcrService {
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.korean);

  Future<OcrResult> processImage(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final elements = _extractAllElements(recognizedText);
      if (elements.isEmpty) {
        return OcrResult(players: [], imagePath: imagePath);
      }

      final rows = _groupIntoRows(elements);
      final players = _parsePlayerRows(rows);

      return OcrResult(players: players, imagePath: imagePath);
    } catch (e) {
      debugPrint('OCR 처리 오류: $e');
      return OcrResult(players: [], imagePath: imagePath);
    }
  }

  void dispose() {
    _textRecognizer.close();
  }

  // --- 내부 구현 ---

  /// 모든 TextElement를 평탄화하여 추출
  List<_OcrElement> _extractAllElements(RecognizedText text) {
    final elements = <_OcrElement>[];
    for (final block in text.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          elements.add(_OcrElement(
            text: element.text,
            rect: element.boundingBox,
          ));
        }
      }
    }
    return elements;
  }

  /// Y좌표 기준으로 텍스트를 행(Row)으로 그룹핑
  List<_TextRow> _groupIntoRows(List<_OcrElement> elements) {
    if (elements.isEmpty) return [];

    elements.sort((a, b) => a.rect.center.dy.compareTo(b.rect.center.dy));

    final rows = <_TextRow>[];
    var currentRow = _TextRow(elements: [elements.first]);

    for (int i = 1; i < elements.length; i++) {
      final element = elements[i];
      final rowCenterY = currentRow.centerY;
      final rowHeight = currentRow.avgHeight;

      // 같은 행 판별: Y좌표 차이가 행 높이의 50% 이내
      if ((element.rect.center.dy - rowCenterY).abs() < rowHeight * 0.5) {
        currentRow.elements.add(element);
      } else {
        rows.add(currentRow);
        currentRow = _TextRow(elements: [element]);
      }
    }
    rows.add(currentRow);

    // 각 행 내부를 X좌표로 정렬
    for (final row in rows) {
      row.elements.sort((a, b) => a.rect.left.compareTo(b.rect.left));
    }

    return rows;
  }

  /// 행 데이터에서 플레이어별 프레임 정보를 파싱
  List<OcrPlayerResult> _parsePlayerRows(List<_TextRow> rows) {
    if (rows.isEmpty) return [];

    // 프레임 헤더 행 감지 (1~10 숫자가 연속으로 나오는 행)
    int? headerRowIdx;
    for (int i = 0; i < rows.length; i++) {
      if (_isFrameHeaderRow(rows[i])) {
        headerRowIdx = i;
        break;
      }
    }

    // 플레이어 이름이 포함된 행 감지 (한글 텍스트)
    final playerGroups = <_PlayerRowGroup>[];

    for (int i = 0; i < rows.length; i++) {
      if (i == headerRowIdx) continue;

      final koreanName = _extractKoreanName(rows[i]);
      if (koreanName != null) {
        // 이름이 있는 행 = 핀 카운트 행
        // 바로 다음 행 = 누적 점수 행 (숫자만 있는 행)
        _TextRow? cumulativeRow;
        if (i + 1 < rows.length && _isNumericRow(rows[i + 1])) {
          cumulativeRow = rows[i + 1];
        }

        playerGroups.add(_PlayerRowGroup(
          name: koreanName,
          pinCountRow: rows[i],
          cumulativeRow: cumulativeRow,
        ));
      }
    }

    // 헤더 행에서 프레임 열 위치 매핑
    List<double>? columnPositions;
    if (headerRowIdx != null) {
      columnPositions = _extractColumnPositions(rows[headerRowIdx]);
    }

    return playerGroups
        .map((g) => _parsePlayerGroup(g, columnPositions))
        .toList();
  }

  /// 프레임 헤더 행인지 확인 (1~10 숫자 시퀀스)
  bool _isFrameHeaderRow(_TextRow row) {
    final numbers = <int>[];
    for (final e in row.elements) {
      final n = int.tryParse(e.text.trim());
      if (n != null) numbers.add(n);
    }
    if (numbers.length < 5) return false;

    // 1~10 범위의 연속 숫자가 5개 이상이면 헤더 행
    int matchCount = 0;
    for (int i = 1; i <= 10; i++) {
      if (numbers.contains(i)) matchCount++;
    }
    return matchCount >= 5;
  }

  /// 행에서 한글 이름 추출
  String? _extractKoreanName(_TextRow row) {
    final koreanRegex = RegExp(r'[가-힣]{2,}');
    for (final e in row.elements) {
      final match = koreanRegex.firstMatch(e.text);
      if (match != null) return match.group(0);
    }
    return null;
  }

  /// 행이 숫자 위주인지 확인 (누적 점수 행)
  bool _isNumericRow(_TextRow row) {
    int numericCount = 0;
    for (final e in row.elements) {
      if (int.tryParse(e.text.trim()) != null) numericCount++;
    }
    return row.elements.isNotEmpty &&
        numericCount > row.elements.length * 0.5;
  }

  /// 헤더 행에서 각 프레임의 X좌표 위치 추출
  List<double> _extractColumnPositions(_TextRow headerRow) {
    final positions = <double>[];
    for (final e in headerRow.elements) {
      final n = int.tryParse(e.text.trim());
      if (n != null && n >= 1 && n <= 10) {
        positions.add(e.rect.center.dx);
      }
    }
    positions.sort();
    return positions;
  }

  /// 텍스트 요소를 가장 가까운 프레임 열에 매핑
  int? _matchToColumn(double x, List<double> columnPositions) {
    if (columnPositions.isEmpty) return null;

    double minDist = double.infinity;
    int bestIdx = 0;
    for (int i = 0; i < columnPositions.length; i++) {
      final dist = (x - columnPositions[i]).abs();
      if (dist < minDist) {
        minDist = dist;
        bestIdx = i;
      }
    }

    // 프레임 열 간격의 150%를 초과하면 매칭 실패
    if (columnPositions.length > 1) {
      double avgGap = 0;
      for (int i = 1; i < columnPositions.length; i++) {
        avgGap += columnPositions[i] - columnPositions[i - 1];
      }
      avgGap /= (columnPositions.length - 1);
      if (minDist > avgGap * 1.5) return null;
    }

    return bestIdx + 1; // 1-based 프레임 번호
  }

  /// 플레이어 그룹을 파싱하여 OcrPlayerResult 생성
  OcrPlayerResult _parsePlayerGroup(
    _PlayerRowGroup group,
    List<double>? columnPositions,
  ) {
    final frames = <int, OcrFrameResult>{};

    // 1. 누적 점수 파싱 (신뢰도 높음)
    final cumulativeScores = <int, int>{};
    if (group.cumulativeRow != null) {
      _parseCumulativeScores(
        group.cumulativeRow!,
        columnPositions,
        cumulativeScores,
      );
    }

    // 2. 핀 카운트 파싱
    _parsePinCounts(
      group.pinCountRow,
      group.name,
      columnPositions,
      frames,
    );

    // 3. 누적 점수를 프레임에 매핑
    for (final entry in cumulativeScores.entries) {
      final frameNum = entry.key;
      if (frames.containsKey(frameNum)) {
        frames[frameNum] = frames[frameNum]!.copyWith(
          cumulativeScore: entry.value,
        );
      } else {
        frames[frameNum] = OcrFrameResult(
          frameNumber: frameNum,
          cumulativeScore: entry.value,
          confidence: OcrConfidence.low,
        );
      }
    }

    // 4. 누적 점수로 프레임 데이터 보완/검증
    _validateAndFillFromCumulative(frames, cumulativeScores);

    final sortedFrames = frames.values.toList()
      ..sort((a, b) => a.frameNumber.compareTo(b.frameNumber));

    return OcrPlayerResult(
      playerName: group.name,
      frames: sortedFrames,
    );
  }

  /// 누적 점수 행 파싱
  void _parseCumulativeScores(
    _TextRow row,
    List<double>? columnPositions,
    Map<int, int> result,
  ) {
    // 열 위치 기반 매핑
    if (columnPositions != null && columnPositions.isNotEmpty) {
      for (final e in row.elements) {
        final score = int.tryParse(e.text.trim());
        if (score == null || score < 0 || score > 300) continue;

        final frameNum = _matchToColumn(e.rect.center.dx, columnPositions);
        if (frameNum != null) {
          result[frameNum] = score;
        }
      }
    } else {
      // 열 위치를 모를 경우, 좌→우 순서대로 1~10프레임에 매핑
      final scores = <int>[];
      for (final e in row.elements) {
        final score = int.tryParse(e.text.trim());
        if (score != null && score >= 0 && score <= 300) {
          scores.add(score);
        }
      }
      // 누적 점수는 단조 증가해야 함
      final validScores = _filterMonotonic(scores);
      for (int i = 0; i < min(validScores.length, 10); i++) {
        result[i + 1] = validScores[i];
      }
    }
  }

  /// 단조 증가하는 부분 수열 추출
  List<int> _filterMonotonic(List<int> scores) {
    if (scores.isEmpty) return [];
    final result = <int>[scores.first];
    for (int i = 1; i < scores.length; i++) {
      if (scores[i] >= result.last) {
        result.add(scores[i]);
      }
    }
    return result;
  }

  /// 핀 카운트 행에서 프레임 데이터 파싱
  void _parsePinCounts(
    _TextRow row,
    String playerName,
    List<double>? columnPositions,
    Map<int, OcrFrameResult> frames,
  ) {
    // 이름과 프레임 번호 등 불필요한 요소를 제외한 핀 카운트 요소 수집
    final pinElements = <_OcrElement>[];
    final koreanRegex = RegExp(r'[가-힣]');
    final skipTexts = {'K', 'LANE', 'LEAGUE', 'NORMAL'};

    for (final e in row.elements) {
      final text = e.text.trim();
      if (text.isEmpty) continue;
      if (koreanRegex.hasMatch(text)) continue;
      if (skipTexts.contains(text.toUpperCase())) continue;
      pinElements.add(e);
    }

    if (columnPositions != null && columnPositions.isNotEmpty) {
      _parsePinCountsByColumn(pinElements, columnPositions, frames);
    } else {
      _parsePinCountsBySequence(pinElements, frames);
    }
  }

  /// 열 위치 기반으로 핀 카운트를 프레임에 매핑
  void _parsePinCountsByColumn(
    List<_OcrElement> elements,
    List<double> columnPositions,
    Map<int, OcrFrameResult> frames,
  ) {
    // 각 프레임 열에 속하는 요소를 그룹핑
    final frameElements = <int, List<_OcrElement>>{};
    for (final e in elements) {
      final frameNum = _matchToColumn(e.rect.center.dx, columnPositions);
      if (frameNum == null) continue;
      frameElements.putIfAbsent(frameNum, () => []).add(e);
    }

    for (final entry in frameElements.entries) {
      final frameNum = entry.key;
      final elems = entry.value;
      elems.sort((a, b) => a.rect.left.compareTo(b.rect.left));

      final throws = <int?>[];
      for (final e in elems) {
        throws.add(_parsePinValue(e.text.trim()));
      }

      frames[frameNum] = _buildFrameFromThrows(
        frameNum,
        throws,
        elems.map((e) => e.text.trim()).toList(),
      );
    }
  }

  /// 열 위치 없이 순서대로 핀 카운트 파싱
  void _parsePinCountsBySequence(
    List<_OcrElement> elements,
    Map<int, OcrFrameResult> frames,
  ) {
    int currentFrame = 1;

    final throwValues = <int?>[];
    final throwTexts = <String>[];

    for (final e in elements) {
      throwValues.add(_parsePinValue(e.text.trim()));
      throwTexts.add(e.text.trim());
    }

    int i = 0;
    while (i < throwValues.length && currentFrame <= 10) {
      if (currentFrame < 10) {
        final first = throwValues[i];
        if (_isStrikeText(throwTexts[i]) || first == 10) {
          frames[currentFrame] = OcrFrameResult(
            frameNumber: currentFrame,
            firstThrow: 10,
            confidence: first != null ? OcrConfidence.high : OcrConfidence.low,
          );
          currentFrame++;
          i++;
        } else {
          final second = (i + 1 < throwValues.length) ? throwValues[i + 1] : null;
          final secondText = (i + 1 < throwTexts.length) ? throwTexts[i + 1] : '';
          int? secondVal = second;

          if (_isSpareText(secondText) && first != null) {
            secondVal = 10 - first;
          }

          frames[currentFrame] = OcrFrameResult(
            frameNumber: currentFrame,
            firstThrow: first,
            secondThrow: secondVal,
            confidence: (first != null && secondVal != null)
                ? OcrConfidence.high
                : OcrConfidence.low,
          );
          currentFrame++;
          i += 2;
        }
      } else {
        // 10프레임
        final remaining = throwValues.sublist(i);
        final remainingTexts = throwTexts.sublist(i);

        int? first, second, third;
        if (remaining.isNotEmpty) {
          first = _isStrikeText(remainingTexts[0]) ? 10 : remaining[0];
        }
        if (remaining.length > 1) {
          if (_isStrikeText(remainingTexts[1])) {
            second = 10;
          } else if (_isSpareText(remainingTexts[1]) && first != null && first < 10) {
            second = 10 - first;
          } else {
            second = remaining[1];
          }
        }
        if (remaining.length > 2) {
          if (_isStrikeText(remainingTexts[2])) {
            third = 10;
          } else if (_isSpareText(remainingTexts[2])) {
            final prev = (first == 10 && second == 10) ? 0 : (first == 10 ? (second ?? 0) : 0);
            third = 10 - prev;
          } else {
            third = remaining[2];
          }
        }

        frames[currentFrame] = OcrFrameResult(
          frameNumber: 10,
          firstThrow: first,
          secondThrow: second,
          thirdThrow: third,
          confidence: first != null ? OcrConfidence.high : OcrConfidence.low,
        );
        break;
      }
    }
  }

  /// 핀 카운트 텍스트를 숫자로 변환
  int? _parsePinValue(String text) {
    if (text.isEmpty) return null;
    final upper = text.toUpperCase();

    // 스트라이크
    if (upper == 'X' || upper == 'x') return 10;
    // 거터/미스
    if (upper == '-' || upper == '0') return 0;
    // 숫자
    final n = int.tryParse(text);
    if (n != null && n >= 0 && n <= 10) return n;
    // 스페어는 이전 투구 없이 해석 불가 → null
    if (upper == '/') return null;

    return null;
  }

  bool _isStrikeText(String text) {
    final upper = text.toUpperCase().trim();
    return upper == 'X' || upper == 'x';
  }

  bool _isSpareText(String text) {
    return text.trim() == '/';
  }

  /// throw 값들로 OcrFrameResult 생성
  OcrFrameResult _buildFrameFromThrows(
    int frameNumber,
    List<int?> throws,
    List<String> texts,
  ) {
    if (frameNumber < 10) {
      int? first, second;
      if (throws.isNotEmpty) {
        first = _isStrikeText(texts[0]) ? 10 : throws[0];
      }
      if (throws.length > 1 && first != 10) {
        if (_isSpareText(texts[1]) && first != null) {
          second = 10 - first;
        } else {
          second = throws[1];
        }
      }
      return OcrFrameResult(
        frameNumber: frameNumber,
        firstThrow: first,
        secondThrow: first == 10 ? null : second,
        confidence: first != null ? OcrConfidence.high : OcrConfidence.low,
      );
    } else {
      int? first, second, third;
      if (throws.isNotEmpty) {
        first = _isStrikeText(texts[0]) ? 10 : throws[0];
      }
      if (throws.length > 1) {
        if (_isStrikeText(texts[1])) {
          second = 10;
        } else if (_isSpareText(texts[1]) && first != null && first < 10) {
          second = 10 - first;
        } else {
          second = throws[1];
        }
      }
      if (throws.length > 2) {
        if (_isStrikeText(texts[2])) {
          third = 10;
        } else {
          third = throws[2];
        }
      }
      return OcrFrameResult(
        frameNumber: 10,
        firstThrow: first,
        secondThrow: second,
        thirdThrow: third,
        confidence: first != null ? OcrConfidence.high : OcrConfidence.low,
      );
    }
  }

  /// 누적 점수로 프레임 데이터 보완/검증
  void _validateAndFillFromCumulative(
    Map<int, OcrFrameResult> frames,
    Map<int, int> cumulativeScores,
  ) {
    // 누적 점수가 있지만 프레임 데이터가 없는 경우,
    // 차이값으로 오픈 프레임(보너스 없는)을 추정
    for (int i = 1; i <= 10; i++) {
      if (!cumulativeScores.containsKey(i)) continue;

      final cumScore = cumulativeScores[i]!;
      final prevCum = (i > 1 && cumulativeScores.containsKey(i - 1))
          ? cumulativeScores[i - 1]!
          : 0;
      final frameDiff = cumScore - prevCum;

      if (!frames.containsKey(i)) {
        // 프레임 데이터 없음 → 차이값으로 추정 시도
        if (i < 10 && frameDiff <= 9 && frameDiff >= 0) {
          // 오픈 프레임 확정 (보너스 없이 9 이하면 스트라이크/스페어 아님)
          frames[i] = OcrFrameResult(
            frameNumber: i,
            cumulativeScore: cumScore,
            confidence: OcrConfidence.low,
          );
        } else {
          frames[i] = OcrFrameResult(
            frameNumber: i,
            cumulativeScore: cumScore,
            confidence: OcrConfidence.unrecognized,
          );
        }
      } else {
        // 프레임 데이터와 누적 점수 교차 검증
        final frame = frames[i]!;
        if (frame.cumulativeScore == null) {
          frames[i] = frame.copyWith(cumulativeScore: cumScore);
        }
      }
    }
  }
}

// --- 내부 헬퍼 클래스 ---

class _OcrElement {
  final String text;
  final ui.Rect rect;

  const _OcrElement({required this.text, required this.rect});
}

class _TextRow {
  final List<_OcrElement> elements;

  _TextRow({required this.elements});

  double get centerY {
    if (elements.isEmpty) return 0;
    return elements.map((e) => e.rect.center.dy).reduce((a, b) => a + b) /
        elements.length;
  }

  double get avgHeight {
    if (elements.isEmpty) return 20;
    return elements.map((e) => e.rect.height).reduce((a, b) => a + b) /
        elements.length;
  }
}

class _PlayerRowGroup {
  final String name;
  final _TextRow pinCountRow;
  final _TextRow? cumulativeRow;

  const _PlayerRowGroup({
    required this.name,
    required this.pinCountRow,
    this.cumulativeRow,
  });
}
