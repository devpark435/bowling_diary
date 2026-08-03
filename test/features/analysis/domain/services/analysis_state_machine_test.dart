import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

BallDetection _det({double bw = 0.05, double bh = 0.05}) =>
    BallDetection(cx: 0.5, cy: 0.3, bw: bw, bh: bh, confidence: 0.9);

void main() {
  group('AnalysisStateMachine', () {
    test('임팩트 후 영상이 길게 이어져 idle로 되돌아가도 궤적이 남는다', () {
      // 실측 회귀: 210프레임 영상에서 settle→idle이 frame 209에 발생하자
      // _trajectory가 통째로 지워져, 같은 영상인데도 임팩트 도달 여부에 따라
      // 결과가 37포인트 / 0포인트로 갈렸다. 배치 사용자는 전 프레임을 먹인
      // 뒤에 trajectory를 읽으므로 완주분이 살아있어야 한다.
      final fsm = AnalysisStateMachine();
      var frameIdx = 0;

      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.03 + i * 0.01, bh: 0.03 + i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 1.0 + i * 0.3),
        );
      }
      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.08 - i * 0.01, bh: 0.08 - i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 2.8 + i * 0.3),
        );
      }
      // flight: 핀덱까지 주행 → 임팩트 전이
      for (var y = 5.0; y <= 18.5; y += 0.5) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(),
          lanePos: LanePoint(xM: 0.5, yM: y),
        );
      }
      expect(fsm.phase, AnalysisPhase.impact);
      final duringFlight = fsm.trajectory.length;
      expect(duringFlight, greaterThan(8));

      // impact(30) + settle(60) 을 넘겨 idle 복귀시킨다.
      for (var i = 0; i < 100; i++) {
        fsm.onFrame(frameIdx: frameIdx++, detection: null, lanePos: null);
      }
      expect(fsm.phase, AnalysisPhase.idle);
      expect(fsm.trajectory.length, duringFlight);
    });

    test('초기 상태는 idle', () {
      final fsm = AnalysisStateMachine();
      expect(fsm.phase, AnalysisPhase.idle);
    });

    test('검출 없으면 idle 유지', () {
      final fsm = AnalysisStateMachine();
      for (var i = 0; i < 10; i++) {
        fsm.onFrame(frameIdx: i, detection: null, lanePos: null);
      }
      expect(fsm.phase, AnalysisPhase.idle);
    });

    test('bbox 면적이 peak 지난 후 감소 + lane-y 단조증가 시 release 전이', () {
      final fsm = AnalysisStateMachine();
      var frameIdx = 0;
      // approach: 면적 증가 (백스윙→어프로치 peak)
      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.03 + i * 0.01, bh: 0.03 + i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 1.0 + i * 0.3),
        );
      }
      // release: 면적 감소 + lane-y 계속 증가
      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.08 - i * 0.01, bh: 0.08 - i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 2.8 + i * 0.3),
        );
      }
      expect(fsm.releaseFrame, isNotNull);
    });

    test('reset 후 idle로 복귀하고 trajectory 비워짐', () {
      final fsm = AnalysisStateMachine();
      fsm.onFrame(frameIdx: 0, detection: _det(), lanePos: const LanePoint(xM: 0.5, yM: 1.0));
      fsm.reset();
      expect(fsm.phase, AnalysisPhase.idle);
      expect(fsm.trajectory, isEmpty);
      expect(fsm.releaseFrame, isNull);
    });

    test('release phase 동안에는 trajectory를 누적하지 않는다 (손 구간 오버레이 누출 방지)', () {
      final fsm = AnalysisStateMachine();
      var frameIdx = 0;
      // approach: 면적 증가 (백스윙→어프로치 peak)
      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.03 + i * 0.01, bh: 0.03 + i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 1.0 + i * 0.3),
        );
      }
      // release: 면적 감소 + lane-y 계속 증가 → release 전이 발생.
      // 이 6프레임 안에서 release 전이(frame 7)와 release phase 창(4프레임, frame
      // 8~11)이 모두 소비되어 마지막 프레임에서 이미 flight로 전이된다 — 기존
      // "bbox 면적이 peak..." 테스트와 동일한 프레임 진행.
      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.08 - i * 0.01, bh: 0.08 - i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 2.8 + i * 0.3),
        );
      }
      expect(fsm.releaseFrame, isNotNull);
      expect(fsm.phase, AnalysisPhase.flight);
      // release phase(고정 4프레임 창) 동안 lanePos가 있었음에도 trajectory는
      // 비어 있어야 한다 — 손 구간 오버레이 누출 방지 (Fix 1).
      expect(fsm.trajectory, isEmpty);

      // flight phase에 확실히 진입한 뒤 유효한 lanePos를 주면 그때부터는 누적된다.
      fsm.onFrame(
        frameIdx: frameIdx++,
        detection: _det(),
        lanePos: const LanePoint(xM: 0.5, yM: 5.0),
      );
      expect(fsm.trajectory, hasLength(1));
    });

    test('flight phase에서 yM < 0(파울라인 뒤)인 lanePos는 trajectory에 걸러진다', () {
      final fsm = AnalysisStateMachine();
      var frameIdx = 0;
      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.03 + i * 0.01, bh: 0.03 + i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 1.0 + i * 0.3),
        );
      }
      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.08 - i * 0.01, bh: 0.08 - i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 2.8 + i * 0.3),
        );
      }
      expect(fsm.phase, AnalysisPhase.flight);
      expect(fsm.trajectory, isEmpty);

      fsm.onFrame(
        frameIdx: frameIdx++,
        detection: _det(),
        lanePos: const LanePoint(xM: 0.5, yM: -0.5),
      );
      expect(fsm.trajectory, isEmpty);

      fsm.onFrame(
        frameIdx: frameIdx++,
        detection: _det(),
        lanePos: const LanePoint(xM: 0.5, yM: 1.0),
      );
      expect(fsm.trajectory, hasLength(1));
      expect(fsm.trajectory.last.lane.yM, 1.0);
    });

    test('브레이크포인트 구간(레인 얕음)에서 5프레임 연속 미검출은 impact를 오탐하지 않는다', () {
      final fsm = AnalysisStateMachine();
      var frameIdx = 0;
      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.03 + i * 0.01, bh: 0.03 + i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 1.0 + i * 0.3),
        );
      }
      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.08 - i * 0.01, bh: 0.08 - i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 2.8 + i * 0.3),
        );
      }
      expect(fsm.phase, AnalysisPhase.flight);

      // 브레이크포인트 구간(약 8.0m)에서 마지막 유효 위치 기록
      fsm.onFrame(
        frameIdx: frameIdx++,
        detection: _det(),
        lanePos: const LanePoint(xM: 0.5, yM: 8.0),
      );

      // 이후 5프레임 연속 미검출
      for (var i = 0; i < 5; i++) {
        fsm.onFrame(frameIdx: frameIdx++, detection: null, lanePos: null);
      }

      expect(fsm.phase, AnalysisPhase.flight);
      expect(fsm.impactFrame, isNull);
    });

    test('핀 근처 깊은 레인에서 5프레임 연속 미검출은 impact로 정상 전이한다', () {
      final fsm = AnalysisStateMachine();
      var frameIdx = 0;
      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.03 + i * 0.01, bh: 0.03 + i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 1.0 + i * 0.3),
        );
      }
      for (var i = 0; i < 6; i++) {
        fsm.onFrame(
          frameIdx: frameIdx++,
          detection: _det(bw: 0.08 - i * 0.01, bh: 0.08 - i * 0.01),
          lanePos: LanePoint(xM: 0.5, yM: 2.8 + i * 0.3),
        );
      }
      expect(fsm.phase, AnalysisPhase.flight);

      // 핀 근처(약 16.0m)에서 마지막 유효 위치 기록
      fsm.onFrame(
        frameIdx: frameIdx++,
        detection: _det(),
        lanePos: const LanePoint(xM: 0.5, yM: 16.0),
      );

      int? lastFrame;
      for (var i = 0; i < 5; i++) {
        lastFrame = frameIdx;
        fsm.onFrame(frameIdx: frameIdx++, detection: null, lanePos: null);
      }

      expect(fsm.phase, AnalysisPhase.impact);
      expect(fsm.impactFrame, lastFrame);
    });
  });
}
