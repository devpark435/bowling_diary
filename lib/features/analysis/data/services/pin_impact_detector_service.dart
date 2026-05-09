import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/impact_result.dart';

/// 영상 grid 변화율 기반 핀 임팩트 탐지.
///
/// ROI 위치 추정 없이 영상 전체를 8×8 grid로 나눠 각 cell의
/// frame-to-frame 변화율 시계열을 분석한다.
/// release 후 minTravelFrames를 기다렸다가, _minSpikingCells개 이상의
/// cell이 동시에 baseline + 3σ 이상으로 spike하면 임팩트로 판정.
class PinImpactDetectorService {
  static const int _gridCols = 8;
  static const int _gridRows = 8;
  static const int _dsSize = 160; // 다운샘플 크기
  static const double _pixelDiffThreshold = 20.0;
  // 50 km/h 기준 이동 시간 ~1.3s = 39프레임 → 절반(20)을 release 직후 무시
  static const int _minTravelFrames = 20;
  // baseline 계산에 사용할 release 직후 프레임 수
  static const int _baselineFrames = 20;
  // 동시에 spike해야 하는 최소 cell 수 (임팩트 vs 단순 움직임 구분)
  static const int _minSpikingCells = 3;
  // cell threshold의 최소값 (정적 배경의 경우 baseline이 너무 낮을 수 있음)
  static const double _minCellThreshold = 0.04;
  static const double _spikeMultiplier = 3.0;

  ImpactResult findImpact(
    List<img.Image> frames,
    List<BallDetection?> detections,
    int releaseFrame,
  ) {
    if (frames.length < 2) return ImpactResult.notFound;
    if (releaseFrame >= frames.length) return ImpactResult.notFound;

    final searchStart = releaseFrame + _minTravelFrames;
    if (searchStart >= frames.length) return ImpactResult.notFound;

    final fw = frames.first.width.toDouble();
    final fh = frames.first.height.toDouble();

    // 1. release부터 다운샘플 그레이스케일 프레임 준비
    final dsFrames = <img.Image>[];
    final frameIndices = <int>[];
    for (int i = releaseFrame; i < frames.length; i++) {
      final ds = img.copyResize(frames[i], width: _dsSize, height: _dsSize);
      dsFrames.add(img.grayscale(ds));
      frameIndices.add(i);
    }

    if (dsFrames.length < _baselineFrames + 2) return ImpactResult.notFound;

    final cellW = _dsSize ~/ _gridCols;
    final cellH = _dsSize ~/ _gridRows;
    final totalCells = _gridCols * _gridRows;

    // 2. 각 연속 프레임 쌍에서 cell별 변화율 계산
    // gridRatios[frameIdx][cellIdx]
    final gridRatios = <List<double>>[];
    for (int fi = 1; fi < dsFrames.length; fi++) {
      final prev = dsFrames[fi - 1];
      final curr = dsFrames[fi];
      final cellRatios = List<double>.filled(totalCells, 0.0);
      for (int row = 0; row < _gridRows; row++) {
        for (int col = 0; col < _gridCols; col++) {
          final cellIdx = row * _gridCols + col;
          final x0 = col * cellW;
          final y0 = row * cellH;
          int changed = 0;
          int total = 0;
          for (int py = y0; py < y0 + cellH && py < _dsSize; py++) {
            for (int px = x0; px < x0 + cellW && px < _dsSize; px++) {
              final diff = (img.getLuminance(curr.getPixel(px, py)) -
                      img.getLuminance(prev.getPixel(px, py)))
                  .abs();
              if (diff > _pixelDiffThreshold) changed++;
              total++;
            }
          }
          cellRatios[cellIdx] = total > 0 ? changed / total : 0.0;
        }
      }
      gridRatios.add(cellRatios);
    }

    // 3. 첫 _baselineFrames 쌍으로 cell별 baseline (mean + 3σ) 계산
    final baselineLen = math.min(_baselineFrames, gridRatios.length ~/ 2);
    final means = List<double>.filled(totalCells, 0.0);
    final stds = List<double>.filled(totalCells, 0.0);
    for (int c = 0; c < totalCells; c++) {
      final vals = gridRatios.take(baselineLen).map((r) => r[c]).toList();
      final mean = vals.reduce((a, b) => a + b) / vals.length;
      final variance = vals.map((v) => (v - mean) * (v - mean)).reduce(
              (a, b) => a + b) /
          vals.length;
      means[c] = mean;
      stds[c] = math.sqrt(variance);
    }

    // 4. release + minTravelFrames 이후 spike 탐지
    // gridRatios[i]는 frame[releaseFrame + i + 1] 의 변화율 (i=0 → release+1 vs release)
    final relativeSearchStart = searchStart - releaseFrame - 1;

    for (int ri = math.max(0, relativeSearchStart);
        ri < gridRatios.length;
        ri++) {
      final absoluteFrame = frameIndices[ri + 1]; // ri+1 because ratio is between fi-1 and fi
      final cellRatios = gridRatios[ri];
      final spikingCells = <int>[];

      for (int c = 0; c < totalCells; c++) {
        final threshold =
            math.max(_minCellThreshold, means[c] + _spikeMultiplier * stds[c]);
        if (cellRatios[c] >= threshold) spikingCells.add(c);
      }

      // 볼이 감지된 cell 제외 (볼 확대 움직임으로 인한 false positive 방지)
      if (absoluteFrame < detections.length) {
        final ballDet = detections[absoluteFrame];
        if (ballDet != null) {
          final ballCellSet = _ballCellIndices(ballDet);
          spikingCells.removeWhere(ballCellSet.contains);
        }
      }

      if (spikingCells.length >= _minSpikingCells) {
        // spike cell들의 union ROI 계산 (원본 좌표로 변환)
        double minX = double.infinity,
            minY = double.infinity,
            maxX = 0,
            maxY = 0;
        for (final c in spikingCells) {
          final col = c % _gridCols;
          final row = c ~/ _gridCols;
          final x = col * cellW / _dsSize * fw;
          final y = row * cellH / _dsSize * fh;
          final w = cellW / _dsSize * fw;
          final h = cellH / _dsSize * fh;
          minX = math.min(minX, x);
          minY = math.min(minY, y);
          maxX = math.max(maxX, x + w);
          maxY = math.max(maxY, y + h);
        }
        final roi = Rect.fromLTRB(minX, minY, maxX, maxY);
        final maxRatio = spikingCells.map((c) => cellRatios[c]).reduce(
            (a, b) => a > b ? a : b);

        // confidence: cell 수 기여(50%) + maxRatio 기여(50%)
        // cells=_minSpikingCells → 0.5, cells=10+ → ~1.0
        final cellScore =
            (spikingCells.length / _minSpikingCells * 0.5).clamp(0.0, 0.5);
        final ratioScore = (maxRatio * 0.5).clamp(0.0, 0.5);
        final confidence = (cellScore + ratioScore).clamp(0.0, 1.0);

        debugPrint('[PinImpact] impact=$absoluteFrame, '
            'cells=${spikingCells.length}, maxRatio=${(maxRatio * 100).toStringAsFixed(1)}%, '
            'conf=${confidence.toStringAsFixed(2)}, roi=$roi');
        return ImpactResult(
          frame: absoluteFrame,
          roi: roi,
          confidence: confidence,
        );
      }
    }

    debugPrint('[PinImpact] impact 미감지 (grid ${_gridCols}x$_gridRows, '
        'minCells=$_minSpikingCells)');
    return ImpactResult.notFound;
  }

  /// 볼 detection bbox가 점유하는 grid cell 인덱스 집합 반환 (정규화 좌표 기준).
  Set<int> _ballCellIndices(BallDetection det) {
    final cellFw = 1.0 / _gridCols;
    final cellFh = 1.0 / _gridRows;
    // bbox 패딩 1.2배
    const pad = 1.2;
    final bx = det.cx - det.bw * pad / 2;
    final by = det.cy - det.bh * pad / 2;
    final bx2 = det.cx + det.bw * pad / 2;
    final by2 = det.cy + det.bh * pad / 2;

    final result = <int>{};
    for (int row = 0; row < _gridRows; row++) {
      for (int col = 0; col < _gridCols; col++) {
        final cx0 = col * cellFw;
        final cy0 = row * cellFh;
        final cx1 = cx0 + cellFw;
        final cy1 = cy0 + cellFh;
        // bbox와 cell이 겹치면 포함
        if (bx < cx1 && bx2 > cx0 && by < cy1 && by2 > cy0) {
          result.add(row * _gridCols + col);
        }
      }
    }
    return result;
  }
}
