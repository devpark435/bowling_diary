import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:bowling_diary/features/record/data/services/cumulative_score_validator.dart';
import 'package:bowling_diary/features/record/data/services/gemini_ocr_service.dart';
// ignore: unused_import
import 'package:bowling_diary/features/record/data/services/score_cell_analyzer.dart';
import 'package:bowling_diary/features/record/domain/entities/ocr_result.dart';

class BowlingOcrService {
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.korean);
  final ScoreCellAnalyzer _cellAnalyzer = ScoreCellAnalyzer();
  final CumulativeScoreValidator _validator = CumulativeScoreValidator();
  final GeminiOcrService _geminiService = GeminiOcrService();

  Future<OcrResult> processImage(String imagePath) async {
    // 1단계: Gemini API 시도
    try {
      debugPrint('[OCR] === Gemini OCR 시도 ===');
      final players = await _geminiService.processImage(imagePath);
      debugPrint('[OCR] Gemini 성공 - ${players.length}명 감지');
      return OcrResult(players: players, imagePath: imagePath);
    } on GeminiNotConfiguredException {
      debugPrint('[OCR] Gemini 키 미설정 → ML Kit으로 직접 진행');
    } catch (e) {
      debugPrint('[OCR] Gemini 실패 ($e) → ML Kit 폴백');
      final mlkitResult = await _runMlKit(imagePath);
      return OcrResult(
        players: mlkitResult.players,
        imagePath: imagePath,
        usedGeminiFallback: true,
      );
    }

    // 2단계: API 키 미설정 시 ML Kit 직접 실행 (폴백 아님)
    return _runMlKit(imagePath);
  }

  /// ML Kit 기반 OCR 파이프라인
  Future<OcrResult> _runMlKit(String imagePath) async {
    try {
      debugPrint('[OCR] === ML Kit 이미지 처리 시작 ===');
      debugPrint('[OCR] 이미지 경로: $imagePath');

      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      debugPrint('[OCR] ML Kit 인식 완료 - 블록 수: ${recognizedText.blocks.length}');
      for (final block in recognizedText.blocks) {
        debugPrint('[OCR]   블록: "${block.text}" '
            '(${block.boundingBox.left.toInt()}, ${block.boundingBox.top.toInt()}) '
            '${block.boundingBox.width.toInt()}x${block.boundingBox.height.toInt()}');
      }

      final elements = _extractAllElements(recognizedText);
      debugPrint('[OCR] 추출된 텍스트 요소 수: ${elements.length}');
      if (elements.isEmpty) {
        debugPrint('[OCR] !! 텍스트 요소가 0개 - 이미지에서 글자를 전혀 인식하지 못함');
        return OcrResult(players: [], imagePath: imagePath);
      }

      for (final e in elements) {
        debugPrint('[OCR]   요소: "${e.text}" '
            'at (${e.rect.left.toInt()}, ${e.rect.top.toInt()}) '
            '${e.rect.width.toInt()}x${e.rect.height.toInt()}');
      }

      final rows = _groupIntoRows(elements);
      debugPrint('[OCR] 행 그룹핑 결과: ${rows.length}개 행');
      for (int i = 0; i < rows.length; i++) {
        final texts = rows[i].elements.map((e) => e.text).join(' | ');
        debugPrint('[OCR]   행[$i] Y=${rows[i].centerY.toInt()}: $texts');
      }

      final players = await _parsePlayerRows(rows, imagePath);
      debugPrint('[OCR] 감지된 플레이어 수: ${players.length}');
      for (final p in players) {
        debugPrint('[OCR]   플레이어: "${p.playerName}" - '
            '프레임 ${p.frames.length}개, '
            '완료 ${p.completedFrameCount}개, '
            '총점 ${p.totalScore ?? "없음"}');
      }

      debugPrint('[OCR] === ML Kit 처리 완료 ===');
      return OcrResult(players: players, imagePath: imagePath);
    } catch (e, stackTrace) {
      debugPrint('[OCR] !! ML Kit 처리 중 예외 발생: $e');
      debugPrint('[OCR] $stackTrace');
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
  Future<List<OcrPlayerResult>> _parsePlayerRows(List<_TextRow> rows, String imagePath) async {
    if (rows.isEmpty) {
      debugPrint('[OCR] !! 행이 0개 - 파싱할 데이터 없음');
      return [];
    }

    // 프레임 헤더 행 감지 (1~10 숫자가 연속으로 나오는 행)
    int? headerRowIdx;
    for (int i = 0; i < rows.length; i++) {
      if (_isFrameHeaderRow(rows[i])) {
        headerRowIdx = i;
        break;
      }
    }
    debugPrint('[OCR] 프레임 헤더 행: ${headerRowIdx != null ? "행[$headerRowIdx]에서 발견" : "!! 미발견"}');

    // 1차: 한글 이름으로 플레이어 감지
    var playerGroups = _detectPlayersByKoreanName(rows, headerRowIdx);

    // 2차: 한글 이름 실패 시, "K" 마커 + 행 패턴으로 감지
    if (playerGroups.isEmpty) {
      debugPrint('[OCR] 한글 이름 감지 실패 → "K" 마커 기반 감지 시도');
      playerGroups = _detectPlayersByMarker(rows, headerRowIdx);
    }

    // 3차: 누적 점수 행 패턴으로 감지 (범용 - K 마커 없는 볼링장 대응)
    if (playerGroups.isEmpty) {
      debugPrint('[OCR] "K" 마커 감지 실패 → 누적 점수 패턴 기반 감지 시도');
      playerGroups = _detectPlayersByCumulativePattern(rows, headerRowIdx);
    }

    if (playerGroups.isEmpty) {
      debugPrint('[OCR] !! 모든 감지 방법 실패');
      for (int i = 0; i < rows.length; i++) {
        final texts = rows[i].elements.map((e) => '"${e.text}"').join(', ');
        debugPrint('[OCR]    행[$i]: $texts');
      }
    }

    // 헤더 행에서 프레임 열 위치 매핑
    List<double>? columnPositions;
    if (headerRowIdx != null) {
      columnPositions = _extractColumnPositions(rows[headerRowIdx]);
      debugPrint('[OCR] 열 위치: ${columnPositions.map((p) => p.toInt()).toList()}');
    }

    final results = <OcrPlayerResult>[];
    for (final g in playerGroups) {
      results.add(await _parsePlayerGroup(g, columnPositions, imagePath));
    }
    return results;
  }

  /// 1차 감지: 한글 이름으로 플레이어 행 찾기
  List<_PlayerRowGroup> _detectPlayersByKoreanName(
    List<_TextRow> rows,
    int? headerRowIdx,
  ) {
    final groups = <_PlayerRowGroup>[];

    for (int i = 0; i < rows.length; i++) {
      if (i == headerRowIdx) continue;

      final koreanName = _extractKoreanName(rows[i]);
      if (koreanName != null) {
        debugPrint('[OCR] 한글 이름 발견: "$koreanName" (행[$i])');

        _TextRow? cumulativeRow;
        if (i + 1 < rows.length && _isNumericRow(rows[i + 1])) {
          cumulativeRow = rows[i + 1];
        }

        groups.add(_PlayerRowGroup(
          name: koreanName,
          pinCountRow: rows[i],
          cumulativeRow: cumulativeRow,
        ));
      }
    }

    return groups;
  }

  /// 2차 감지: "K" 마커 또는 행 패턴으로 플레이어 찾기
  /// 볼링장 모니터에서 한글 이름이 OCR로 인식 안 될 때 사용
  List<_PlayerRowGroup> _detectPlayersByMarker(
    List<_TextRow> rows,
    int? headerRowIdx,
  ) {
    final groups = <_PlayerRowGroup>[];
    final usedRows = <int>{};
    if (headerRowIdx != null) usedRows.add(headerRowIdx);

    // "K" 마커가 있는 행 = 핀 카운트 행(플레이어 시작점)
    // 볼링장 모니터에서 각 플레이어 행 왼쪽에 "K" 레이블이 표시됨
    int playerNum = 0;
    for (int i = 0; i < rows.length; i++) {
      if (usedRows.contains(i)) continue;

      final hasKMarker = _hasPlayerMarker(rows[i]);
      if (!hasKMarker) continue;

      playerNum++;
      usedRows.add(i);

      // 이 행에서 한글 이름 추출 시도 (실패하면 "플레이어 N")
      final name = _extractKoreanName(rows[i]) ?? '플레이어 $playerNum';
      debugPrint('[OCR] "K" 마커 감지 → "$name" (행[$i])');

      // 다음 행이 누적 점수 행인지 확인
      _TextRow? cumulativeRow;
      if (i + 1 < rows.length && !usedRows.contains(i + 1)) {
        if (_isNumericRow(rows[i + 1])) {
          cumulativeRow = rows[i + 1];
          usedRows.add(i + 1);
          final cumTexts = cumulativeRow.elements.map((e) => e.text).join(', ');
          debugPrint('[OCR]   누적 점수 행: 행[${i + 1}] → $cumTexts');
        }
      }

      // "K"만 단독 행인 경우: 핀 카운트가 별도 행에 있을 수 있음
      // 행[3]: "K" (단독) → 다음 행이 누적 점수면, 핀 카운트 행이 없는 것
      if (rows[i].elements.length <= 1 && cumulativeRow != null) {
        debugPrint('[OCR]   "K" 단독 행 → 핀 카운트 없이 누적 점수만 사용');
        groups.add(_PlayerRowGroup(
          name: name,
          pinCountRow: rows[i],
          cumulativeRow: cumulativeRow,
        ));
        continue;
      }

      // "K"만 단독이고 다음 2행이 핀+누적일 수 있음
      if (rows[i].elements.length <= 1 && cumulativeRow == null) {
        // 다음 행 = 핀 카운트, 그 다음 행 = 누적 점수
        if (i + 1 < rows.length && !usedRows.contains(i + 1)) {
          final pinRow = rows[i + 1];
          usedRows.add(i + 1);
          _TextRow? cumRow;
          if (i + 2 < rows.length && !usedRows.contains(i + 2) && _isNumericRow(rows[i + 2])) {
            cumRow = rows[i + 2];
            usedRows.add(i + 2);
          }
          debugPrint('[OCR]   "K" 단독 → 핀: 행[${i + 1}], 누적: ${cumRow != null ? "행[${i + 2}]" : "없음"}');
          groups.add(_PlayerRowGroup(
            name: name,
            pinCountRow: pinRow,
            cumulativeRow: cumRow,
          ));
          continue;
        }
      }

      groups.add(_PlayerRowGroup(
        name: name,
        pinCountRow: rows[i],
        cumulativeRow: cumulativeRow,
      ));
    }

    return groups;
  }

  /// 행에 "K" 같은 플레이어 마커가 있는지 확인
  bool _hasPlayerMarker(_TextRow row) {
    for (final e in row.elements) {
      final text = e.text.trim().toUpperCase();
      if (text == 'K') return true;
    }
    return false;
  }

  /// 3차 감지: 누적 점수 행 패턴으로 플레이어 찾기
  /// 단조 증가 + 0~300 범위 + 숫자 3개 이상인 행을 누적 점수 행으로 판별
  List<_PlayerRowGroup> _detectPlayersByCumulativePattern(
    List<_TextRow> rows,
    int? headerRowIdx,
  ) {
    final groups = <_PlayerRowGroup>[];
    final usedRows = <int>{};
    if (headerRowIdx != null) usedRows.add(headerRowIdx);

    int playerNum = 0;
    for (int i = 0; i < rows.length; i++) {
      if (usedRows.contains(i)) continue;

      if (_isCumulativeScoreRow(rows[i])) {
        playerNum++;
        usedRows.add(i);

        // 바로 위 행을 핀 카운트 행으로 사용 (사용되지 않은 경우)
        _TextRow? pinCountRow;
        if (i - 1 >= 0 && !usedRows.contains(i - 1) && i - 1 != headerRowIdx) {
          pinCountRow = rows[i - 1];
          usedRows.add(i - 1);
        }

        final name = (pinCountRow != null ? _extractKoreanName(pinCountRow) : null)
            ?? '플레이어 $playerNum';

        debugPrint('[OCR] 누적 점수 패턴 감지 → "$name" (누적: 행[$i]${pinCountRow != null ? ", 핀: 행[${i - 1}]" : ""})');

        groups.add(_PlayerRowGroup(
          name: name,
          pinCountRow: pinCountRow ?? rows[i],
          cumulativeRow: rows[i],
        ));
      }
    }

    return groups;
  }

  /// 행이 누적 점수 행인지 판별
  /// 조건: 숫자 3개 이상 + 단조 증가 + 0~300 범위
  bool _isCumulativeScoreRow(_TextRow row) {
    final scores = <int>[];
    for (final e in row.elements) {
      final extracted = _extractScoresFromText(e.text);
      scores.addAll(extracted);
    }
    if (scores.length < 3) return false;

    final monotonic = _filterMonotonic(scores);
    // 원본의 70% 이상이 단조 증가 패턴을 유지하고, 마지막 값이 10 이상이면 누적 점수 행
    return monotonic.length >= scores.length * 0.7 &&
        monotonic.length >= 3 &&
        monotonic.last >= 10 &&
        monotonic.last <= 300;
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
  Future<OcrPlayerResult> _parsePlayerGroup(
    _PlayerRowGroup group,
    List<double>? columnPositions,
    String imagePath,
  ) async {
    debugPrint('[OCR] --- "${group.name}" 파싱 시작 ---');
    final frames = <int, OcrFrameResult>{};

    // 1. 누적 점수 파싱 (신뢰도 높음)
    final cumulativeScores = <int, int>{};
    if (group.cumulativeRow != null) {
      _parseCumulativeScores(
        group.cumulativeRow!,
        columnPositions,
        cumulativeScores,
      );
      debugPrint('[OCR]   누적 점수 파싱 결과: $cumulativeScores');
    } else {
      debugPrint('[OCR]   !! 누적 점수 행 없음');
    }

    // 2. 핀 카운트 파싱
    _parsePinCounts(
      group.pinCountRow,
      group.name,
      columnPositions,
      frames,
    );
    debugPrint('[OCR]   핀 카운트 파싱 결과: ${frames.length}개 프레임');
    for (final entry in frames.entries) {
      final f = entry.value;
      debugPrint('[OCR]     프레임${f.frameNumber}: '
          '1투=${f.firstThrow} 2투=${f.secondThrow} 3투=${f.thirdThrow} '
          '신뢰도=${f.confidence.name}');
    }

    // 3. 셀 이미지 분석 (스트라이크/스페어 그래픽 감지)
    // TODO: CellAnalyzer crop 좌표 버그로 전 셀 100% 스트라이크 오판정 중 → 임시 비활성화
    // if (columnPositions != null && columnPositions.isNotEmpty) {
    //   final cellResults = await _analyzeCellImages(
    //     imagePath: imagePath,
    //     pinCountRow: group.pinCountRow,
    //     columnPositions: columnPositions,
    //   );
    //   if (cellResults.isNotEmpty) {
    //     debugPrint('[OCR]   셀 이미지 분석 결과: ${cellResults.length}개');
    //     for (final cr in cellResults) {
    //       debugPrint('[OCR]     $cr');
    //     }
    //     _applyCellAnalysisResults(frames, cellResults);
    //   }
    // }

    // 4. 누적 점수를 프레임에 매핑
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

    // 5. 기본 누적 점수 보완 (누적 점수만 있고 프레임 데이터 없는 경우)
    _validateAndFillFromCumulative(frames, cumulativeScores);

    // 6. CumulativeScoreValidator로 교차 검증 + 역추론 보정
    final frameList = frames.values.toList()
      ..sort((a, b) => a.frameNumber.compareTo(b.frameNumber));

    final validationResult = _validator.validate(
      frames: frameList,
      cumulativeScores: cumulativeScores,
    );

    debugPrint('[OCR]   검증 결과: 불일치 ${validationResult.mismatchedFrames.length}개, '
        '완전 검증=${validationResult.isFullyValidated}');
    if (validationResult.mismatchedFrames.isNotEmpty) {
      debugPrint('[OCR]   불일치 프레임: ${validationResult.mismatchedFrames}');
    }

    // 7. 최종 결과 조합
    final sortedFrames = validationResult.correctedFrames;

    debugPrint('[OCR] --- "${group.name}" 최종: ${sortedFrames.length}개 프레임 ---');
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
    // 먼저 각 요소에서 숫자를 추출 (합쳐진 숫자, 파이프 문자 처리)
    final scores = <int>[];
    for (final e in row.elements) {
      final extracted = _extractScoresFromText(e.text);
      scores.addAll(extracted);
    }

    debugPrint('[OCR]   누적 점수 추출 원본: $scores');

    // 누적 점수는 단조 증가해야 함
    final validScores = _filterMonotonic(scores);
    debugPrint('[OCR]   단조 증가 필터 후: $validScores');
    _mapCumulativeScoresToFrames(validScores, result);
    debugPrint('[OCR]   볼링 규칙 매핑 후: $result');
  }

  /// 텍스트에서 누적 점수 숫자들을 추출
  /// "102111|" → [102, 111], "85|105" → [85, 105], "152172" → [152, 172]
  List<int> _extractScoresFromText(String text) {
    // 파이프, 슬래시 등 구분자로 먼저 분리
    final cleaned = text.replaceAll(RegExp(r'[|/\\]'), ' ');
    final parts = cleaned.split(RegExp(r'\s+'));

    final results = <int>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      // 숫자만 추출
      final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.isEmpty) continue;

      final n = int.tryParse(digitsOnly);
      if (n != null && n >= 0 && n <= 300) {
        results.add(n);
        continue;
      }

      // 300 초과면 합쳐진 숫자 → 2~3자리씩 분리 시도
      if (n != null && n > 300) {
        results.addAll(_splitConcatenatedScores(digitsOnly));
      }
    }
    return results;
  }

  /// 단조증가 제약 기반 백트래킹으로 합쳐진 점수를 분리
  /// "939" (prevScore=0) → [9, 39], "152172" → [152, 172]
  /// 길이 3→2→1 순서로 시도하되, 단조증가 제약을 만족 못하면 백트래킹
  List<int> _splitConcatenatedScores(String digits, {int prevScore = 0}) {
    final result = <int>[];
    final success = _splitRecursive(digits, 0, prevScore, result);
    debugPrint('[OCR]     합쳐진 숫자 분리 (prevScore=$prevScore): "$digits" → '
        '${success ? result.toString() : "분리 실패 []"}');
    return success ? result : [];
  }

  /// [_splitConcatenatedScores] 의 백트래킹 구현체
  bool _splitRecursive(String digits, int start, int prevScore, List<int> result) {
    if (start == digits.length) return true;

    // 3자리 → 2자리 → 1자리 순서로 시도 (큰 단위 우선, 실패 시 백트래킹)
    for (final len in [3, 2, 1]) {
      if (start + len > digits.length) continue;
      final n = int.tryParse(digits.substring(start, start + len));
      if (n == null || n <= prevScore || n > 300) continue;

      result.add(n);
      if (_splitRecursive(digits, start + len, n, result)) return true;
      result.removeLast();
    }
    return false;
  }

  /// 단조 증가하는 부분 수열 추출
  List<int> _filterMonotonic(List<int> scores) {
    if (scores.isEmpty) return [];
    final n = scores.length;
    final dp = List<int>.filled(n, 1);
    final prev = List<int>.filled(n, -1);

    int bestEnd = 0;
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < i; j++) {
        if (scores[j] <= scores[i] && dp[j] + 1 > dp[i]) {
          dp[i] = dp[j] + 1;
          prev[i] = j;
        }
      }
      if (dp[i] > dp[bestEnd]) {
        bestEnd = i;
      }
    }

    final result = <int>[];
    int idx = bestEnd;
    while (idx != -1) {
      result.add(scores[idx]);
      idx = prev[idx];
    }
    return result.reversed.toList();
  }

  /// 누적 점수를 프레임 번호에 매핑 (볼링 규칙 반영)
  void _mapCumulativeScoresToFrames(List<int> scores, Map<int, int> result) {
    int minFrame = 1;
    int prevScore = 0;

    for (final score in scores) {
      if (score < prevScore || score < 0 || score > 300) continue;

      int frame = max(minFrame, (score + 29) ~/ 30); // ceil(score / 30)
      while (frame <= 10 && score > frame * 30) {
        frame++;
      }
      if (frame > 10) continue;

      result[frame] = score;
      prevScore = score;
      minFrame = frame + 1;
      if (minFrame > 10) break;
    }
  }

  /// 핀 카운트 행에서 프레임 데이터 파싱
  void _parsePinCounts(
    _TextRow row,
    String playerName,
    List<double>? columnPositions,
    Map<int, OcrFrameResult> frames,
  ) {
    final allTexts = row.elements.map((e) => '"${e.text}"').join(', ');
    debugPrint('[OCR]   핀 카운트 행 원본 요소: $allTexts');

    // 이름과 프레임 번호 등 불필요한 요소를 제외한 핀 카운트 요소 수집
    final pinElements = <_OcrElement>[];
    final koreanRegex = RegExp(r'[가-힣]');
    final skipTexts = {'K', 'LANE', 'LEAGUE', 'NORMAL'};

    // F1 열 왼쪽 경계: 첫 번째 열 위치 - 열 간격의 절반
    // 이 경계보다 왼쪽에 있는 요소는 레인 번호 등 노이즈로 제외
    final double? leftBoundary = (columnPositions != null && columnPositions.length >= 2)
        ? columnPositions.first - (columnPositions[1] - columnPositions[0]) * 0.5
        : null;

    for (final e in row.elements) {
      final text = e.text.trim();
      if (text.isEmpty) { debugPrint('[OCR]     필터: "$text" → 빈 문자열 제외'); continue; }
      if (koreanRegex.hasMatch(text)) { debugPrint('[OCR]     필터: "$text" → 한글 포함 제외'); continue; }
      if (skipTexts.contains(text.toUpperCase())) { debugPrint('[OCR]     필터: "$text" → 스킵 키워드 제외'); continue; }
      if (leftBoundary != null && e.rect.center.dx < leftBoundary) {
        debugPrint('[OCR]     필터: "$text" → F1 왼쪽 영역 제외');
        continue;
      }
      pinElements.add(e);
    }

    final filteredTexts = pinElements.map((e) => '"${e.text}"').join(', ');
    debugPrint('[OCR]   필터링 후 핀 요소 ${pinElements.length}개: $filteredTexts');
    debugPrint('[OCR]   열 위치 매핑 방식: ${columnPositions != null && columnPositions.isNotEmpty ? "열 기반" : "순서 기반"}');

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
      // 스페어("/") 요소는 인접 스트라이크 그래픽으로 인해 바운딩 박스가
      // 좌측으로 늘어나 center가 잘못된 프레임에 매핑될 수 있음.
      // "/" 문자는 우측에 위치하므로 rect.right - height/2 를 기준 좌표로 사용
      double refX = e.rect.center.dx;
      if (e.text.trim().endsWith('/') && e.rect.width > e.rect.height) {
        refX = e.rect.right - e.rect.height * 0.5;
        debugPrint('[OCR]     스페어 열 보정: "${e.text}" '
            'center=${e.rect.center.dx.toInt()} → ref=${refX.toInt()}');
      }
      final frameNum = _matchToColumn(refX, columnPositions);
      if (frameNum == null) continue;
      frameElements.putIfAbsent(frameNum, () => []).add(e);
    }

    for (final entry in frameElements.entries) {
      final frameNum = entry.key;
      final elems = entry.value;
      elems.sort((a, b) => a.rect.left.compareTo(b.rect.left));

      final throwTexts = <String>[];
      for (final e in elems) {
        throwTexts.addAll(_splitPinToken(e.text.trim()));
      }

      final throws = <int?>[];
      for (final token in throwTexts) {
        throws.add(_parsePinValue(token));
      }

      frames[frameNum] = _buildFrameFromThrows(
        frameNum,
        throws,
        throwTexts,
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
      final tokens = _splitPinToken(e.text.trim());
      for (final token in tokens) {
        throwValues.add(_parsePinValue(token));
        throwTexts.add(token);
      }
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
    final upper = text.toUpperCase().trim().replaceAll('O', '0');

    // 스트라이크 (X 및 OCR 오인식 패턴: M, N, W, K 등 대각선 모양 글자)
    if (_isStrikeText(text)) return 10;
    // 거터/미스
    if (upper == '-' || upper == '0') return 0;
    // 스페어
    if (_isSpareText(text)) return null;
    // 숫자
    final n = int.tryParse(upper);
    if (n != null && n >= 0 && n <= 10) return n;

    debugPrint('[OCR]     핀 값 변환 실패: "$text"');
    return null;
  }

  /// OCR로 붙어서 인식된 핀 텍스트를 투구 단위로 분리
  List<String> _splitPinToken(String text) {
    final normalized = text.toUpperCase().trim().replaceAll('O', '0');
    if (normalized.isEmpty) return [];

    final isDigit = RegExp(r'^\d$');
    if (normalized.length == 2) {
      final a = normalized.substring(0, 1);
      final b = normalized.substring(1, 2);

      // 예: "72" -> "7", "2"
      if (isDigit.hasMatch(a) && isDigit.hasMatch(b)) return [a, b];
      // 예: "9/" -> "9", "/"
      if (isDigit.hasMatch(a) && b == '/') return [a, '/'];
      // 예: "M7" -> "M", "7" (M은 스트라이크 오인식)
      if (_isStrikeText(a) && isDigit.hasMatch(b)) return [a, b];
      // 예: "7X" -> "7", "X"
      if (isDigit.hasMatch(a) && _isStrikeText(b)) return [a, b];
    }

    return [normalized];
  }

  /// 스트라이크 텍스트 판별 (OCR 오인식 패턴 포함)
  /// "K"는 볼링장 모니터의 플레이어 마커이므로 제외 (필터에서 이미 제거됨)
  bool _isStrikeText(String text) {
    final upper = text.toUpperCase().trim();
    // 볼링 모니터의 대각선 스트라이크 마크가 OCR에서 다양한 글자로 인식됨
    const strikePatterns = {'X', 'M', 'N', 'W', 'Y', 'V'};
    return strikePatterns.contains(upper);
  }

  bool _isSpareText(String text) {
    final trimmed = text.trim();
    return trimmed == '/' || trimmed == '|' || trimmed == 'l';
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

  /// 핀 카운트 행의 바운딩 박스와 열 위치로 각 셀 영역을 계산하고 이미지 분석
  Future<List<CellAnalysisResult>> _analyzeCellImages({
    required String imagePath,
    required _TextRow pinCountRow,
    required List<double> columnPositions,
  }) async {
    if (columnPositions.length < 2) return [];

    // 열 간격 평균
    double avgGap = 0;
    for (int i = 1; i < columnPositions.length; i++) {
      avgGap += columnPositions[i] - columnPositions[i - 1];
    }
    avgGap /= (columnPositions.length - 1);

    // 핀 카운트 행의 Y 범위
    double minY = double.infinity, maxY = 0;
    for (final e in pinCountRow.elements) {
      if (e.rect.top < minY) minY = e.rect.top;
      if (e.rect.bottom > maxY) maxY = e.rect.bottom;
    }
    final cellHeight = maxY - minY;
    if (cellHeight < 5) return [];

    final cellWidth = avgGap * 0.45;

    final cells = <_CellInfo>[];
    for (int frameIdx = 0; frameIdx < columnPositions.length && frameIdx < 10; frameIdx++) {
      final frameNum = frameIdx + 1;
      final centerX = columnPositions[frameIdx];

      if (frameNum < 10) {
        // 1~9 프레임: 1투, 2투 (좌/우 반분할)
        cells.add(_CellInfo(
          rect: ui.Rect.fromCenter(
            center: ui.Offset(centerX - cellWidth * 0.5, (minY + maxY) / 2),
            width: cellWidth,
            height: cellHeight,
          ),
          frameNumber: frameNum,
          throwIndex: 0,
        ));
        cells.add(_CellInfo(
          rect: ui.Rect.fromCenter(
            center: ui.Offset(centerX + cellWidth * 0.5, (minY + maxY) / 2),
            width: cellWidth,
            height: cellHeight,
          ),
          frameNumber: frameNum,
          throwIndex: 1,
        ));
      } else {
        // 10프레임: 3분할
        final thirdWidth = cellWidth * 0.7;
        cells.add(_CellInfo(
          rect: ui.Rect.fromCenter(
            center: ui.Offset(centerX - thirdWidth, (minY + maxY) / 2),
            width: thirdWidth,
            height: cellHeight,
          ),
          frameNumber: 10,
          throwIndex: 0,
        ));
        cells.add(_CellInfo(
          rect: ui.Rect.fromCenter(
            center: ui.Offset(centerX, (minY + maxY) / 2),
            width: thirdWidth,
            height: cellHeight,
          ),
          frameNumber: 10,
          throwIndex: 1,
        ));
        cells.add(_CellInfo(
          rect: ui.Rect.fromCenter(
            center: ui.Offset(centerX + thirdWidth, (minY + maxY) / 2),
            width: thirdWidth,
            height: cellHeight,
          ),
          frameNumber: 10,
          throwIndex: 2,
        ));
      }
    }

    if (cells.isEmpty) return [];

    final results = <CellAnalysisResult>[];
    for (final cell in cells) {
      final result = await _cellAnalyzer.analyzeCell(
        imagePath: imagePath,
        cellRect: cell.rect,
        frameNumber: cell.frameNumber,
        throwIndex: cell.throwIndex,
      );
      results.add(result);
    }

    return results;
  }

  /// 셀 분석 결과를 프레임에 적용
  void _applyCellAnalysisResults(
    Map<int, OcrFrameResult> frames,
    List<CellAnalysisResult> cellResults,
  ) {
    // 프레임별로 셀 결과를 그룹핑
    final grouped = <int, List<CellAnalysisResult>>{};
    for (final cr in cellResults) {
      grouped.putIfAbsent(cr.frameNumber, () => []).add(cr);
    }

    for (final entry in grouped.entries) {
      final frameNum = entry.key;
      final cells = entry.value..sort((a, b) => a.throwIndex.compareTo(b.throwIndex));
      final existing = frames[frameNum];

      if (frameNum < 10) {
        _applyCellToNormalFrame(frames, frameNum, cells, existing);
      } else {
        _applyCellToTenthFrame(frames, cells, existing);
      }
    }
  }

  void _applyCellToNormalFrame(
    Map<int, OcrFrameResult> frames,
    int frameNum,
    List<CellAnalysisResult> cells,
    OcrFrameResult? existing,
  ) {
    final firstCell = cells.firstWhere((c) => c.throwIndex == 0,
        orElse: () => cells.first);
    final secondCell = cells.length > 1
        ? cells.firstWhere((c) => c.throwIndex == 1, orElse: () => cells.last)
        : null;

    int? firstThrow = existing?.firstThrow;
    int? secondThrow = existing?.secondThrow;
    var confidence = existing?.confidence ?? OcrConfidence.unrecognized;

    // 셀 = strike이고 ML Kit에서 스트라이크로 인식 못한 경우 → 셀 결과 적용
    if (firstCell.type == CellType.strike && firstCell.confidence > 0.5) {
      if (firstThrow != 10) {
        debugPrint('[OCR]   셀 분석 보정: F$frameNum 1투 → 스트라이크');
        firstThrow = 10;
        secondThrow = null;
        confidence = OcrConfidence.high;
      }
    }

    // 2투 셀 = spare
    if (secondCell != null &&
        secondCell.type == CellType.spare &&
        secondCell.confidence > 0.5 &&
        firstThrow != null &&
        firstThrow < 10) {
      final spareVal = 10 - firstThrow;
      if (secondThrow != spareVal) {
        debugPrint('[OCR]   셀 분석 보정: F$frameNum 2투 → 스페어($spareVal)');
        secondThrow = spareVal;
        confidence = OcrConfidence.high;
      }
    }

    if (firstThrow != existing?.firstThrow || secondThrow != existing?.secondThrow) {
      frames[frameNum] = OcrFrameResult(
        frameNumber: frameNum,
        firstThrow: firstThrow,
        secondThrow: secondThrow,
        cumulativeScore: existing?.cumulativeScore,
        confidence: confidence,
      );
    }
  }

  void _applyCellToTenthFrame(
    Map<int, OcrFrameResult> frames,
    List<CellAnalysisResult> cells,
    OcrFrameResult? existing,
  ) {
    int? first = existing?.firstThrow;
    int? second = existing?.secondThrow;
    int? third = existing?.thirdThrow;
    var confidence = existing?.confidence ?? OcrConfidence.unrecognized;

    for (final cell in cells) {
      if (cell.confidence < 0.5) continue;

      if (cell.throwIndex == 0 && cell.type == CellType.strike && first != 10) {
        first = 10;
        confidence = OcrConfidence.high;
      }
      if (cell.throwIndex == 1) {
        if (cell.type == CellType.strike && second != 10) {
          second = 10;
          confidence = OcrConfidence.high;
        } else if (cell.type == CellType.spare && first != null && first < 10) {
          second = 10 - first;
          confidence = OcrConfidence.high;
        }
      }
      if (cell.throwIndex == 2 && cell.type == CellType.strike && third != 10) {
        third = 10;
        confidence = OcrConfidence.high;
      }
    }

    frames[10] = OcrFrameResult(
      frameNumber: 10,
      firstThrow: first,
      secondThrow: second,
      thirdThrow: third,
      cumulativeScore: existing?.cumulativeScore,
      confidence: confidence,
    );
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

class _CellInfo {
  final ui.Rect rect;
  final int frameNumber;
  final int throwIndex;

  const _CellInfo({
    required this.rect,
    required this.frameNumber,
    required this.throwIndex,
  });
}
