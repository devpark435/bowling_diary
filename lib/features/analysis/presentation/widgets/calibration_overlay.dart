import 'package:flutter/material.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

/// [BoxFit.contain]으로 렌더링된 이미지가 [containerSize] 안에서 실제로 차지하는
/// 사각형을 계산한다. 레터박스(여백) 영역을 제외한 이미지 고유 영역만 반환한다.
///
/// 순수 함수 — 위젯 트리 없이 단위 테스트 가능.
Rect computeContainRect(Size containerSize, Size imageSize) {
  if (imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      containerSize.width <= 0 ||
      containerSize.height <= 0) {
    return Offset.zero & containerSize;
  }

  final containerAspect = containerSize.width / containerSize.height;
  final imageAspect = imageSize.width / imageSize.height;

  double width;
  double height;
  if (imageAspect > containerAspect) {
    // 이미지가 컨테이너보다 상대적으로 넓다 → 상/하 레터박스
    width = containerSize.width;
    height = width / imageAspect;
  } else {
    // 이미지가 컨테이너보다 상대적으로 좁다 → 좌/우 레터박스
    height = containerSize.height;
    width = height * imageAspect;
  }

  final left = (containerSize.width - width) / 2;
  final top = (containerSize.height - height) / 2;
  return Rect.fromLTWH(left, top, width, height);
}

class CalibrationOverlay extends StatelessWidget {
  final List<FramePoint> points;
  final ValueChanged<FramePoint> onTap;

  /// 참조 이미지의 고유(intrinsic) 픽셀 크기. [BoxFit.contain] 렌더링 영역을
  /// 계산하기 위해 필요하다.
  final Size imageSize;

  const CalibrationOverlay({
    super.key,
    required this.points,
    required this.onTap,
    required this.imageSize,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = constraints.biggest;
        final imageRect = computeContainRect(containerSize, imageSize);

        return GestureDetector(
          onTapUp: (details) {
            if (points.length >= 4) return;
            final pos = details.localPosition;
            // 레터박스(이미지 밖) 영역의 탭은 무시한다.
            if (!imageRect.contains(pos)) return;

            final nx = ((pos.dx - imageRect.left) / imageRect.width)
                .clamp(0.0, 1.0);
            final ny = ((pos.dy - imageRect.top) / imageRect.height)
                .clamp(0.0, 1.0);
            onTap(FramePoint(nx: nx, ny: ny));
          },
          child: CustomPaint(
            size: containerSize,
            painter: _MarkerPainter(points, imageRect),
          ),
        );
      },
    );
  }
}

class _MarkerPainter extends CustomPainter {
  final List<FramePoint> points;
  final Rect imageRect;
  _MarkerPainter(this.points, this.imageRect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.fill;
    for (var i = 0; i < points.length; i++) {
      // 이미지-상대 정규화 좌표를 화면 좌표로 역변환한다.
      final offset = Offset(
        imageRect.left + points[i].nx * imageRect.width,
        imageRect.top + points[i].ny * imageRect.height,
      );
      canvas.drawCircle(offset, 12, paint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
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

  @override
  bool shouldRepaint(covariant _MarkerPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.imageRect != imageRect;
}
