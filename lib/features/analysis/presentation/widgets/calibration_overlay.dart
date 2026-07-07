import 'package:flutter/material.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

class CalibrationOverlay extends StatelessWidget {
  final List<FramePoint> points;
  final ValueChanged<FramePoint> onTap;

  const CalibrationOverlay({super.key, required this.points, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapUp: (details) {
            if (points.length >= 4) return;
            final nx = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            final ny = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
            onTap(FramePoint(nx: nx, ny: ny));
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _MarkerPainter(points),
          ),
        );
      },
    );
  }
}

class _MarkerPainter extends CustomPainter {
  final List<FramePoint> points;
  _MarkerPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.fill;
    for (var i = 0; i < points.length; i++) {
      final offset = Offset(points[i].nx * size.width, points[i].ny * size.height);
      canvas.drawCircle(offset, 10, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter oldDelegate) => oldDelegate.points != points;
}
