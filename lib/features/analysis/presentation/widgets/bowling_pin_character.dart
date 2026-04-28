import 'package:flutter/material.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';

class BowlingPinCharacter extends StatelessWidget {
  final String emotion; // 'normal' | 'happy' | 'cheer'

  const BowlingPinCharacter({super.key, this.emotion = 'normal'});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(100, 140),
      painter: _PinPainter(),
    );
  }
}

class _PinPainter extends CustomPainter {

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final orangePaint = Paint()..color = AppColors.neonOrange;

    final cx = size.width / 2;

    final bodyRect = Rect.fromCenter(
      center: Offset(cx, size.height * 0.65),
      width: size.width * 0.72,
      height: size.height * 0.62,
    );

    // 몸통
    canvas.drawOval(bodyRect, paint);

    // 오렌지 줄무늬 (몸통 안에만)
    canvas.save();
    final bodyPath = Path()..addOval(bodyRect);
    canvas.clipPath(bodyPath);
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(cx, size.height * 0.54),
            width: size.width * 0.72,
            height: size.height * 0.055),
        orangePaint);
    canvas.restore();

    // 머리 (목 없이 몸통과 오버랩)
    canvas.drawCircle(
        Offset(cx, size.height * 0.22), size.width * 0.24, paint);
  }

  @override
  bool shouldRepaint(_PinPainter old) => false;
}
