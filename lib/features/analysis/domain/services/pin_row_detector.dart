import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

// 밝은 픽셀 판정 임계값(luminance).
const double _luminanceThreshold = 200;
// 프레임 상단 몇 %까지 스캔할지 — 핀은 항상 화면 위쪽(기계 아래·레인 위)에 있다.
const double _topScanRatio = 0.7;
// 연속 밝은 픽셀 구간(run)으로 인정할 최소 폭(px). 1px 노이즈를 배제한다.
const int _minRunWidthPx = 2;
// 핀 행으로 볼 최소 run 개수(핀 몸통들이 만드는 분리된 구간).
const int _minRunCount = 3;
// 핀 행 후보 행의 밝은 픽셀 비율 범위(행 폭 대비). 조명 패널/기계 바(좁은
// 단일 run)나 레인 반사(어두운 나무색, 200 임계 미달)를 배제한다.
const double _minBrightRatio = 0.04;
const double _maxBrightRatio = 0.6;
// 선택된 밴드의 높이가 프레임 높이 대비 이 범위 밖이면 오탐으로 보고 실패.
const double _minBandHeightRatio = 0.015;
const double _maxBandHeightRatio = 0.20;
// 밴드 세로 범위를 밴드 높이의 이 비율만큼 위아래로 확장(핀 상단/베이스 여유).
const double _bandVerticalExpandRatio = 0.30;
// 밴드 가로 범위(run 최소 시작~최대 끝)에 프레임 폭의 이 비율만큼 마진 추가.
const double _horizontalMarginRatio = 0.02;

/// 한 행에서 조건을 만족한 경우의 run 경계(가로 범위 산출용).
class _QualifyingRow {
  final int minRunStart;
  final int maxRunEnd;
  const _QualifyingRow({required this.minRunStart, required this.maxRunEnd});
}

/// 프레임에서 스탠딩 핀 행(흰 핀들이 검은 피트 배경 앞에 늘어선 띠)을 직접
/// 탐지해 정규화 존 Rect를 반환한다. 호모그래피(수동 캘리브레이션)에 의존하지
/// 않으므로 캘리브레이션이 부정확해도 핀 폭발 감지가 정확한 위치를 본다.
///
/// 휴리스틱:
/// 1) 상단 70% 행마다 밝은 픽셀(luminance > 200) 수집.
/// 2) 각 행에서 밝은 픽셀의 연속 구간(run, 최소 폭 2px) 개수를 셈 — 핀 행은
///    핀 몸통들이 만드는 3개 이상의 분리된 run이 특징(조명 패널/기계 바는
///    1~2개의 넓은 run, 레인 반사는 배경이 나무색이라 200 임계 미달).
/// 3) "run >= 3 && 밝은 비율이 행 폭의 4~60%" 조건을 만족하는 행들의 연속
///    밴드 중 **가장 아래**(핀은 기계 아래·레인 위에 있음) 밴드를 선택.
/// 4) 밴드 높이가 프레임의 1.5~20% 범위 밖이면 실패(null) — 호출부는
///    호모그래피 존 → legacy 존 순으로 폴백.
/// 5) 존: 밴드 세로 범위 ±(밴드높이의 30%) 확장, 가로는 조건 만족 행들의
///    run 최소 시작~최대 끝 ±2% 마진, 전부 0~1 클램프.
Rect? detectPinRowZone(img.Image frame) {
  final width = frame.width;
  final height = frame.height;
  if (width <= 0 || height <= 0) return null;

  final scanHeight = (height * _topScanRatio).floor().clamp(0, height);
  if (scanHeight <= 0) return null;

  final rows = List<_QualifyingRow?>.filled(scanHeight, null);

  for (var y = 0; y < scanHeight; y++) {
    var brightCount = 0;
    final runStarts = <int>[];
    final runEnds = <int>[];
    int? runStart;

    void closeRun(int endExclusive) {
      if (runStart == null) return;
      final runEnd = endExclusive - 1;
      if (runEnd - runStart! + 1 >= _minRunWidthPx) {
        runStarts.add(runStart!);
        runEnds.add(runEnd);
      }
      runStart = null;
    }

    for (var x = 0; x < width; x++) {
      final isBright = img.getLuminance(frame.getPixel(x, y)) > _luminanceThreshold;
      if (isBright) {
        brightCount++;
        runStart ??= x;
      } else {
        closeRun(x);
      }
    }
    closeRun(width);

    final brightRatio = brightCount / width;
    final qualifies = runStarts.length >= _minRunCount &&
        brightRatio >= _minBrightRatio &&
        brightRatio <= _maxBrightRatio;

    if (qualifies) {
      rows[y] = _QualifyingRow(
        minRunStart: runStarts.reduce(math.min),
        maxRunEnd: runEnds.reduce(math.max),
      );
    }
  }

  // 조건을 만족하는 행들의 연속 밴드 중 가장 아래(마지막) 밴드를 선택한다.
  // 위에서 아래로 순회하며 매번 덮어쓰므로 최종적으로 마지막 밴드가 남는다.
  int? bandTop;
  int? bandBottom;
  int? currentStart;
  for (var y = 0; y < scanHeight; y++) {
    if (rows[y] != null) {
      currentStart ??= y;
    } else if (currentStart != null) {
      bandTop = currentStart;
      bandBottom = y - 1;
      currentStart = null;
    }
  }
  if (currentStart != null) {
    bandTop = currentStart;
    bandBottom = scanHeight - 1;
  }

  if (bandTop == null || bandBottom == null) return null;

  final bandTopPx = bandTop.toDouble();
  final bandBottomPx = bandBottom + 1.0; // 행 인덱스는 inclusive → 픽셀 경계는 +1
  final bandHeightPx = bandBottomPx - bandTopPx;
  final bandHeightRatio = bandHeightPx / height;
  if (bandHeightRatio < _minBandHeightRatio || bandHeightRatio > _maxBandHeightRatio) {
    return null;
  }

  var minX = width;
  var maxX = 0;
  for (var y = bandTop; y <= bandBottom; y++) {
    final row = rows[y];
    if (row == null) continue;
    minX = math.min(minX, row.minRunStart);
    maxX = math.max(maxX, row.maxRunEnd);
  }

  final verticalExpandPx = bandHeightPx * _bandVerticalExpandRatio;
  final topPx = (bandTopPx - verticalExpandPx).clamp(0.0, height.toDouble());
  final bottomPx = (bandBottomPx + verticalExpandPx).clamp(0.0, height.toDouble());

  final horizontalMarginPx = width * _horizontalMarginRatio;
  final leftPx = (minX - horizontalMarginPx).clamp(0.0, width.toDouble());
  final rightPx = (maxX + 1 + horizontalMarginPx).clamp(0.0, width.toDouble());

  if (rightPx - leftPx <= 0 || bottomPx - topPx <= 0) return null;

  return Rect.fromLTRB(
    leftPx / width,
    topPx / height,
    rightPx / width,
    bottomPx / height,
  );
}
