import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/projective_track_model.dart';
import 'package:flutter_test/flutter_test.dart';

// ── 실영상 계측 데이터 ──────────────────────────────────────────────
// 1920×1080 / 29.98fps. 반해상도(960×540) 픽셀로 계측한 볼 추적 결과를
// 정규화한 값. 화면 깊이축 = ny(핀 쪽이 작다), 가로 = nx.
// 파이썬 투영적합(50프레임 구간): ny_v = 189.4/960 = 0.1973, rms 0.38px.

const _depthPx = 960.0; // 깊이축 픽셀 크기
const _lateralPx = 540.0;

BallPixelSample _s(int frame, double depth, double lateral, double widthPx) => (
      frame: frame,
      contact: FramePoint(nx: lateral / _lateralPx, ny: depth / _depthPx),
      widthN: widthPx / _depthPx,
    );

/// 배경차분 추적 결과(프레임, 깊이 px, 가로 px, bbox 폭 px).
/// f43·f53은 손과 겹쳐 폭이 부풀어 있다(88·79) — 폭 모델의 강건성 시험용.
final _track = <BallPixelSample>[
  _s(43, 687.5, 275.1, 88),
  _s(53, 569.3, 222.3, 79),
  _s(63, 503.2, 200.9, 51),
  _s(73, 453.8, 188.8, 42),
  _s(83, 418.8, 182.9, 37),
  _s(93, 392.2, 183.5, 32),
];

const _pythonNyv = 189.4 / _depthPx;
const _impactFrame = 126;

void main() {
  group('fitProjectiveTrack', () {
    test('실측 궤적에 적합하고 소실점이 파이썬 투영적합과 일치한다', () {
      final m = fitProjectiveTrack(_track);
      expect(m, isNotNull);
      expect(m!.nyv, closeTo(_pythonNyv, 0.03));
      expect(m.beta, greaterThan(0));
      // 잔차는 화면 높이의 0.2% 미만(= 반해상도 2px 미만).
      expect(m.rms, lessThan(0.002));
    });

    test('직선 외삽보다 정확하다 — 뒤 2점을 빼고 적합해 예측 비교', () {
      final head = _track.take(4).toList(); // f43~f73
      final m = fitProjectiveTrack(head)!;

      // 직선 외삽: 마지막 두 관측점의 기울기를 그대로 연장(현행 방식과 동형).
      final p0 = head[head.length - 2];
      final p1 = head.last;
      final slope =
          (p1.contact.ny - p0.contact.ny) / (p1.frame - p0.frame);
      double linearAt(int f) => p1.contact.ny + slope * (f - p1.frame);

      for (final actual in _track.skip(4)) {
        final modelErr = (m.depthAt(actual.frame.toDouble())! - actual.contact.ny).abs();
        final linearErr = (linearAt(actual.frame) - actual.contact.ny).abs();
        expect(modelErr, lessThan(linearErr),
            reason: 'f${actual.frame}: 모델 $modelErr vs 직선 $linearErr');
      }
    });

    test('직선 외삽은 핀덱 부근에서 소실점을 넘어 발산한다', () {
      final head = _track.take(4).toList();
      final p0 = head[head.length - 2];
      final p1 = head.last;
      final slope = (p1.contact.ny - p0.contact.ny) / (p1.frame - p0.frame);
      final linearAtImpact = p1.contact.ny + slope * (_impactFrame - p1.frame);
      final m = fitProjectiveTrack(head)!;

      // 직선 연장은 소실점보다 더 멀리(작은 ny) 가버린다 — 물리적으로 불가능.
      expect(linearAtImpact, lessThan(m.nyv));
      // 모델은 소실점 앞에 머문다.
      expect(m.depthAt(_impactFrame.toDouble())!, greaterThan(m.nyv));
    });

    test('점이 부족하면 null', () {
      expect(fitProjectiveTrack(_track.take(3).toList()), isNull);
    });

    test('공이 핀에서 멀어지면(beta<=0) null', () {
      final reversed = <BallPixelSample>[
        for (var k = 0; k < _track.length; k++)
          (
            frame: _track[k].frame,
            contact: _track[_track.length - 1 - k].contact,
            widthN: _track[k].widthN,
          ),
      ];
      expect(fitProjectiveTrack(reversed), isNull);
    });

    test('깊이 변화가 없으면 null', () {
      final flat = [
        for (var k = 0; k < 6; k++) _s(43 + k * 10, 500.0, 200.0, 40),
      ];
      expect(fitProjectiveTrack(flat), isNull);
    });

    test('잡음 궤적은 maxRms에서 걸러진다', () {
      final noisy = <BallPixelSample>[
        _s(43, 687.5, 275.1, 88),
        _s(53, 300.0, 222.3, 79),
        _s(63, 640.0, 200.9, 51),
        _s(73, 320.0, 188.8, 42),
        _s(83, 600.0, 182.9, 37),
        _s(93, 392.2, 183.5, 32),
      ];
      expect(fitProjectiveTrack(noisy, maxRms: 0.002), isNull);
    });
  });

  group('폭 모델', () {
    test('겉보기 폭이 (ny − nyv)에 비례한다 — 멀수록 작다', () {
      final m = fitProjectiveTrack(_track)!;
      expect(m.widthScale, isNotNull);
      final near = m.widthAt(_track.first.contact.ny)!;
      final far = m.widthAt(_track.last.contact.ny)!;
      expect(near, greaterThan(far));
      // 실측 f63(51px) 대비 f93(32px) 비율을 모델이 재현하는지.
      final ratioActual = 32 / 51;
      final ratioModel =
          m.widthAt(_track[5].contact.ny)! / m.widthAt(_track[2].contact.ny)!;
      expect(ratioModel, closeTo(ratioActual, 0.08));
    });
  });

  group('buildProjectiveRibbon', () {
    test('관측 프레임은 검출값을 그대로 쓴다 — 선이 공 위에 정확히 얹힌다', () {
      final m = fitProjectiveTrack(_track)!;
      final ribbon = buildProjectiveRibbon(
        track: _track,
        model: m,
        endFrame: _impactFrame,
      );
      for (final s in _track) {
        final r = ribbon.firstWhere((e) => e.frame == s.frame);
        final centerNy = r.left.ny;
        final centerNx = (r.left.nx + r.right.nx) / 2;
        expect(centerNy, closeTo(s.contact.ny, 1e-9));
        expect(centerNx, closeTo(s.contact.nx, 1e-9));
        // 리본 폭 = 실측 bbox 폭.
        expect(r.right.nx - r.left.nx, closeTo(s.widthN, 1e-9));
      }
    });

    test('핀 충돌 프레임까지 연장되고 깊이가 단조 감소한다', () {
      final m = fitProjectiveTrack(_track)!;
      final ribbon = buildProjectiveRibbon(
        track: _track,
        model: m,
        endFrame: _impactFrame,
      );
      expect(ribbon.first.frame, _track.first.frame);
      expect(ribbon.last.frame, _impactFrame);
      for (var i = 1; i < ribbon.length; i++) {
        expect(ribbon[i].left.ny, lessThanOrEqualTo(ribbon[i - 1].left.ny),
            reason: 'f${ribbon[i].frame}');
      }
    });

    test('연장 구간 리본이 관측 구간보다 좁다 — 원근이 반영된다', () {
      final m = fitProjectiveTrack(_track)!;
      final ribbon = buildProjectiveRibbon(
        track: _track,
        model: m,
        endFrame: _impactFrame,
      );
      final atFirst = ribbon.first.right.nx - ribbon.first.left.nx;
      final atImpact = ribbon.last.right.nx - ribbon.last.left.nx;
      expect(atImpact, lessThan(atFirst));
      expect(atImpact, greaterThan(0));
    });

    test('startFrame으로 앞쪽 연장 — 릴리즈 직후 구간을 채운다', () {
      final m = fitProjectiveTrack(_track)!;
      final ribbon = buildProjectiveRibbon(
        track: _track,
        model: m,
        endFrame: _impactFrame,
        startFrame: 30,
      );
      expect(ribbon.first.frame, lessThan(_track.first.frame));
      // 앞쪽은 공이 카메라에 가까우므로 더 깊고(ny 큼) 더 굵다.
      expect(ribbon.first.left.ny, greaterThan(_track.first.contact.ny));
    });

    test('극점 이전 프레임은 요청해도 생기지 않는다', () {
      final m = fitProjectiveTrack(_track)!;
      final ribbon = buildProjectiveRibbon(
        track: _track,
        model: m,
        endFrame: _impactFrame,
        startFrame: -10000,
      );
      expect(ribbon.first.frame, greaterThan(m.poleFrame));
      expect(m.pointAt(m.poleFrame), isNull);
    });
  });
}
