import 'package:flutter_test/flutter_test.dart';

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';

// ── 헬퍼 팩토리 ─────────────────────────────────────────────────

BallDetection _det({double cx = 0.5, double cy = 0.5, double bw = 0.1, double bh = 0.1}) =>
    BallDetection(cx: cx, cy: cy, bw: bw, bh: bh, confidence: 0.9);

/// area = bw * bh 가 되도록 생성
BallDetection _detArea(double area) {
  final side = area; // bw = area, bh = 1.0 → area = bw*bh
  return BallDetection(cx: 0.5, cy: 0.5, bw: side, bh: 1.0, confidence: 0.9);
}

LanePoint _lane(double y) => LanePoint(xM: 0.5, yM: y);

/// AnalysisStateMachine을 approach 단계로 진입시키고 롤링 윈도우를 준비한다.
/// areas: 5개, laneYs: 5개 (approach 첫 프레임 포함)
/// 반환값: 마지막으로 투입한 프레임 인덱스
int _setupApproach(
  AnalysisStateMachine fsm,
  List<double> areas, {
  List<double>? laneYs,
  int startFrame = 0,
}) {
  assert(areas.length == 5);
  int frame = startFrame;
  for (int i = 0; i < areas.length; i++) {
    final lanePos = laneYs != null ? _lane(laneYs[i]) : null;
    fsm.onFrame(
      frameIdx: frame,
      detection: _detArea(areas[i]),
      lanePos: lanePos,
    );
    frame++;
  }
  return frame - 1;
}

void main() {
  group('AnalysisStateMachine', () {
    late AnalysisStateMachine fsm;

    setUp(() {
      fsm = AnalysisStateMachine();
    });

    // ── 1. 초기 상태 ──────────────────────────────────────────────
    test('초기 상태는 idle', () {
      expect(fsm.phase, AnalysisPhase.idle);
      expect(fsm.releaseFrame, isNull);
      expect(fsm.impactFrame, isNull);
      expect(fsm.trajectory, isEmpty);
    });

    // ── 2. idle → approach ────────────────────────────────────────
    test('detection 보이면 idle → approach', () {
      fsm.onFrame(frameIdx: 0, detection: _det(), lanePos: null);
      expect(fsm.phase, AnalysisPhase.approach);
    });

    // ── 3. 백스윙 정점 후 lane y 증가 → release ───────────────────
    test('백스윙 정점 후 lane y 증가 → release', () {
      // frame 0-4: bbox 면적 증가, lane y 일정
      _setupApproach(
        fsm,
        [1.0, 1.2, 1.4, 1.6, 1.8],
        laneYs: [0.1, 0.1, 0.1, 0.1, 0.1],
        startFrame: 0,
      );
      expect(fsm.phase, AnalysisPhase.approach);

      // frame 5: bbox 감소, lane y 증가 시작
      fsm.onFrame(frameIdx: 5, detection: _detArea(1.5), lanePos: _lane(0.2));
      // frame 6: bbox 더 감소, lane y 증가
      fsm.onFrame(frameIdx: 6, detection: _detArea(1.0), lanePos: _lane(0.4));
      // frame 7: bbox 더 감소, lane y 계속 증가
      fsm.onFrame(frameIdx: 7, detection: _detArea(0.8), lanePos: _lane(0.7));

      expect(fsm.phase, AnalysisPhase.release);
      expect(fsm.releaseFrame, isNotNull);
    });

    // ── 4. release 후 4프레임 → flight ───────────────────────────
    test('release 후 4프레임 → flight', () {
      // approach 진입 및 release 유도
      _setupApproach(
        fsm,
        [1.0, 1.2, 1.4, 1.6, 1.8],
        laneYs: [0.1, 0.1, 0.1, 0.1, 0.1],
        startFrame: 0,
      );
      fsm.onFrame(frameIdx: 5, detection: _detArea(1.5), lanePos: _lane(0.2));
      fsm.onFrame(frameIdx: 6, detection: _detArea(1.0), lanePos: _lane(0.4));
      fsm.onFrame(frameIdx: 7, detection: _detArea(0.8), lanePos: _lane(0.7));

      // 이 시점에 release 상태여야 함
      expect(fsm.phase, AnalysisPhase.release);
      final releaseStart = fsm.releaseFrame!;

      // release 진입 직후 4프레임 추가
      for (int i = 1; i <= 4; i++) {
        fsm.onFrame(
          frameIdx: releaseStart + i,
          detection: _det(),
          lanePos: _lane(1.0 + i * 0.5),
        );
      }

      expect(fsm.phase, AnalysisPhase.flight);
    });

    // ── 5. lane y >= 18.0 → impact ───────────────────────────────
    test('lane y >= 18.0 → impact', () {
      // approach → release → flight 유도
      _setupApproach(
        fsm,
        [1.0, 1.2, 1.4, 1.6, 1.8],
        laneYs: [0.1, 0.1, 0.1, 0.1, 0.1],
        startFrame: 0,
      );
      fsm.onFrame(frameIdx: 5, detection: _detArea(1.5), lanePos: _lane(0.2));
      fsm.onFrame(frameIdx: 6, detection: _detArea(1.0), lanePos: _lane(0.4));
      fsm.onFrame(frameIdx: 7, detection: _detArea(0.8), lanePos: _lane(0.7));

      final releaseStart = fsm.releaseFrame!;
      for (int i = 1; i <= 4; i++) {
        fsm.onFrame(
          frameIdx: releaseStart + i,
          detection: _det(),
          lanePos: _lane(5.0),
        );
      }
      expect(fsm.phase, AnalysisPhase.flight);

      // 핀 덱 도달
      final flightStart = releaseStart + 4;
      fsm.onFrame(
        frameIdx: flightStart + 1,
        detection: _det(),
        lanePos: _lane(18.5),
      );

      expect(fsm.phase, AnalysisPhase.impact);
      expect(fsm.impactFrame, isNotNull);
    });

    // ── 6. flight 중 detection 5프레임 연속 null → impact ─────────
    test('flight 중 detection 5프레임 연속 null → impact', () {
      // flight 상태로 진입
      _setupApproach(
        fsm,
        [1.0, 1.2, 1.4, 1.6, 1.8],
        laneYs: [0.1, 0.1, 0.1, 0.1, 0.1],
        startFrame: 0,
      );
      fsm.onFrame(frameIdx: 5, detection: _detArea(1.5), lanePos: _lane(0.2));
      fsm.onFrame(frameIdx: 6, detection: _detArea(1.0), lanePos: _lane(0.4));
      fsm.onFrame(frameIdx: 7, detection: _detArea(0.8), lanePos: _lane(0.7));

      final releaseStart = fsm.releaseFrame!;
      for (int i = 1; i <= 4; i++) {
        fsm.onFrame(
          frameIdx: releaseStart + i,
          detection: _det(),
          lanePos: _lane(5.0),
        );
      }
      expect(fsm.phase, AnalysisPhase.flight);

      final flightStart = releaseStart + 4;
      // 5프레임 연속 null
      for (int i = 1; i <= 5; i++) {
        fsm.onFrame(
          frameIdx: flightStart + i,
          detection: null,
          lanePos: null,
        );
      }

      expect(fsm.phase, AnalysisPhase.impact);
    });

    // ── 7. impact → settle → idle 자동 전이 ──────────────────────
    test('impact → settle → idle 자동 전이', () {
      // impact 상태로 직접 진입하는 헬퍼
      void reachImpact() {
        _setupApproach(
          fsm,
          [1.0, 1.2, 1.4, 1.6, 1.8],
          laneYs: [0.1, 0.1, 0.1, 0.1, 0.1],
          startFrame: 0,
        );
        fsm.onFrame(frameIdx: 5, detection: _detArea(1.5), lanePos: _lane(0.2));
        fsm.onFrame(frameIdx: 6, detection: _detArea(1.0), lanePos: _lane(0.4));
        fsm.onFrame(frameIdx: 7, detection: _detArea(0.8), lanePos: _lane(0.7));

        final releaseStart = fsm.releaseFrame!;
        for (int i = 1; i <= 4; i++) {
          fsm.onFrame(
            frameIdx: releaseStart + i,
            detection: _det(),
            lanePos: _lane(5.0),
          );
        }
        fsm.onFrame(
          frameIdx: releaseStart + 5,
          detection: _det(),
          lanePos: _lane(18.5),
        );
      }

      reachImpact();
      expect(fsm.phase, AnalysisPhase.impact);

      final impactStart = fsm.impactFrame!;

      // 30프레임 → settle
      for (int i = 1; i <= 30; i++) {
        fsm.onFrame(frameIdx: impactStart + i, detection: null, lanePos: null);
      }
      expect(fsm.phase, AnalysisPhase.settle);

      // 60프레임 → idle
      final settleStart = impactStart + 30;
      for (int i = 1; i <= 60; i++) {
        fsm.onFrame(frameIdx: settleStart + i, detection: null, lanePos: null);
      }
      expect(fsm.phase, AnalysisPhase.idle);
    });

    // ── 8. trajectory: flight 동안 lanePos 누적 ──────────────────
    test('trajectory: flight 동안 lanePos 누적', () {
      // flight 상태로 진입
      _setupApproach(
        fsm,
        [1.0, 1.2, 1.4, 1.6, 1.8],
        laneYs: [0.1, 0.1, 0.1, 0.1, 0.1],
        startFrame: 0,
      );
      fsm.onFrame(frameIdx: 5, detection: _detArea(1.5), lanePos: _lane(0.2));
      fsm.onFrame(frameIdx: 6, detection: _detArea(1.0), lanePos: _lane(0.4));
      fsm.onFrame(frameIdx: 7, detection: _detArea(0.8), lanePos: _lane(0.7));

      final releaseStart = fsm.releaseFrame!;
      // release 단계 4프레임 (lanePos 포함 → trajectory 누적)
      for (int i = 1; i <= 4; i++) {
        fsm.onFrame(
          frameIdx: releaseStart + i,
          detection: _det(),
          lanePos: _lane(1.0 + i.toDouble()),
        );
      }
      expect(fsm.phase, AnalysisPhase.flight);

      final flightStart = releaseStart + 4;
      // trajectory 초기화 후 flight에서만 세기 위해 현재 크기 기록
      final trajBeforeFlight = fsm.trajectory.length;

      // flight 3프레임
      for (int i = 1; i <= 3; i++) {
        fsm.onFrame(
          frameIdx: flightStart + i,
          detection: _det(),
          lanePos: _lane(5.0 + i.toDouble()),
        );
      }

      expect(fsm.trajectory.length, trajBeforeFlight + 3);
    });

    // ── 9. reset() — 모든 상태 초기화 ────────────────────────────
    test('reset() — 모든 상태 초기화', () {
      // approach 상태로 진입
      fsm.onFrame(frameIdx: 0, detection: _det(), lanePos: null);
      expect(fsm.phase, AnalysisPhase.approach);

      fsm.reset();

      expect(fsm.phase, AnalysisPhase.idle);
      expect(fsm.releaseFrame, isNull);
      expect(fsm.impactFrame, isNull);
      expect(fsm.trajectory, isEmpty);
    });

    // ── 10. homography 없는 경우 bbox shrink만으로 release 감지 ───
    test('homography 없는 경우 (lanePos null) — bbox shrink만으로 release 감지', () {
      // frame 0-4: bbox 면적 증가, lanePos = null
      _setupApproach(
        fsm,
        [1.0, 1.2, 1.4, 1.6, 1.8],
        laneYs: null, // lanePos 없음
        startFrame: 0,
      );
      expect(fsm.phase, AnalysisPhase.approach);

      // frame 5: bbox 면적 감소 (정점 통과), lanePos null
      fsm.onFrame(frameIdx: 5, detection: _detArea(1.5), lanePos: null);
      // frame 6: bbox 더 감소
      fsm.onFrame(frameIdx: 6, detection: _detArea(1.0), lanePos: null);
      // frame 7: bbox 더 감소
      fsm.onFrame(frameIdx: 7, detection: _detArea(0.8), lanePos: null);

      expect(fsm.phase, AnalysisPhase.release);
      expect(fsm.releaseFrame, isNotNull);
    });
  });
}
