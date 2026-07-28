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
// run 사이 "틈" 픽셀들의 25퍼센타일 휘도가 이 값 미만이어야 핀 행으로 본다.
// 핀 사이로는 피트(검정, 실측 p25≈25~60)가 보이지만, 레인 반사/마킹의 틈은
// 밝은 나무색(실측 p25≈104~177)이다 — 실영상 계측으로 확정한 결정적 판별자.
// (이 필터가 없으면 반사 밴드가 "최하단" 규칙에 걸려 오탐된다.)
const double _maxGapP25Luminance = 60;
// 조건 만족 행 사이에 이 행수 이하의 구멍은 같은 밴드로 병합(핀 넥 등).
const int _bandMergeGapRows = 2;
// 밴드로 인정할 최소 행 수(노이즈성 1~2행 밴드 배제, 실측 핀 밴드 ≈ 36행/853).
const int _minBandRows = 6;
// 선택된 밴드의 높이가 프레임 높이 대비 이 값을 넘으면 오탐으로 보고 실패.
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
/// 휴리스틱 (실영상 2편 계측으로 규칙 확정 — 아래 실측치 참조):
/// 1) 상단 70% 행마다 밝은 픽셀(luminance > 200) 수집.
/// 2) 각 행에서 밝은 픽셀의 연속 구간(run, 최소 폭 2px)을 구한다.
/// 3) 행 자격: run >= 3 && 밝은 비율 4~60% && **run 사이 틈 픽셀의 p25 휘도
///    < 60**. 마지막 조건이 결정적 판별자 — 핀 사이로는 피트(검정)가
///    보이지만(실측 p25 25~60), 레인 반사·마킹·기계의 틈은 밝다(실측
///    104~177). 이 필터 없이 "최하단 밴드" 규칙만 쓰면 레인 반사 밴드
///    (프레임 ~69% 지점)가 걸린다(실영상 재현).
/// 4) 자격 행들을 밴드로 병합(2행 이하 구멍 허용), 6행 미만 밴드 배제 후
///    **가장 아래** 밴드 선택(위쪽 기계의 어두운 슬롯이 유사 패턴을 만든다
///    — 실측: 기계 유사 밴드 0.30~0.31 vs 핀 밴드 0.33~0.38).
/// 5) 밴드 높이가 프레임의 20% 초과면 실패(null) — 호출부는 호모그래피 존
///    → legacy 존 순으로 폴백.
/// 6) 존: 밴드 세로 범위 ±(밴드높이의 30%) 확장, 가로는 자격 행들의 run
///    최소 시작~최대 끝 ±2% 마진, 전부 0~1 클램프. 주의: 옆 레인 핀도
///    가로 범위에 들어올 수 있다(실측 nx 0~0.96).
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
    final gapLums = <num>[];
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
    var qualifies = runStarts.length >= _minRunCount &&
        brightRatio >= _minBrightRatio &&
        brightRatio <= _maxBrightRatio;

    if (qualifies) {
      // run 사이 틈 픽셀들의 휘도 — 피트(검정) 판별자 (클래스 doc 3) 참조).
      for (var r = 0; r + 1 < runStarts.length; r++) {
        for (var x = runEnds[r] + 1; x < runStarts[r + 1]; x++) {
          gapLums.add(img.getLuminance(frame.getPixel(x, y)));
        }
      }
      if (gapLums.isEmpty) {
        qualifies = false;
      } else {
        gapLums.sort();
        final p25 = gapLums[gapLums.length ~/ 4];
        qualifies = p25 < _maxGapP25Luminance;
      }
    }

    if (qualifies) {
      rows[y] = _QualifyingRow(
        minRunStart: runStarts.reduce(math.min),
        maxRunEnd: runEnds.reduce(math.max),
      );
    }
  }

  // 자격 행들을 밴드로 병합([_bandMergeGapRows] 이하 구멍 허용) 후, 최소 행수
  // 조건을 만족하는 밴드 중 가장 아래(마지막) 밴드를 선택한다.
  int? bandTop;
  int? bandBottom;
  int? currentStart;
  int? currentEnd;
  void closeBand() {
    if (currentStart == null || currentEnd == null) return;
    final rowCount = currentEnd! - currentStart! + 1;
    if (rowCount >= _minBandRows) {
      bandTop = currentStart;
      bandBottom = currentEnd;
    }
    currentStart = null;
    currentEnd = null;
  }

  for (var y = 0; y < scanHeight; y++) {
    if (rows[y] == null) continue;
    if (currentEnd != null && y - currentEnd! > _bandMergeGapRows) {
      closeBand();
    }
    currentStart ??= y;
    currentEnd = y;
  }
  closeBand();

  if (bandTop == null || bandBottom == null) return null;

  final bandTopPx = bandTop!.toDouble();
  final bandBottomPx = bandBottom! + 1.0; // 행 인덱스는 inclusive → 픽셀 경계는 +1
  final bandHeightPx = bandBottomPx - bandTopPx;
  final bandHeightRatio = bandHeightPx / height;
  if (bandHeightRatio > _maxBandHeightRatio) {
    return null;
  }

  var minX = width;
  var maxX = 0;
  for (var y = bandTop!; y <= bandBottom!; y++) {
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
