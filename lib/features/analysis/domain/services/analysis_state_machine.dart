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

  final List<({int frame, double area})> _recentAreas = [];
  static const _areaWindowSize = 5;

  int _flightNullCount = 0;

  final List<double> _recentLaneY = [];
  static const _laneYWindowSize = 3;

  AnalysisPhase get phase => _phase;
  int? get releaseFrame => _releaseFrame;
  int? get impactFrame => _impactFrame;
  List<({int frame, LanePoint lane})> get trajectory => List.unmodifiable(_trajectory);

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
    _recentAreas.clear();
    _recentLaneY.clear();
    _flightNullCount = 0;
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
    if (lanePos != null) {
      _trajectory.add((frame: frameIdx, lane: lanePos));
    }
    if (frameIdx - _phaseStartFrame >= 4) {
      _transitionTo(AnalysisPhase.flight, frameIdx);
    }
  }

  void _handleFlight(int frameIdx, BallDetection? detection, LanePoint? lanePos) {
    if (lanePos != null) {
      _trajectory.add((frame: frameIdx, lane: lanePos));
    }
    if (lanePos != null && lanePos.yM >= 18.29) {
      _impactFrame = frameIdx;
      _transitionTo(AnalysisPhase.impact, frameIdx);
      return;
    }
    if (detection == null) {
      _flightNullCount++;
      if (_flightNullCount >= 5) {
        _impactFrame = frameIdx;
        _transitionTo(AnalysisPhase.impact, frameIdx);
      }
    } else {
      _flightNullCount = 0;
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
