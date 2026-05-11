import 'package:flutter/material.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

/// 레인 캘리브레이션 오버레이 위젯
///
/// 사용자 탭 시 정규화 좌표(0~1)를 [onTap] 콜백으로 전달한다.
/// 4개의 점이 모두 입력되면 다각형을 닫아 영역을 표시한다.
class CalibrationOverlay extends StatelessWidget {
  /// 현재 입력된 프레임 정규화 좌표 목록
  final List<FramePoint> points;

  /// 탭 시 정규화 좌표를 전달하는 콜백
  final void Function(FramePoint) onTap;

  const CalibrationOverlay({
    super.key,
    required this.points,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(details.globalPosition);
        final size = box.size;
        final nx = (local.dx / size.width).clamp(0.0, 1.0);
        final ny = (local.dy / size.height).clamp(0.0, 1.0);
        onTap(FramePoint(nx: nx, ny: ny));
      },
      child: CustomPaint(
        painter: _CalibrationPainter(points: points),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _CalibrationPainter extends CustomPainter {
  final List<FramePoint> points;

  const _CalibrationPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final linePaint = Paint()
      ..color = Colors.amber
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.fill;

    // 연결선 그리기
    if (points.length >= 2) {
      final path = Path();
      final first = _toOffset(points.first, size);
      path.moveTo(first.dx, first.dy);

      for (var i = 1; i < points.length; i++) {
        final pt = _toOffset(points[i], size);
        path.lineTo(pt.dx, pt.dy);
      }

      // 4점이 입력되면 다각형 닫기
      if (points.length == 4) {
        path.close();
      }

      canvas.drawPath(path, linePaint);
    }

    // 점 그리기
    for (var i = 0; i < points.length; i++) {
      final offset = _toOffset(points[i], size);
      canvas.drawCircle(offset, 8.0, dotPaint);

      // 점 번호 텍스트
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        offset - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  Offset _toOffset(FramePoint p, Size size) {
    return Offset(p.nx * size.width, p.ny * size.height);
  }

  @override
  bool shouldRepaint(_CalibrationPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
