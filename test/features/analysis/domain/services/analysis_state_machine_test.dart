import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

BallDetection _det({double bw = 0.05, double bh = 0.05}) =>
    BallDetection(cx: 0.5, cy: 0.3, bw: bw, bh: bh, confidence: 0.9);

void main() {
  group('AnalysisStateMachine', () {
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
  });
}
