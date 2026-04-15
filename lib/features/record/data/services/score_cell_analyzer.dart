import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 셀 이미지 분석으로 감지된 타입
enum CellType { strike, spare, number, empty, unknown }

/// 셀 분석 결과
class CellAnalysisResult {
  final int frameNumber;
  final int throwIndex; // 0=1투, 1=2투, 2=3투(10프레임)
  final CellType type;
  final double confidence;

  const CellAnalysisResult({
    required this.frameNumber,
    required this.throwIndex,
    required this.type,
    required this.confidence,
  });

  @override
  String toString() =>
      'Cell(F$frameNumber-T$throwIndex: ${type.name}, ${(confidence * 100).toInt()}%)';
}

/// 볼링 점수판 셀 이미지를 분석하여 스트라이크/스페어 그래픽을 감지
class ScoreCellAnalyzer {
  /// 대각선 패턴 분석 시 밝은 픽셀로 판별하는 임계값 (0~255)
  static const int _brightnessThreshold = 160;

  /// 대각선 위에 밝은 픽셀이 이 비율 이상이면 대각선 있음으로 판별
  static const double _diagonalPresenceThreshold = 0.25;

  /// 전체 셀 대비 밝은 픽셀 비율 (너무 낮으면 빈 셀)
  static const double _emptyThreshold = 0.05;

  /// 이미지 파일에서 지정 영역을 분석
  Future<CellAnalysisResult> analyzeCell({
    required String imagePath,
    required ui.Rect cellRect,
    required int frameNumber,
    required int throwIndex,
  }) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return CellAnalysisResult(
          frameNumber: frameNumber,
          throwIndex: throwIndex,
          type: CellType.unknown,
          confidence: 0,
        );
      }

      // 셀 영역 crop (이미지 경계 보정)
      final x = cellRect.left.toInt().clamp(0, decoded.width - 1);
      final y = cellRect.top.toInt().clamp(0, decoded.height - 1);
      final w = min(cellRect.width.toInt(), decoded.width - x);
      final h = min(cellRect.height.toInt(), decoded.height - y);

      if (w < 5 || h < 5) {
        return CellAnalysisResult(
          frameNumber: frameNumber,
          throwIndex: throwIndex,
          type: CellType.unknown,
          confidence: 0,
        );
      }

      final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
      final grayscale = img.grayscale(cropped);

      return _analyzeCroppedCell(grayscale, frameNumber, throwIndex);
    } catch (e) {
      debugPrint('[CellAnalyzer] 분석 실패 (F$frameNumber-T$throwIndex): $e');
      return CellAnalysisResult(
        frameNumber: frameNumber,
        throwIndex: throwIndex,
        type: CellType.unknown,
        confidence: 0,
      );
    }
  }

  /// 크롭된 그레이스케일 이미지에서 대각선 패턴 분석
  CellAnalysisResult _analyzeCroppedCell(
    img.Image grayscale,
    int frameNumber,
    int throwIndex,
  ) {
    final w = grayscale.width;
    final h = grayscale.height;

    // 전체 밝은 픽셀 비율 → 빈 셀 판별
    int totalBright = 0;
    for (int py = 0; py < h; py++) {
      for (int px = 0; px < w; px++) {
        final pixel = grayscale.getPixel(px, py);
        if (pixel.luminance * 255 > _brightnessThreshold) totalBright++;
      }
    }
    final brightRatio = totalBright / (w * h);

    if (brightRatio < _emptyThreshold) {
      return CellAnalysisResult(
        frameNumber: frameNumber,
        throwIndex: throwIndex,
        type: CellType.empty,
        confidence: 0.8,
      );
    }

    // 좌상→우하 대각선 (\) 밝은 픽셀 비율
    final ltrRatio = _diagonalBrightRatio(grayscale, isLeftToRight: true);
    // 우상→좌하 대각선 (/) 밝은 픽셀 비율
    final rtlRatio = _diagonalBrightRatio(grayscale, isLeftToRight: false);

    debugPrint('[CellAnalyzer] F$frameNumber-T$throwIndex: '
        'bright=${(brightRatio * 100).toInt()}%, '
        'LTR=${(ltrRatio * 100).toInt()}%, '
        'RTL=${(rtlRatio * 100).toInt()}%');

    final hasLtr = ltrRatio > _diagonalPresenceThreshold;
    final hasRtl = rtlRatio > _diagonalPresenceThreshold;

    if (hasLtr && hasRtl) {
      // X자 패턴 → 스트라이크
      final avgDiag = (ltrRatio + rtlRatio) / 2;
      return CellAnalysisResult(
        frameNumber: frameNumber,
        throwIndex: throwIndex,
        type: CellType.strike,
        confidence: min(avgDiag / 0.5, 1.0),
      );
    } else if (hasRtl && !hasLtr) {
      // / 패턴 → 스페어
      return CellAnalysisResult(
        frameNumber: frameNumber,
        throwIndex: throwIndex,
        type: CellType.spare,
        confidence: min(rtlRatio / 0.4, 1.0),
      );
    } else if (hasLtr && !hasRtl) {
      // \ 패턴만 → 스트라이크 변형 또는 숫자
      return CellAnalysisResult(
        frameNumber: frameNumber,
        throwIndex: throwIndex,
        type: CellType.number,
        confidence: 0.5,
      );
    } else {
      // 대각선 패턴 없음 → 숫자
      return CellAnalysisResult(
        frameNumber: frameNumber,
        throwIndex: throwIndex,
        type: brightRatio > 0.15 ? CellType.number : CellType.empty,
        confidence: 0.6,
      );
    }
  }

  /// 대각선 경로 위의 밝은 픽셀 비율 계산
  /// [isLeftToRight] true = 좌상→우하(\), false = 우상→좌하(/)
  double _diagonalBrightRatio(img.Image image, {required bool isLeftToRight}) {
    final w = image.width;
    final h = image.height;
    final diagLength = min(w, h);
    if (diagLength == 0) return 0;

    int brightCount = 0;
    int totalSampled = 0;

    // 대각선 주변 ±2px 폭으로 샘플링
    const bandwidth = 2;

    for (int step = 0; step < diagLength; step++) {
      final progress = step / diagLength;
      final centerX = isLeftToRight
          ? (progress * w).toInt()
          : ((1.0 - progress) * w).toInt();
      final centerY = (progress * h).toInt();

      for (int offset = -bandwidth; offset <= bandwidth; offset++) {
        final px = (centerX + offset).clamp(0, w - 1);
        final py = centerY.clamp(0, h - 1);
        final pixel = image.getPixel(px, py);
        totalSampled++;
        if (pixel.luminance * 255 > _brightnessThreshold) brightCount++;
      }
    }

    return totalSampled > 0 ? brightCount / totalSampled : 0;
  }
}

