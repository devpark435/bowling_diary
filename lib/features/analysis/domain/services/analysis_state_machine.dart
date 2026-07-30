import 'package:flutter/foundation.dart' show debugPrint;

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

enum AnalysisPhase { idle, approach, release, flight, impact, settle }

class AnalysisStateMachine {
  AnalysisPhase _phase = AnalysisPhase.idle;
  int _phaseStartFrame = 0;

  int? _releaseFrame;
  int? _impactFrame;

  final List<({int frame, LanePoint lane})> _trajectory = [];

  /// 직전에 **완주한** 투구의 궤적.
  ///
  /// 이 FSM은 실시간 세션용이라 settle→idle에서 다음 투구를 위해 궤적을 비운다.
  /// 그런데 파이프라인은 영상 전체를 다 먹인 **뒤에** [trajectory]를 읽는 배치
  /// 사용자다. 영상이 임팩트 후 90프레임 이상 더 이어지면 마지막 프레임 근처에서
  /// idle로 되돌아가며 궤적이 통째로 지워져, 같은 영상인데도 임팩트 도달 여부에
  /// 따라 결과가 37포인트 또는 0포인트로 갈렸다(실측). 완주분을 따로 붙잡아
  /// 배치 사용자가 잃지 않게 한다.
  List<({int frame, LanePoint lane})> _completedTrajectory = const [];

  final List<({int frame, double area})> _recentAreas = [];
  static const _areaWindowSize = 5;

  int _flightNullCount = 0;
  double? _lastFlightLaneY;

  // 5프레임 연속 미검출을 "임팩트 도달"로 간주하려면 이미 레인 깊숙이(18.29m의 약 75%) 들어가 있어야 한다.
  // 훅 브레이크포인트는 보통 6~12m 구간에서 발생하므로, 그 구간에서 일시적으로 검출을 놓쳐도
  // 이 임계값에 못 미쳐 false-positive 임팩트로 이어지지 않는다. 회복 안 되고 끝까지 놓치면
  // impactFrame이 끝내 null로 남아 파이프라인이 "측정불가"로 정직하게 실패한다(스펙 원칙: 틀린 숫자보다 정직한 실패).
  static const double _nullCountImpactMinY = 14.0;

  final List<double> _recentLaneY = [];
  static const _laneYWindowSize = 3;

  AnalysisPhase get phase => _phase;
  int? get releaseFrame => _releaseFrame;
  int? get impactFrame => _impactFrame;
  /// 진행 중인 궤적이 있으면 그것을, 없으면 직전 완주 투구의 궤적을 준다.
  List<({int frame, LanePoint lane})> get trajectory => List.unmodifiable(
        _trajectory.isNotEmpty ? _trajectory : _completedTrajectory,
      );

  void onFrame({
    required int frameIdx,
    required BallDetection? detection,
    required LanePoint? lanePos,
  }) {
    switch (_phase) {
      case AnalysisPhase.idle:
        _handleIdle(frameIdx, detection, lanePos);
      case AnalysisPhase.approach:
        _handleApproach(frameIdx, detection, lanePos);
      case AnalysisPhase.release:
        _handleRelease(frameIdx, detection, lanePos);
      case AnalysisPhase.flight:
        _handleFlight(frameIdx, detection, lanePos);
      case AnalysisPhase.impact:
        _handleImpact(frameIdx);
      case AnalysisPhase.settle:
        _handleSettle(frameIdx);
    }
  }

  void reset() {
    _phase = AnalysisPhase.idle;
    _phaseStartFrame = 0;
    _releaseFrame = null;
    _impactFrame = null;
    _trajectory.clear();
    _completedTrajectory = const [];
    _recentAreas.clear();
    _recentLaneY.clear();
    _flightNullCount = 0;
    _lastFlightLaneY = null;
  }

  void _handleIdle(int frameIdx, BallDetection? detection, LanePoint? lanePos) {
    if (detection != null) {
      _transitionTo(AnalysisPhase.approach, frameIdx);
      _recentAreas.clear();
      _recentLaneY.clear();
      _addArea(frameIdx, detection);
      _addLaneY(lanePos);
    }
  }

  void _handleApproach(int frameIdx, BallDetection? detection, LanePoint? lanePos) {
    if (detection == null) return;
    _addArea(frameIdx, detection);
    _addLaneY(lanePos);
    if (_shouldTransitionToRelease()) {
      _releaseFrame = frameIdx;
      _transitionTo(AnalysisPhase.release, frameIdx);
    }
  }

  void _handleRelease(int frameIdx, BallDetection? detection, LanePoint? lanePos) {
    // release는 릴리즈 직후 전환 상태(고정 4프레임 창)일 뿐, 공이 레인 위에 있다고
    // 확정된 상태가 아니다. 이 구간에서 lanePos를 궤적에 누적하면 아직 손 안(레인
    // 평면 밖)에 있는 공이 homography를 통해 왜곡된 좌표로 투영되어 궤적 오버레이가
    // 어프로치/손 구간까지 그려지는 문제가 생긴다. 궤적 누적은 flight 진입 후에만.
    if (frameIdx - _phaseStartFrame >= 4) {
      _transitionTo(AnalysisPhase.flight, frameIdx);
    }
  }

  void _handleFlight(int frameIdx, BallDetection? detection, LanePoint? lanePos) {
    if (lanePos != null && lanePos.yM >= 0) {
      _trajectory.add((frame: frameIdx, lane: lanePos));
    }
    if (lanePos != null && lanePos.yM >= 18.29) {
      _impactFrame = frameIdx;
      _transitionTo(AnalysisPhase.impact, frameIdx);
      return;
    }
    if (detection == null) {
      _flightNullCount++;
      if (_flightNullCount >= 5 && _lastFlightLaneY != null && _lastFlightLaneY! >= _nullCountImpactMinY) {
        _impactFrame = frameIdx;
        _transitionTo(AnalysisPhase.impact, frameIdx);
      }
    } else {
      _flightNullCount = 0;
      if (lanePos != null) {
        _lastFlightLaneY = lanePos.yM;
      }
    }
  }

  void _handleImpact(int frameIdx) {
    if (frameIdx - _phaseStartFrame >= 30) {
      _transitionTo(AnalysisPhase.settle, frameIdx);
    }
  }

  void _handleSettle(int frameIdx) {
    if (frameIdx - _phaseStartFrame >= 60) {
      _transitionTo(AnalysisPhase.idle, frameIdx);
      // 실시간 오버레이가 지난 투구 선을 계속 그리지 않도록 진행분은 비우되,
      // 배치 사용자가 읽을 수 있게 완주분은 남긴다.
      _completedTrajectory = List.of(_trajectory);
      _trajectory.clear();
    }
  }

  void _transitionTo(AnalysisPhase next, int frameIdx) {
    debugPrint('[AnalysisFSM] ${_phase.name} → ${next.name} (frame $frameIdx)');
    _phase = next;
    _phaseStartFrame = frameIdx;
  }

  void _addArea(int frameIdx, BallDetection detection) {
    final area = detection.bw * detection.bh;
    _recentAreas.add((frame: frameIdx, area: area));
    if (_recentAreas.length > _areaWindowSize) _recentAreas.removeAt(0);
  }

  void _addLaneY(LanePoint? lanePos) {
    if (lanePos == null) return;
    _recentLaneY.add(lanePos.yM);
    if (_recentLaneY.length > _laneYWindowSize) _recentLaneY.removeAt(0);
  }

  bool _shouldTransitionToRelease() {
    if (_recentAreas.length < _areaWindowSize) return false;
    final currentArea = _recentAreas.last.area;
    final maxArea = _recentAreas.map((e) => e.area).reduce((a, b) => a > b ? a : b);
    final pastPeak = currentArea < maxArea;
    if (!pastPeak) return false;
    if (_recentLaneY.length >= _laneYWindowSize) {
      bool monotonicallyIncreasing = true;
      for (int i = 1; i < _recentLaneY.length; i++) {
        if (_recentLaneY[i] <= _recentLaneY[i - 1]) {
          monotonicallyIncreasing = false;
          break;
        }
      }
      return monotonicallyIncreasing;
    }
    return true;
  }
}
