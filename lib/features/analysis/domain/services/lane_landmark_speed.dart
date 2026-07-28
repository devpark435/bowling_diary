import 'dart:math' as math;

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

/// 파울라인 ~ 헤드핀 중심 거리(USBC 규격, 60ft).
const double kPinDeckM = 18.288;

/// 볼 반지름(지름 8.5in = 0.2159m).
const double kBallRadiusM = 0.1080;

/// 핀 몸통(벨리) 반지름 — 접촉 시점 보정용.
const double kPinBellyRadiusM = 0.0603;

/// 볼 **중심**이 헤드핀에 닿는 순간의 레인 거리.
/// 핀이 움직이기 시작하는 프레임은 이 지점에 대응한다.
const double kHeadPinContactUM = kPinDeckM - kBallRadiusM - kPinBellyRadiusM;

/// 바깥쪽 조준 화살표 2개(board 5·35)의 레인 거리 — 둘 다 파울라인에서 12ft.
/// 이 둘을 잇는 선은 레인 위에서 정확히 등거리(iso-u) 선이다.
const double kOuterArrowUM = 3.6576;

/// 레인 위 거리 [uM]가 알려진 iso-u 선. 화면 픽셀(정규화) 좌표의 두 점으로 준다.
///
/// 좌표계 주의: [a]·[b]·궤적점 모두 [FramePoint](nx, ny 0~1 정규화)다. 아래
/// 교차 계산은 외적 부호만 쓰므로 x·y 축을 각각 독립적으로 스케일해도(=화면
/// 종횡비가 1:1이 아니어도) 결과가 **정확히 불변**이다 — 외적이 sx·sy배로
/// 균일하게 스케일되어 부호와 선형보간 위치가 그대로이기 때문. 따라서 정규화
/// 좌표를 그대로 넣어도 된다.
class LaneLandmarkLine {
  final FramePoint a;
  final FramePoint b;
  final double uM;

  const LaneLandmarkLine({required this.a, required this.b, required this.uM});
}

/// 픽셀 궤적 한 점 — 프레임 번호와 공의 레인 접점(정규화 좌표).
typedef PixelTrackPoint = ({int frame, FramePoint p});

double _signedSide(LaneLandmarkLine line, FramePoint p) {
  final dx = line.b.nx - line.a.nx;
  final dy = line.b.ny - line.a.ny;
  return dx * (p.ny - line.a.ny) - dy * (p.nx - line.a.nx);
}

/// 볼이 [line]을 지나간 프레임을 소수점까지 구한다. 부호 변화 구간을 선형
/// 보간한다. 부호 변화가 없거나(선을 안 지남) 2회 이상이면(궤적 오염) null.
///
/// 추적 구간 **안에서** 일어난 교차만 인정한다 — 외삽은 현 코드의 파울라인
/// 외삽과 같은 실패 모드를 다시 들여오는 것이라 배제한다.
double? landmarkCrossingFrame(
  List<PixelTrackPoint> track,
  LaneLandmarkLine line,
) {
  if (track.length < 2) return null;

  double? crossing;
  for (var i = 0; i < track.length - 1; i++) {
    final s0 = _signedSide(line, track[i].p);
    final s1 = _signedSide(line, track[i + 1].p);
    if (s0 == 0.0) {
      if (crossing != null) return null;
      crossing = track[i].frame.toDouble();
      continue;
    }
    if (s0.sign == s1.sign) continue;
    if (crossing != null) return null; // 교차 2회 이상 = 궤적 오염
    final t = s0 / (s0 - s1);
    crossing = track[i].frame + t * (track[i + 1].frame - track[i].frame);
  }
  return crossing;
}

/// 알려진 거리의 랜드마크 2개를 **볼이 통과한 시각**으로 재서 구속을 낸다.
///
/// 핵심 아이디어 — 픽셀에서 깊이를 재지 말고 시간을 재라:
/// 볼이 등속이면 카메라 투영에서 화면 위치는 `x = x_v + K/(i − a)` 꼴이고,
/// 이는 레인 거리 u가 프레임 번호 i에 **선형**이라는 것과 정확히 동치다.
/// 따라서 필요한 것은 랜드마크의 픽셀 깊이가 아니라 볼이 그 랜드마크를 지난
/// 프레임뿐이다. 소실점 근처에서 1px이 수십 cm가 되는 원근 압축(=기존
/// 호모그래피 방식의 지배적 오차원)이 계산에서 통째로 빠진다.
///
/// 실영상 계측(1920×1080, 29.98fps, 184프레임):
///  - 에로우 iso-u 선 통과 f47.8, 핀 접촉 f126 → 20.0 km/h
///  - 민감도: 에로우 선 ±15px → 19.6~20.3 km/h, 충돌 프레임 ±4 → 19.0~21.0
///  - 대조군(에로우 단독 호모그래피): 에로우 중심 ±1px → 29~98 km/h
///
/// [impactFrame]은 핀이 움직이기 시작하는 프레임(핀 폭발 램프 개시)이어야
/// 한다 — 램프 피크가 아니다. 피크를 넣으면 비행시간이 과대평가돼 느리게 나온다.
double? estimateLandmarkSpeedKmh({
  required List<PixelTrackPoint> track,
  required LaneLandmarkLine line,
  required double impactFrame,
  required int sampleFps,
  double contactUM = kHeadPinContactUM,
}) {
  if (sampleFps <= 0) return null;
  final deltaU = contactUM - line.uM;
  if (deltaU <= 0) return null;

  final crossing = landmarkCrossingFrame(track, line);
  if (crossing == null) return null;

  final flightFrames = impactFrame - crossing;
  if (flightFrames <= 0) return null;

  final seconds = flightFrames / sampleFps;
  return deltaU / seconds * 3.6;
}

/// 검출된 조준 화살표들에서 iso-u 선을 만든다.
///
/// 7개 화살표는 board 5·10·15·20·25·30·35에 각각 12·13·14·15·14·13·12ft로
/// 셰브론(V)을 이룬다. 양 끝(board 5·35)만이 서로 **같은 거리**(12ft)라
/// 그 둘을 잇는 선이 iso-u 선이다.
///
/// 양 끝을 고르는 규칙: **픽셀 거리가 최대인 쌍**. 원근이 진행방향을 강하게
/// 압축하기 때문에 화면상 최장 쌍은 항상 가로로 벌어진 board 5–35 쌍이 된다
/// (실측: 바깥쌍 204px vs 바깥–꼭짓점 101px).
///
/// [minArrows] 미만이거나 V가 아니면(꼭짓점이 선에서 충분히 벗어나지 않으면)
/// null — 레인 이음매·마킹을 화살표로 오인한 경우를 막는다.
///
/// [minApexDeviationRatio]는 교차 계산과 달리 **종횡비에 불변이 아니다**
/// (거리비를 쓰므로). 정규화 좌표에서 실측 V의 편차비는 0.0155였고(같은
/// 데이터가 픽셀 좌표에선 0.073), 일직선 오탐은 0에 수렴하므로 기본값은
/// 양쪽 모두에서 통과하도록 낮게 잡았다.
LaneLandmarkLine? arrowLineFromDetections(
  List<FramePoint> arrows, {
  int minArrows = 5,
  double minApexDeviationRatio = 0.008,
}) {
  if (arrows.length < minArrows) return null;

  var bestI = 0;
  var bestJ = 1;
  var bestD = -1.0;
  for (var i = 0; i < arrows.length; i++) {
    for (var j = i + 1; j < arrows.length; j++) {
      final dx = arrows[j].nx - arrows[i].nx;
      final dy = arrows[j].ny - arrows[i].ny;
      final d = dx * dx + dy * dy;
      if (d > bestD) {
        bestD = d;
        bestI = i;
        bestJ = j;
      }
    }
  }
  if (bestD <= 0) return null;

  final line = LaneLandmarkLine(a: arrows[bestI], b: arrows[bestJ], uM: kOuterArrowUM);

  // V 검증: 나머지 점 중 최대 수직편차가 양끝 간격의 일정 비율 이상이어야 한다.
  final span = math.sqrt(bestD);
  var maxDev = 0.0;
  for (var k = 0; k < arrows.length; k++) {
    if (k == bestI || k == bestJ) continue;
    final dev = (_signedSide(line, arrows[k]) / span).abs();
    if (dev > maxDev) maxDev = dev;
  }
  if (maxDev < span * minApexDeviationRatio) return null;

  return line;
}
