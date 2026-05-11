import 'package:flutter/material.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/analysis_state_machine.dart';
import 'package:bowling_diary/features/analysis/presentation/viewmodels/live_analysis_view_model.dart';

/// 라이브 분석 HUD 오버레이
///
/// 현재 단계 칩, 볼 위치 점, 궤적 경로, 릴리즈 마커를 CustomPaint로 그린다.
class LiveHudOverlay extends StatelessWidget {
  final LiveAnalysisState state;

  const LiveHudOverlay({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final borderColor = _borderColorFor(state.phase);

    return Stack(
      children: [
        // 단계 표시 칩 (좌상단)
        Positioned(
          top: 16,
          left: 16,
          child: _PhaseChip(phase: state.phase),
        ),
        // 경계선 + 궤적/볼 점 오버레이
        Positioned.fill(
          child: CustomPaint(
            painter: _HudPainter(
              state: state,
              borderColor: borderColor,
            ),
          ),
        ),
      ],
    );
  }

  Color _borderColorFor(AnalysisPhase phase) {
    switch (phase) {
      case AnalysisPhase.flight:
        return Colors.greenAccent;
      case AnalysisPhase.release:
        return Colors.orangeAccent;
      default:
        return Colors.white54;
    }
  }
}

// ──────────────────────────────────────────────────────────────
// Phase 칩
// ──────────────────────────────────────────────────────────────

class _PhaseChip extends StatelessWidget {
  final AnalysisPhase phase;

  const _PhaseChip({required this.phase});

  @override
  Widget build(BuildContext context) {
    final label = _label(phase);
    final color = _color(phase);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  String _label(AnalysisPhase phase) {
    switch (phase) {
      case AnalysisPhase.idle:
        return 'IDLE';
      case AnalysisPhase.approach:
        return 'APPROACH';
      case AnalysisPhase.release:
        return 'RELEASE';
      case AnalysisPhase.flight:
        return 'FLIGHT';
      case AnalysisPhase.impact:
        return 'IMPACT';
      case AnalysisPhase.settle:
        return 'SETTLE';
    }
  }

  Color _color(AnalysisPhase phase) {
    switch (phase) {
      case AnalysisPhase.idle:
        return Colors.white54;
      case AnalysisPhase.approach:
        return Colors.yellowAccent;
      case AnalysisPhase.release:
        return Colors.orangeAccent;
      case AnalysisPhase.flight:
        return Colors.greenAccent;
      case AnalysisPhase.impact:
        return Colors.redAccent;
      case AnalysisPhase.settle:
        return Colors.blueAccent;
    }
  }
}

// ──────────────────────────────────────────────────────────────
// CustomPainter
// ──────────────────────────────────────────────────────────────

class _HudPainter extends CustomPainter {
  final LiveAnalysisState state;
  final Color borderColor;

  const _HudPainter({required this.state, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    _drawBorder(canvas, size);
    _drawTrajectory(canvas, size);
    _drawBallDot(canvas, size);
  }

  /// 화면 경계선 — 단계에 따라 색상 변경
  void _drawBorder(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor.withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(8, 8, size.width - 16, size.height - 16),
        const Radius.circular(8),
      ),
      paint,
    );
  }

  /// 궤적 경로 + 릴리즈 마커
  void _drawTrajectory(Canvas canvas, Size size) {
    if (state.trajectory.isEmpty) return;

    // 레인 좌표 → 프레임 좌표 → 화면 픽셀
    final screenPoints = state.trajectory
        .map((lane) => _laneToScreen(lane, size))
        .toList();

    if (screenPoints.isEmpty) return;

    // 궤적 경로
    final pathPaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(screenPoints.first.dx, screenPoints.first.dy);
    for (final pt in screenPoints.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path, pathPaint);

    // 릴리즈 마커 (궤적 첫 점)
    final markerPaint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.fill;

    canvas.drawCircle(screenPoints.first, 6.0, markerPaint);

    final markerRingPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(screenPoints.first, 6.0, markerRingPaint);
  }

  /// 현재 볼 위치 점
  void _drawBallDot(Canvas canvas, Size size) {
    final fp = state.lastBallFrame;
    if (fp == null) return;

    final pos = Offset(fp.nx * size.width, fp.ny * size.height);

    // 외곽 링
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(pos, 16.0, ringPaint);

    // 내부 점
    final dotPaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(pos, 8.0, dotPaint);
  }

  /// LanePoint → 화면 Offset
  ///
  /// 항등 행렬을 사용 중이라면 lane 좌표가 [0~1.05, 0~18.29] 범위이므로
  /// 화면에 직접 매핑할 수 없다. 대신 역호모그래피를 써서 정규화 프레임 좌표로
  /// 변환한 뒤 화면에 투영한다.
  Offset _laneToScreen(LanePoint lane, Size size) {
    final fp = state.homography.laneToFrame(lane);
    return Offset(fp.nx * size.width, fp.ny * size.height);
  }

  @override
  bool shouldRepaint(_HudPainter old) {
    return old.state != state || old.borderColor != borderColor;
  }
}
