import 'package:flutter/material.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';

class CameraGuideOverlay extends StatelessWidget {
  final bool isRecording;

  const CameraGuideOverlay({super.key, required this.isRecording});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _LaneGuidePainter()),
        ),
        if (!isRecording)
          Positioned(
            top: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '레인이 화면 안에 들어오도록 맞춰주세요',
                  style:
                      AppTextStyles.bodySmall.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
        if (isRecording)
          Positioned(
            top: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fiber_manual_record,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text('녹화 중',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LaneGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.neonOrange.withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
        Offset(size.width * 0.2, 0), Offset(size.width * 0.2, size.height), paint);
    canvas.drawLine(
        Offset(size.width * 0.8, 0), Offset(size.width * 0.8, size.height), paint);
  }

  @override
  bool shouldRepaint(_LaneGuidePainter _) => false;
}
