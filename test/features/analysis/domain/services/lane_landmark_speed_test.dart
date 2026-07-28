import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/lane_landmark_speed.dart';
import 'package:flutter_test/flutter_test.dart';

// ── 실영상 계측 데이터 ──────────────────────────────────────────────
// 1920×1080 / 29.98fps / 184프레임 영상을 반해상도(960×540)로 계측한 값.
// 좌표는 반해상도 픽셀. 레인 진행방향 = x축(핀이 작은 x), 가로 = y축.

const _frameW = 960.0;
const _frameH = 540.0;

FramePoint _px(double x, double y) => FramePoint(nx: x / _frameW, ny: y / _frameH);

/// 검출된 7개 조준 화살표 중심(반해상도 px). board 5~35이 셰브론을 이룬다.
final _arrows = <FramePoint>[
  _px(626.3, 141.5),
  _px(620.4, 175.4),
  _px(615.2, 208.5),
  _px(610.4, 240.8), // 꼭짓점(board 20, 15ft)
  _px(614.3, 274.6),
  _px(619.4, 309.6),
  _px(624.2, 345.5),
];

/// 배경차분 추적으로 얻은 볼 접점(반해상도 px).
final _ballTrack = <PixelTrackPoint>[
  (frame: 43, p: _px(687.5, 275.1)),
  (frame: 53, p: _px(569.3, 222.3)),
  (frame: 63, p: _px(503.2, 200.9)),
  (frame: 73, p: _px(453.8, 188.8)),
  (frame: 83, p: _px(418.8, 182.9)),
  (frame: 93, p: _px(392.2, 183.5)),
];

/// 핀이 움직이기 시작한 프레임(핀 ROI 프레임차 램프 개시).
const _impactFrame = 126.0;
const _fps = 30;

void main() {
  group('arrowLineFromDetections', () {
    test('실측 7개 화살표에서 바깥쌍(board 5·35)을 iso-u 선으로 고른다', () {
      final line = arrowLineFromDetections(_arrows);
      expect(line, isNotNull);
      // 바깥쌍 = 리스트의 첫·마지막(가로로 가장 벌어진 쌍).
      final ends = {line!.a, line.b};
      expect(ends, {_arrows.first, _arrows.last});
      expect(line.uM, kOuterArrowUM);
    });

    test('점이 부족하면 null', () {
      expect(arrowLineFromDetections(_arrows.take(4).toList()), isNull);
    });

    test('일직선이면(V가 아니면) null — 레인 이음매 오탐 배제', () {
      final collinear = List.generate(7, (i) => _px(620.0, 141.5 + i * 34.0));
      expect(arrowLineFromDetections(collinear), isNull);
    });
  });

  group('landmarkCrossingFrame', () {
    test('실측 궤적이 에로우 iso-u 선을 지나는 프레임을 소수점으로 구한다', () {
      final line = arrowLineFromDetections(_arrows)!;
      final f = landmarkCrossingFrame(_ballTrack, line);
      expect(f, isNotNull);
      // 투영모델 적합(x = 189.4 + 16962/(i−8.9), rms 0.38px)이 준 47.8과
      // 원시 선형보간이 준 값이 1프레임 이내로 일치해야 한다.
      expect(f!, closeTo(48.3, 0.5));
    });

    test('종횡비에 불변 — 정규화 좌표든 픽셀 좌표든 같은 답', () {
      final linePx = LaneLandmarkLine(
        a: FramePoint(nx: 626.3, ny: 141.5),
        b: FramePoint(nx: 624.2, ny: 345.5),
        uM: kOuterArrowUM,
      );
      final trackPx = <PixelTrackPoint>[
        (frame: 43, p: FramePoint(nx: 687.5, ny: 275.1)),
        (frame: 53, p: FramePoint(nx: 569.3, ny: 222.3)),
        (frame: 63, p: FramePoint(nx: 503.2, ny: 200.9)),
        (frame: 73, p: FramePoint(nx: 453.8, ny: 188.8)),
        (frame: 83, p: FramePoint(nx: 418.8, ny: 182.9)),
        (frame: 93, p: FramePoint(nx: 392.2, ny: 183.5)),
      ];
      final normalized = landmarkCrossingFrame(_ballTrack, arrowLineFromDetections(_arrows)!);
      final pixels = landmarkCrossingFrame(trackPx, linePx);
      expect(pixels, closeTo(normalized!, 1e-9));
    });

    test('선을 지나지 않으면 null', () {
      final line = arrowLineFromDetections(_arrows)!;
      final beforeOnly = _ballTrack.take(1).toList()
        ..add((frame: 45, p: _px(660.0, 265.0)));
      expect(landmarkCrossingFrame(beforeOnly, line), isNull);
    });

    test('부호 변화가 두 번이면 null — 궤적 오염', () {
      final line = arrowLineFromDetections(_arrows)!;
      final zigzag = <PixelTrackPoint>[
        (frame: 43, p: _px(687.5, 275.1)),
        (frame: 53, p: _px(569.3, 222.3)),
        (frame: 63, p: _px(700.0, 260.0)), // 되돌아옴
      ];
      expect(landmarkCrossingFrame(zigzag, line), isNull);
    });
  });

  group('estimateLandmarkSpeedKmh', () {
    LaneLandmarkLine line() => arrowLineFromDetections(_arrows)!;

    test('실영상 구속을 산출한다', () {
      final kmh = estimateLandmarkSpeedKmh(
        track: _ballTrack,
        line: line(),
        impactFrame: _impactFrame,
        sampleFps: _fps,
      );
      expect(kmh, isNotNull);
      expect(kmh!, closeTo(20.1, 0.6));
    });

    test('조건수가 좋다 — 에로우 선을 ±15px 흔들어도 1km/h 미만 변화', () {
      final base = estimateLandmarkSpeedKmh(
        track: _ballTrack,
        line: line(),
        impactFrame: _impactFrame,
        sampleFps: _fps,
      )!;
      for (final dx in <double>[-15, 15]) {
        final shifted = LaneLandmarkLine(
          a: _px(626.3 + dx, 141.5),
          b: _px(624.2 + dx, 345.5),
          uM: kOuterArrowUM,
        );
        final kmh = estimateLandmarkSpeedKmh(
          track: _ballTrack,
          line: shifted,
          impactFrame: _impactFrame,
          sampleFps: _fps,
        );
        expect((kmh! - base).abs(), lessThan(1.0), reason: 'dx=$dx');
      }
    });

    test('충돌 프레임 ±4에도 ±1.1km/h 이내', () {
      final base = estimateLandmarkSpeedKmh(
        track: _ballTrack,
        line: line(),
        impactFrame: _impactFrame,
        sampleFps: _fps,
      )!;
      for (final df in <double>[-4, 4]) {
        final kmh = estimateLandmarkSpeedKmh(
          track: _ballTrack,
          line: line(),
          impactFrame: _impactFrame + df,
          sampleFps: _fps,
        );
        expect((kmh! - base).abs(), lessThan(1.1), reason: 'df=$df');
      }
    });

    test('충돌이 통과보다 앞서면 null', () {
      expect(
        estimateLandmarkSpeedKmh(
          track: _ballTrack,
          line: line(),
          impactFrame: 40,
          sampleFps: _fps,
        ),
        isNull,
      );
    });

    test('fps가 0 이하면 null', () {
      expect(
        estimateLandmarkSpeedKmh(
          track: _ballTrack,
          line: line(),
          impactFrame: _impactFrame,
          sampleFps: 0,
        ),
        isNull,
      );
    });
  });

  test('레인 상수 — 헤드핀 접촉 지점은 핀덱보다 볼+핀 반지름만큼 앞', () {
    expect(kHeadPinContactUM, closeTo(18.1197, 1e-4));
    expect(kOuterArrowUM, closeTo(3.6576, 1e-4));
  });
}
