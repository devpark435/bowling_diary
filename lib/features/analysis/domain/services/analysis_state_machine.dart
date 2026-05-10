import 'package:flutter/foundation.dart' show debugPrint;

import 'package:bowling_diary/features/analysis/data/services/ball_detection_service.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

/// 볼링 영상 분석 단계 열거형
enum AnalysisPhase {
  /// 볼 미감지 상태
  idle,

  /// 볼 감지됨, 어프로치 진행 중
  approach,

  /// 릴리즈 직후 전환 상태 (수 프레임 지속)
  release,

  /// 볼이 레인에서 핀 덱을 향해 이동 중
  flight,

  /// 볼이 핀 덱 도달 (yM >= 18.0m)
  impact,

  /// 충돌 후 대기 상태
  settle,
}

/// 볼링 영상 분석 온라인 상태머신
///
/// 프레임 단위로 [onFrame]을 호출하면 내부 상태를 갱신한다.
/// 배치 모드(프레임 순차 재생) 및 실시간 모드 모두에서 사용 가능.
class AnalysisStateMachine {
  AnalysisPhase _phase = AnalysisPhase.idle;
  int _phaseStartFrame = 0;

  int? _releaseFrame;
  int? _impactFrame;

  /// flight 단계에서 누적된 레인 좌표 목록
  final List<({int frame, LanePoint lane})> _trajectory = [];

  // approach → release 감지용 rolling 윈도우
  final List<({int frame, double area})> _recentAreas = [];
  static const _areaWindowSize = 5;

  // flight 중 detection null 연속 카운터
  int _flightNullCount = 0;

  // 최근 유효 lanePos (forward score 계산용)
  final List<double> _recentLaneY = [];
  static const _laneYWindowSize = 3;

  // ── 공개 API ──────────────────────────────────────────────

  /// 현재 분석 단계
  AnalysisPhase get phase => _phase;

  /// idle → ... → release 전환이 발생한 프레임 인덱스 (전환 전까지 null)
  int? get releaseFrame => _releaseFrame;

  /// flight → impact 전환이 발생한 프레임 인덱스 (전환 전까지 null)
  int? get impactFrame => _impactFrame;

  /// release·flight 단계에서 누적된 레인 좌표 목록
  List<({int frame, LanePoint lane})> get trajectory =>
      List.unmodifiable(_trajectory);

  // ── 주요 메서드 ────────────────────────────────────────────

  /// 프레임 하나를 처리하여 상태를 갱신한다.
  ///
  /// [frameIdx] : 처리 중인 프레임 번호 (0-based)
  /// [detection] : YOLO 볼 감지 결과 (null = 미감지)
  /// [lanePos]   : 호모그래피 변환 레인 좌표 (null = 호모그래피 없음 또는 미감지)
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

  /// 상태머신을 초기 상태로 리셋한다.
  void reset() {
    _phase = AnalysisPhase.idle;
    _phaseStartFrame = 0;
    _releaseFrame = null;
    _impactFrame = null;
    _trajectory.clear();
    _recentAreas.clear();
    _recentLaneY.clear();
    _flightNullCount = 0;
    debugPrint('[AnalysisFSM] reset → idle');
  }

  // ── 상태 핸들러 ───────────────────────────────────────────

  void _handleIdle(
    int frameIdx,
    BallDetection? detection,
    LanePoint? lanePos,
  ) {
    if (detection != null) {
      _transitionTo(AnalysisPhase.approach, frameIdx);
      // approach 진입 직후 area 윈도우 초기화 및 첫 샘플 추가
      _recentAreas.clear();
      _recentLaneY.clear();
      _addArea(frameIdx, detection);
      _addLaneY(lanePos);
    }
  }

  void _handleApproach(
    int frameIdx,
    BallDetection? detection,
    LanePoint? lanePos,
  ) {
    if (detection == null) {
      // 감지 소실 → 롤링 윈도우만 유지 (approach 유지)
      return;
    }

    _addArea(frameIdx, detection);
    _addLaneY(lanePos);

    if (_shouldTransitionToRelease()) {
      _releaseFrame = frameIdx;
      _transitionTo(AnalysisPhase.release, frameIdx);
    }
  }

  void _handleRelease(
    int frameIdx,
    BallDetection? detection,
    LanePoint? lanePos,
  ) {
    // trajectory 누적
    if (lanePos != null) {
      _trajectory.add((frame: frameIdx, lane: lanePos));
    }

    // 4프레임 후 flight 전환
    if (frameIdx - _phaseStartFrame >= 4) {
      _transitionTo(AnalysisPhase.flight, frameIdx);
    }
  }

  void _handleFlight(
    int frameIdx,
    BallDetection? detection,
    LanePoint? lanePos,
  ) {
    // trajectory 누적
    if (lanePos != null) {
      _trajectory.add((frame: frameIdx, lane: lanePos));
    }

    // 핀 덱 도달 체크
    if (lanePos != null && lanePos.yM >= 18.0) {
      _impactFrame = frameIdx;
      _transitionTo(AnalysisPhase.impact, frameIdx);
      return;
    }

    // 연속 null 감지 체크
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
    // 30프레임 후 settle 전환
    if (frameIdx - _phaseStartFrame >= 30) {
      _transitionTo(AnalysisPhase.settle, frameIdx);
    }
  }

  void _handleSettle(int frameIdx) {
    // 60프레임 후 idle 전환
    if (frameIdx - _phaseStartFrame >= 60) {
      _transitionTo(AnalysisPhase.idle, frameIdx);
      // idle 재진입 시 trajectory 초기화
      _trajectory.clear();
    }
  }

  // ── 헬퍼 ─────────────────────────────────────────────────

  void _transitionTo(AnalysisPhase next, int frameIdx) {
    debugPrint('[AnalysisFSM] ${_phase.name} → ${next.name} (frame $frameIdx)');
    _phase = next;
    _phaseStartFrame = frameIdx;
  }

  void _addArea(int frameIdx, BallDetection detection) {
    final area = detection.bw * detection.bh;
    _recentAreas.add((frame: frameIdx, area: area));
    if (_recentAreas.length > _areaWindowSize) {
      _recentAreas.removeAt(0);
    }
  }

  void _addLaneY(LanePoint? lanePos) {
    if (lanePos == null) return;
    _recentLaneY.add(lanePos.yM);
    if (_recentLaneY.length > _laneYWindowSize) {
      _recentLaneY.removeAt(0);
    }
  }

  /// approach → release 전환 조건 판단
  ///
  /// - 5프레임 롤링 윈도우가 꽉 찬 상태에서
  /// - 가장 최근 area < 윈도우 내 최대 area (=정점 통과)
  /// - AND (lane forward score 충족 OR lanePos 없는 경우 bbox shrink만으로 판단)
  bool _shouldTransitionToRelease() {
    if (_recentAreas.length < _areaWindowSize) return false;

    final currentArea = _recentAreas.last.area;
    final maxArea =
        _recentAreas.map((e) => e.area).reduce((a, b) => a > b ? a : b);

    // 정점 이후 bbox 감소 체크
    final pastPeak = currentArea < maxArea;
    if (!pastPeak) return false;

    // lane forward 체크 (laneY 데이터 있는 경우)
    if (_recentLaneY.length >= _laneYWindowSize) {
      // 최근 3개 laneY가 단조 증가하면 forward motion 확인
      bool monotonicallyIncreasing = true;
      for (int i = 1; i < _recentLaneY.length; i++) {
        if (_recentLaneY[i] <= _recentLaneY[i - 1]) {
          monotonicallyIncreasing = false;
          break;
        }
      }
      return monotonicallyIncreasing;
    }

    // lanePos 없는 경우 bbox shrink만으로 release 감지
    return true;
  }
}
