import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

// ── 튜닝 상수 (실영상 1편 계측 기준, 960px 장변으로 정규화한 뒤 적용) ──────
// 실측: 에로우 7개 전부 5×5px, 블롭 면적 18~20, 국소배경 대비 어두움 42.8~66.8.
// 아래 후보 필터는 그보다 넉넉하게 잡고, 최종 선별은 "서로 크기가 비슷한
// 무리"와 셰브론 모양 검증으로 한다 — 카메라 거리가 달라지면 에로우의 절대
// 픽셀 크기가 변하므로 절대값을 박으면 다른 영상에서 깨진다.

/// 작업 해상도(장변). 튜닝 상수들이 이 크기 기준이다.
const int _workLongSide = 960;

/// 국소 배경을 구하는 박스 필터 반지름(작업 해상도 px). 실측 41px 창 = 반지름 20.
const int _bgRadius = 20;

/// 국소 배경보다 이만큼 어두워야 후보 픽셀.
const double _minDarkness = 18;

/// 최종 선별에 요구하는 블롭 평균 어두움.
const double _minBlobDarkness = 30;

/// 후보 블롭의 변 길이 범위(작업 해상도 px).
const int _minBlobSide = 3;
const int _maxBlobSide = 22;

/// 후보 블롭의 최소 픽셀 수.
const int _minBlobArea = 12;

/// 탐색 영역(정규화). 깊이축은 화면 중간~가까운 쪽, 가로축은 레인 폭 대부분.
/// 핀덱(깊이 0 쪽)과 화면 가장자리를 배제한다.
const double _minDepth = 0.35;
const double _maxDepth = 0.95;
const double _minLateral = 0.08;
const double _maxLateral = 0.92;

/// 같은 무리로 볼 크기 비율(중앙값 대비).
const double _sizeClusterLow = 0.6;
const double _sizeClusterHigh = 1.6;

/// 조준 화살표 후보 개수 범위. 규격은 7개지만 일부 마모/가려짐을 허용한다.
const int _minArrows = 5;
const int _maxArrows = 9;

/// 프레임에서 레인 조준 화살표(targeting arrows)들의 중심을 검출한다.
///
/// 화살표는 레인 판재보다 어두운 작은 표식이라, **국소 배경 대비 어두움**으로
/// 찾는다(전역 임계값은 조명 기울기에 무너진다). 후보 블롭 중 서로 크기가
/// 비슷한 무리를 고른 뒤, 셰브론(V) 모양인지 검증한다.
///
/// 반환 좌표는 [FramePoint](정규화). 검출 실패 시 빈 리스트 —
/// 호출부는 구속을 기존 코어로 폴백해야 한다.
///
/// 주의: 이 검출기의 임계값은 실영상 **1편**으로 잡았다. 다른 촬영 조건에서의
/// 일반화는 검증되지 않았으므로, 실패(빈 리스트)를 정상 경로로 취급할 것.
List<FramePoint> detectArrows(img.Image frame) {
  final long = math.max(frame.width, frame.height);
  if (long <= 0) return const [];

  final scale = _workLongSide / long;
  final work = scale < 0.99
      ? img.copyResize(
          frame,
          width: math.max(1, (frame.width * scale).round()),
          height: math.max(1, (frame.height * scale).round()),
        )
      : frame;

  final w = work.width;
  final h = work.height;
  if (w < 3 * _bgRadius || h < 3 * _bgRadius) return const [];

  final lum = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      lum[row + x] = img.getLuminance(work.getPixel(x, y)).toDouble();
    }
  }

  final dark = _localDarkness(lum, w, h);
  final blobs = _findBlobs(dark, w, h);
  if (blobs.length < _minArrows) return const [];

  // 어두운 순으로 추리고, 서로 크기가 비슷한 무리만 남긴다.
  blobs.sort((a, b) => b.meanDark.compareTo(a.meanDark));
  final pool = blobs.take(_maxArrows * 3).toList();
  final sizes = pool.map((b) => b.size).toList()..sort();
  final medianSize = sizes[sizes.length ~/ 2];
  final cluster = pool
      .where((b) =>
          b.size >= medianSize * _sizeClusterLow && b.size <= medianSize * _sizeClusterHigh)
      .toList();

  if (cluster.length < _minArrows || cluster.length > _maxArrows) return const [];

  final points = cluster
      .map((b) => FramePoint(nx: b.cx / w, ny: b.cy / h))
      .toList();

  if (!isChevron(points)) return const [];
  return points;
}

/// 점들이 조준 화살표 배치(셰브론)인지 검증한다.
///
/// 규격상 7개는 board 5~35에 12·13·14·15·14·13·12ft로 놓여, 양 끝을 잇는 선에
/// 대한 수직 편차가 **가운데에서 최대인 단봉 형태**가 된다. 일직선(레인 이음매)
/// 이나 무작위 배치는 이 조건을 통과하지 못한다.
///
/// [minApexRatio]는 양 끝 간격 대비 최대 편차의 하한 — 일직선 배제용.
bool isChevron(List<FramePoint> points, {double minApexRatio = 0.02}) {
  if (points.length < 3) return false;

  var bestI = 0, bestJ = 1;
  var bestD = -1.0;
  for (var i = 0; i < points.length; i++) {
    for (var j = i + 1; j < points.length; j++) {
      final dx = points[j].nx - points[i].nx;
      final dy = points[j].ny - points[i].ny;
      final d = dx * dx + dy * dy;
      if (d > bestD) {
        bestD = d;
        bestI = i;
        bestJ = j;
      }
    }
  }
  if (bestD <= 0) return false;

  final a = points[bestI];
  final b = points[bestJ];
  final ex = b.nx - a.nx;
  final ey = b.ny - a.ny;
  final span = math.sqrt(bestD);

  // 양 끝 선을 따라간 위치(t)와 수직 편차(dev).
  final ordered = <({double t, double dev})>[];
  for (final p in points) {
    final vx = p.nx - a.nx;
    final vy = p.ny - a.ny;
    ordered.add((
      t: (vx * ex + vy * ey) / bestD,
      dev: (ex * vy - ey * vx) / span,
    ));
  }
  ordered.sort((x, y) => x.t.compareTo(y.t));

  // 편차가 모두 같은 쪽이어야 한다(V가 한쪽으로만 꺾인다).
  final mid = ordered.sublist(1, ordered.length - 1);
  if (mid.isEmpty) return false;
  final sign = mid.map((e) => e.dev).reduce((p, q) => p.abs() > q.abs() ? p : q).sign;
  if (sign == 0) return false;
  final devs = ordered.map((e) => e.dev * sign).toList();

  final peak = devs.reduce(math.max);
  if (peak < span * minApexRatio) return false; // 일직선

  // 단봉성: 최대 지점까지 (거의) 증가, 이후 (거의) 감소.
  final peakIdx = devs.indexOf(peak);
  final tolerance = peak * 0.35;
  for (var k = 1; k <= peakIdx; k++) {
    if (devs[k] < devs[k - 1] - tolerance) return false;
  }
  for (var k = peakIdx + 1; k < devs.length; k++) {
    if (devs[k] > devs[k - 1] + tolerance) return false;
  }
  return true;
}

/// 국소 배경(박스 평균) 대비 어두움. 값이 클수록 주변보다 어둡다.
Float32List _localDarkness(Float32List lum, int w, int h) {
  // 적분영상으로 박스 평균을 O(1)에 구한다.
  final integral = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0.0;
    for (var x = 0; x < w; x++) {
      rowSum += lum[y * w + x];
      integral[(y + 1) * (w + 1) + (x + 1)] = integral[y * (w + 1) + (x + 1)] + rowSum;
    }
  }

  double boxMean(int x, int y) {
    final x0 = math.max(0, x - _bgRadius);
    final y0 = math.max(0, y - _bgRadius);
    final x1 = math.min(w, x + _bgRadius + 1);
    final y1 = math.min(h, y + _bgRadius + 1);
    final sum = integral[y1 * (w + 1) + x1] -
        integral[y0 * (w + 1) + x1] -
        integral[y1 * (w + 1) + x0] +
        integral[y0 * (w + 1) + x0];
    return sum / ((x1 - x0) * (y1 - y0));
  }

  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out[y * w + x] = boxMean(x, y) - lum[y * w + x];
    }
  }
  return out;
}

class _Blob {
  final double cx;
  final double cy;
  final int side;
  final double meanDark;
  const _Blob(this.cx, this.cy, this.side, this.meanDark);

  double get size => side.toDouble();
}

/// 어두움 임계 이상 픽셀들을 4-이웃 연결요소로 묶어 후보 블롭을 만든다.
List<_Blob> _findBlobs(Float32List dark, int w, int h) {
  final visited = Uint8List(w * h);
  final stack = <int>[];
  final blobs = <_Blob>[];

  for (var seed = 0; seed < dark.length; seed++) {
    if (visited[seed] != 0 || dark[seed] <= _minDarkness) continue;

    visited[seed] = 1;
    stack.add(seed);
    var minX = w, maxX = -1, minY = h, maxY = -1;
    var count = 0;
    var sumX = 0.0, sumY = 0.0, sumDark = 0.0;

    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      final x = idx % w;
      final y = idx ~/ w;
      count++;
      sumX += x;
      sumY += y;
      sumDark += dark[idx];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      if (x > 0) _push(stack, visited, dark, idx - 1);
      if (x < w - 1) _push(stack, visited, dark, idx + 1);
      if (y > 0) _push(stack, visited, dark, idx - w);
      if (y < h - 1) _push(stack, visited, dark, idx + w);
    }

    if (count < _minBlobArea) continue;
    final bw = maxX - minX + 1;
    final bh = maxY - minY + 1;
    if (bw < _minBlobSide || bw > _maxBlobSide) continue;
    if (bh < _minBlobSide || bh > _maxBlobSide) continue;

    final meanDark = sumDark / count;
    if (meanDark < _minBlobDarkness) continue;

    final cx = sumX / count;
    final cy = sumY / count;
    final nx = cx / w;
    final ny = cy / h;
    // 깊이축은 장변 쪽이다(레인 진행방향).
    final depth = w >= h ? nx : ny;
    final lateral = w >= h ? ny : nx;
    if (depth < _minDepth || depth > _maxDepth) continue;
    if (lateral < _minLateral || lateral > _maxLateral) continue;

    blobs.add(_Blob(cx, cy, math.max(bw, bh), meanDark));
  }
  return blobs;
}

void _push(List<int> stack, Uint8List visited, Float32List dark, int idx) {
  if (visited[idx] != 0 || dark[idx] <= _minDarkness) return;
  visited[idx] = 1;
  stack.add(idx);
}
