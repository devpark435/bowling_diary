import 'dart:math' as math;

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

/// 픽셀 공간 볼 관측 한 점 — 프레임, 레인 접점(정규화), 정규화 bbox 폭.
typedef BallPixelSample = ({int frame, FramePoint contact, double widthN});

/// 볼 궤적의 **픽셀 공간** 투영 모델. 캘리브레이션(호모그래피)을 전혀 쓰지 않는다.
///
/// 등속으로 굴러가는 공을 고정 카메라로 찍으면 화면 깊이축 좌표는
/// `ny = nyv + 1/(α + β·i)` 꼴이다 — 레인 거리 u가 프레임 번호 i에 선형이고
/// 원근이 `ny − nyv ∝ 1/(u + c)`이기 때문. 따라서 `1/(ny − nyv)`가 i에 대해
/// 선형이고, 미지수는 소실점 [nyv] 하나뿐이라 1차원 탐색으로 적합된다.
///
/// 실영상 계측(1920×1080)에서 50프레임 구간 rms 0.38px. 감속항을 추가해도
/// 개선되지 않았다(등속 가정이 이 구간에서 충분).
///
/// 이 모델이 필요한 이유: 궤적을 핀덱까지 연장하는 기존 방식은 레인 좌표계에서
/// 끝 기울기를 **직선** 연장했다. (a) 실제 곡선이 쌍곡선이라 직선 연장은 끝에서
/// 벌어지고, (b) 목표 y=18.29m가 캘리브레이션 스케일에 물려 있어 스케일이
/// ±30% 흔들리면 연장 길이도 그만큼 틀린다. 픽셀 공간 모델은 둘 다 없앤다.
class ProjectiveTrackModel {
  /// 화면 깊이축(ny)의 소실점.
  final double nyv;

  /// `1/(ny − nyv) = alpha + beta·frame`. 공이 핀 쪽으로 갈수록 ny가 nyv에
  /// 가까워지므로 [beta] > 0.
  final double alpha;
  final double beta;

  /// 가로 이동 모델 `nx = lateralIntercept + lateralSlope·ny`.
  /// 레인 위 직선은 화면에서도 직선이므로, 훅이 끝난 구간(궤적 후반)에
  /// 적합해 연장에 쓴다.
  final double lateralIntercept;
  final double lateralSlope;

  /// 공의 화면상 폭 모델 `widthN = widthScale·(ny − nyv)`.
  /// 겉보기 크기도 `1/(u + c)`에 비례하므로 원점을 지나는 1모수 모델이다.
  /// 관측 폭이 없으면 null.
  final double? widthScale;

  /// ny 잔차의 rms(정규화 단위).
  final double rms;

  const ProjectiveTrackModel({
    required this.nyv,
    required this.alpha,
    required this.beta,
    required this.lateralIntercept,
    required this.lateralSlope,
    required this.widthScale,
    required this.rms,
  });

  /// 모델이 유효한 프레임의 하한(배타적). 이보다 작은 프레임은 소실점 반대편
  /// (카메라 뒤)으로 발산한다.
  double get poleFrame => -alpha / beta;

  /// [frame]에서의 깊이축 좌표. 극점 이하면 null.
  double? depthAt(double frame) {
    final d = alpha + beta * frame;
    if (d <= 0) return null;
    return nyv + 1 / d;
  }

  /// [frame]에서의 볼 접점. 극점 이하면 null.
  FramePoint? pointAt(double frame) {
    final ny = depthAt(frame);
    if (ny == null) return null;
    return FramePoint(nx: lateralIntercept + lateralSlope * ny, ny: ny);
  }

  /// [ny]에서의 볼 화면 폭. 폭 모델이 없으면 null.
  double? widthAt(double ny) {
    final s = widthScale;
    if (s == null) return null;
    return s * (ny - nyv);
  }
}

/// 픽셀 궤적에 [ProjectiveTrackModel]을 적합한다.
///
/// 미지수 [ProjectiveTrackModel.nyv]만 1차원 탐색(기하 격자 + 삼분 탐색)하고,
/// 나머지는 매 후보마다 선형 최소제곱으로 닫힌 형태로 푼다. 잔차는 reciprocal
/// 공간이 아니라 **ny 공간**에서 평가한다(그쪽이 정직한 오차).
///
/// 실패(null) 조건: 점 부족, 깊이 변화 없음, beta ≤ 0(공이 핀 쪽으로 가지 않음),
/// rms가 [maxRms] 초과.
ProjectiveTrackModel? fitProjectiveTrack(
  List<BallPixelSample> track, {
  int minSamples = 4,
  double maxRms = 0.01,
  int gridSteps = 240,
  double minGap = 0.02,
  double maxGap = 20.0,
}) {
  if (track.length < minSamples) return null;

  final frames = track.map((s) => s.frame.toDouble()).toList();
  final ys = track.map((s) => s.contact.ny).toList();

  final yMin = ys.reduce(math.min);
  final yMax = ys.reduce(math.max);
  final span = yMax - yMin;
  if (span <= 0) return null;

  // nyv = yMin − span·g 를 g에 대해 기하 격자로 훑는다.
  double sseAt(double g) {
    final nyv = yMin - span * g;
    final fit = _reciprocalFit(frames, ys, nyv);
    if (fit == null) return double.infinity;
    return fit.sse;
  }

  final ratio = maxGap / minGap;
  var bestG = minGap;
  var bestSse = double.infinity;
  var bestIdx = 0;
  for (var k = 0; k < gridSteps; k++) {
    final g = minGap * math.pow(ratio, k / (gridSteps - 1)).toDouble();
    final sse = sseAt(g);
    if (sse < bestSse) {
      bestSse = sse;
      bestG = g;
      bestIdx = k;
    }
  }
  if (!bestSse.isFinite) return null;

  // 최적 격자 칸 좌우를 삼분 탐색으로 정밀화(log g 공간).
  var lo = minGap * math.pow(ratio, math.max(0, bestIdx - 1) / (gridSteps - 1)).toDouble();
  var hi = minGap *
      math.pow(ratio, math.min(gridSteps - 1, bestIdx + 1) / (gridSteps - 1)).toDouble();
  for (var iter = 0; iter < 60 && hi > lo; iter++) {
    final m1 = lo + (hi - lo) / 3;
    final m2 = hi - (hi - lo) / 3;
    if (sseAt(m1) < sseAt(m2)) {
      hi = m2;
    } else {
      lo = m1;
    }
  }
  final g = (lo + hi) / 2;
  if (sseAt(g) < bestSse) bestG = g;

  final nyv = yMin - span * bestG;
  final fit = _reciprocalFit(frames, ys, nyv);
  if (fit == null) return null;

  final rms = math.sqrt(fit.sse / track.length);
  if (rms > maxRms) return null;

  final lateral = _lateralFit(track);
  final widthScale = _widthFit(track, nyv);

  return ProjectiveTrackModel(
    nyv: nyv,
    alpha: fit.alpha,
    beta: fit.beta,
    lateralIntercept: lateral.intercept,
    lateralSlope: lateral.slope,
    widthScale: widthScale,
    rms: rms,
  );
}

typedef _ReciprocalFit = ({double alpha, double beta, double sse});

/// 주어진 [nyv]에서 `1/(y − nyv) = α + β·i` 선형 적합 후 **ny 공간**에서 SSE 평가.
_ReciprocalFit? _reciprocalFit(List<double> frames, List<double> ys, double nyv) {
  final n = ys.length;
  var st = 0.0, si = 0.0, sti = 0.0, sii = 0.0;
  for (var k = 0; k < n; k++) {
    final d = ys[k] - nyv;
    if (d <= 0) return null;
    final t = 1 / d;
    st += t;
    si += frames[k];
    sti += t * frames[k];
    sii += frames[k] * frames[k];
  }
  final den = n * sii - si * si;
  if (den == 0) return null;
  final beta = (n * sti - si * st) / den;
  if (beta <= 0) return null; // 공이 소실점 쪽(핀 쪽)으로 가야 한다
  final alpha = (st - beta * si) / n;

  var sse = 0.0;
  for (var k = 0; k < n; k++) {
    final d = alpha + beta * frames[k];
    if (d <= 0) return null;
    final r = ys[k] - (nyv + 1 / d);
    sse += r * r;
  }
  return (alpha: alpha, beta: beta, sse: sse);
}

typedef _LateralFit = ({double intercept, double slope});

/// 궤적 후반부(훅이 끝난 직선 구간)에 `nx = p + q·ny` 적합.
/// 레인 위 직선은 화면에서도 직선이므로 연장에 그대로 쓸 수 있다.
_LateralFit _lateralFit(List<BallPixelSample> track) {
  final tailCount = math.max(3, (track.length + 1) ~/ 2);
  final tail = track.sublist(track.length - math.min(tailCount, track.length));

  final n = tail.length;
  var sy = 0.0, sx = 0.0, syy = 0.0, sxy = 0.0;
  for (final s in tail) {
    sy += s.contact.ny;
    sx += s.contact.nx;
    syy += s.contact.ny * s.contact.ny;
    sxy += s.contact.nx * s.contact.ny;
  }
  final den = n * syy - sy * sy;
  if (den == 0) {
    // 깊이 변화가 없으면 기울기를 못 정한다 — 평균 nx로 수직 연장.
    return (intercept: sx / n, slope: 0.0);
  }
  final slope = (n * sxy - sy * sx) / den;
  return (intercept: (sx - slope * sy) / n, slope: slope);
}

/// `widthN = s·(ny − nyv)` 원점 통과 1모수 적합. 유효 관측이 없으면 null.
double? _widthFit(List<BallPixelSample> track, double nyv) {
  var num = 0.0, den = 0.0;
  for (final s in track) {
    if (s.widthN <= 0) continue;
    final d = s.contact.ny - nyv;
    if (d <= 0) continue;
    num += s.widthN * d;
    den += d * d;
  }
  if (den == 0) return null;
  return num / den;
}

/// 관측 궤적을 모델로 [endFrame]까지 연장해 리본 단면들을 만든다.
///
/// 관측된 프레임은 **검출값을 그대로** 쓴다(캘리브레이션과 무관하게 정확히 공
/// 위에 얹힌다). 모델은 관측 밖 구간에만 쓴다. [startFrame]을 주면 앞쪽으로도
/// 연장한다(릴리즈 직후 구간).
///
/// 리본 좌우는 공의 화면 폭 절반만큼 가로로 벌린다 — 관측 구간은 실측 bbox 폭,
/// 연장 구간은 폭 모델값. 폭을 못 구하면 관측 평균 폭으로 대체한다.
List<TrajectoryRibbonPoint> buildProjectiveRibbon({
  required List<BallPixelSample> track,
  required ProjectiveTrackModel model,
  required int endFrame,
  int? startFrame,
}) {
  if (track.isEmpty) return const [];

  final observed = {for (final s in track) s.frame: s};
  final firstObserved = track.first.frame;
  final lastObserved = track.last.frame;

  var fallbackWidth = 0.0;
  var widthCount = 0;
  for (final s in track) {
    if (s.widthN > 0) {
      fallbackWidth += s.widthN;
      widthCount++;
    }
  }
  fallbackWidth = widthCount == 0 ? 0.0 : fallbackWidth / widthCount;

  // 극점 바로 옆은 발산하므로 여유를 둔다.
  final minFrame = model.poleFrame.ceil() + 1;
  final from = math.max(startFrame ?? firstObserved, minFrame);
  final to = math.max(endFrame, lastObserved);

  final out = <TrajectoryRibbonPoint>[];
  for (var f = from; f <= to; f++) {
    final sample = observed[f];
    final FramePoint contact;
    final double widthN;
    if (sample != null) {
      contact = sample.contact;
      widthN = sample.widthN > 0 ? sample.widthN : (model.widthAt(contact.ny) ?? fallbackWidth);
    } else {
      final p = model.pointAt(f.toDouble());
      if (p == null) continue;
      contact = p;
      widthN = model.widthAt(p.ny) ?? fallbackWidth;
    }
    final half = widthN / 2;
    out.add(TrajectoryRibbonPoint(
      frame: f,
      left: FramePoint(nx: (contact.nx - half).clamp(0.0, 1.0), ny: contact.ny.clamp(0.0, 1.0)),
      right: FramePoint(nx: (contact.nx + half).clamp(0.0, 1.0), ny: contact.ny.clamp(0.0, 1.0)),
    ));
  }
  return out;
}
