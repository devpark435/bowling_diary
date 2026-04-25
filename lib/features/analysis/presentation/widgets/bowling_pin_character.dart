import 'package:flutter/material.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';

class BowlingPinCharacter extends StatelessWidget {
  final String emotion; // 'normal' | 'happy' | 'cheer'

  const BowlingPinCharacter({super.key, this.emotion = 'normal'});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(100, 140),
      painter: _PinPainter(emotion: emotion),
    );
  }
}

class _PinPainter extends CustomPainter {
  final String emotion;
  _PinPainter({required this.emotion});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final orangePaint = Paint()..color = AppColors.neonOrange;
    final blackPaint = Paint()..color = Colors.black87;

    final cx = size.width / 2;

    // 몸통
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, size.height * 0.65),
            width: size.width * 0.7,
            height: size.height * 0.6),
        paint);
    // 목
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(cx, size.height * 0.3),
            width: size.width * 0.25,
            height: size.height * 0.15),
        paint);
    // 머리
    canvas.drawCircle(Offset(cx, size.height * 0.18), size.width * 0.22, paint);

    // 오렌지 줄무늬
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(cx, size.height * 0.55),
            width: size.width * 0.7,
            height: size.height * 0.06),
        orangePaint);

    // 눈
    final eyeY = size.height * 0.16;
    canvas.drawCircle(Offset(cx - 7, eyeY), 3.5, blackPaint);
    canvas.drawCircle(Offset(cx + 7, eyeY), 3.5, blackPaint);

    // 감정별 입 모양
    final mouthPaint = Paint()
      ..color = blackPaint.color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final mouthY = size.height * 0.22;
    if (emotion == 'happy' || emotion == 'cheer') {
      final path = Path()
        ..moveTo(cx - 7, mouthY)
        ..quadraticBezierTo(cx, mouthY + 8, cx + 7, mouthY);
      canvas.drawPath(path, mouthPaint);
    } else {
      canvas.drawLine(
          Offset(cx - 6, mouthY + 2), Offset(cx + 6, mouthY + 2), mouthPaint);
    }

    // cheer: 팔 올리기
    if (emotion == 'cheer') {
      final armPaint = Paint()
        ..color = blackPaint.color
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(cx - size.width * 0.35, size.height * 0.5),
          Offset(cx - size.width * 0.5, size.height * 0.3), armPaint);
      canvas.drawLine(Offset(cx + size.width * 0.35, size.height * 0.5),
          Offset(cx + size.width * 0.5, size.height * 0.3), armPaint);
    }
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.emotion != emotion;
}
