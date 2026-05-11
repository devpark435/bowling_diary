import 'package:flutter/material.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

/// 볼링 레인 위에 볼 트래젝토리를 시각화하는 위젯.
///
/// 레인을 위에서 내려다본 탑뷰로 표현:
/// - 상단: 핀 덱 (y ≈ 18.29m)
/// - 하단: 파울 라인 (y = 0m)
class TrajectoryChart extends StatelessWidget {
  /// 비행 좌표 시계열 (미터 단위, x: 0~1.05, y: 0~18.29)
  final List<LanePoint> trajectory;

  /// 곡률 최대 지점 (브레이크 포인트). null이면 표시 안 함.
  final LanePoint? breakPos;

  /// 릴리즈 위치. null이면 trajectory.first를 사용.
  final LanePoint? releasePos;

  /// 위젯 가로/세로 비율. 레인 실제 비율: 1.05 / 18.29 ≈ 0.057.
  final double aspectRatio;

  const TrajectoryChart({
    super.key,
    required this.trajectory,
    this.breakPos,
    this.releasePos,
    this.aspectRatio = 1.05 / 18.29,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: CustomPaint(
        painter: _TrajectoryPainter(
          trajectory: trajectory,
          breakPos: breakPos,
          releasePos: releasePos,
        ),
      ),
    );
  }
}

/// 트래젝토리 CustomPainter.
///
/// 좌표 매핑:
///   canvas.x = xM / 1.05 * canvasWidth
///   canvas.y = (1 - yM / 18.29) * canvasHeight  (y축 반전: 핀 덱이 상단)
class _TrajectoryPainter extends CustomPainter {
  static const double _laneWidth = 1.05;
  static const double _laneLength = 18.29;

  // 핀 덱 y 기준 위치 (레인 좌표, 미터)
  static const double _pinDeckY = 17.5;
  // 핀 간격 (미터, 장식용)
  static const double _pinSpacing = 0.10;
  // 핀 반지름 (캔버스 픽셀)
  static const double _pinRadius = 2.5;
  // 마커 반지름 (캔버스 픽셀)
  static const double _markerRadius = 5.0;

  final List<LanePoint> trajectory;
  final LanePoint? breakPos;
  final LanePoint? releasePos;

  const _TrajectoryPainter({
    required this.trajectory,
    this.breakPos,
    this.releasePos,
  });

  /// 레인 좌표(미터) → 캔버스 좌표(픽셀)
  Offset _toCanvas(double xM, double yM, Size size) {
    final x = (xM / _laneWidth) * size.width;
    // y축 반전: yM=0(파울라인) → 하단, yM=18.29(핀덱) → 상단
    final y = (1.0 - yM / _laneLength) * size.height;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawLaneOutline(canvas, size);
    _drawPinDeck(canvas, size);
    _drawTrajectory(canvas, size);
    _drawMarkers(canvas, size);
  }

  /// 레인 외곽선 그리기
  void _drawLaneOutline(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, paint);

    // 파울 라인 (하단)
    final foulLinePaint = Paint()
      ..color = Colors.white38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      foulLinePaint,
    );
  }

  /// 핀 덱 10개 핀을 삼각형 배열로 표시 (장식용)
  ///
  /// 표준 4열 삼각형:
  ///   1열(앞): 7번핀
  ///   2열: 4,8번
  ///   3열: 2,5,9번
  ///   4열(뒤): 1,3,6,10번
  /// x 위치는 레인 중앙(0.525m) 기준으로 대칭 배치
  void _drawPinDeck(Canvas canvas, Size size) {
    final pinPaint = Paint()
      ..color = Colors.white38
      ..style = PaintingStyle.fill;

    // 핀 위치 (xM, yM) — 장식용 근사값
    final pins = <LanePoint>[
      // 1열 (핀 7): 가장 앞 (가장 높은 yM)
      LanePoint(xM: 0.525, yM: _pinDeckY + _pinSpacing * 1.5),
      // 2열 (핀 4, 8)
      LanePoint(xM: 0.525 - _pinSpacing * 0.5, yM: _pinDeckY + _pinSpacing),
      LanePoint(xM: 0.525 + _pinSpacing * 0.5, yM: _pinDeckY + _pinSpacing),
      // 3열 (핀 2, 5, 9)
      LanePoint(xM: 0.525 - _pinSpacing, yM: _pinDeckY + _pinSpacing * 0.5),
      LanePoint(xM: 0.525, yM: _pinDeckY + _pinSpacing * 0.5),
      LanePoint(xM: 0.525 + _pinSpacing, yM: _pinDeckY + _pinSpacing * 0.5),
      // 4열 (핀 1, 3, 6, 10)
      LanePoint(xM: 0.525 - _pinSpacing * 1.5, yM: _pinDeckY),
      LanePoint(xM: 0.525 - _pinSpacing * 0.5, yM: _pinDeckY),
      LanePoint(xM: 0.525 + _pinSpacing * 0.5, yM: _pinDeckY),
      LanePoint(xM: 0.525 + _pinSpacing * 1.5, yM: _pinDeckY),
    ];

    for (final pin in pins) {
      // yM이 레인 범위 밖이면 클램프
      final clampedY = pin.yM.clamp(0.0, _laneLength);
      final offset = _toCanvas(pin.xM, clampedY, size);
      canvas.drawCircle(offset, _pinRadius, pinPaint);
    }
  }

  /// 트래젝토리 폴리라인 그리기
  void _drawTrajectory(Canvas canvas, Size size) {
    if (trajectory.length < 2) return;

    final paint = Paint()
      ..color = AppColors.neonOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final first = _toCanvas(trajectory.first.xM, trajectory.first.yM, size);
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < trajectory.length; i++) {
      final pt = _toCanvas(trajectory[i].xM, trajectory[i].yM, size);
      path.lineTo(pt.dx, pt.dy);
    }

    canvas.drawPath(path, paint);
  }

  /// 릴리즈/브레이크 마커 그리기
  void _drawMarkers(Canvas canvas, Size size) {
    // 릴리즈 마커: neonOrange 채움 원
    final effectiveRelease = releasePos ??
        (trajectory.isNotEmpty ? trajectory.first : null);

    if (effectiveRelease != null) {
      final releasePaint = Paint()
        ..color = AppColors.neonOrange
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final offset = _toCanvas(effectiveRelease.xM, effectiveRelease.yM, size);
      canvas.drawCircle(offset, _markerRadius, releasePaint);
      canvas.drawCircle(offset, _markerRadius, borderPaint);
    }

    // 브레이크 마커: 시안 채움 원
    if (breakPos != null) {
      final breakPaint = Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final offset = _toCanvas(breakPos!.xM, breakPos!.yM, size);
      canvas.drawCircle(offset, _markerRadius, breakPaint);
      canvas.drawCircle(offset, _markerRadius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(_TrajectoryPainter old) =>
      old.trajectory != trajectory ||
      old.breakPos != breakPos ||
      old.releasePos != releasePos;
}
