import 'package:flutter/material.dart';

import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/services/lane_guide_line_calculator.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/lane_corner_overlay.dart' show computeContainRect;

/// 레인 4코너 보정 중 현재 4점으로 실시간 호모그래피를 산출해, 실제 레인
/// 마킹(에로우/레인지파인더/파울라인/핀덱)이 화면 어디에 와야 하는지
/// 안내선으로 투영하는 오버레이.
///
/// [LaneCornerOverlay]보다 아래 레이어에 그려야 코너 드래그 핸들과 외곽선을
/// 가리지 않는다 — [Stack]에서 이 위젯을 먼저(더 아래) 배치할 것.
class LaneVerificationGridOverlay extends StatelessWidget {
  final List<FramePoint> points;

  /// 렌더링 중인 프레임 이미지의 고유(intrinsic) 픽셀 크기. [LaneCornerOverlay]와
  /// 동일한 [BoxFit.contain] 렌더링 영역 계산에 쓰인다.
  final Size imageSize;

  const LaneVerificationGridOverlay({
    super.key,
    required this.points,
    required this.imageSize,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = constraints.biggest;
        final imageRect = computeContainRect(containerSize, imageSize);
        return IgnorePointer(
          child: CustomPaint(
            size: containerSize,
            painter: _LaneGuideGridPainter(points, imageRect),
          ),
        );
      },
    );
  }
}

class _LaneGuideGridPainter extends CustomPainter {
  final List<FramePoint> points;
  final Rect imageRect;
  _LaneGuideGridPainter(this.points, this.imageRect);

  Offset _toScreen(FramePoint p) => Offset(
        imageRect.left + p.nx * imageRect.width,
        imageRect.top + p.ny * imageRect.height,
      );

  @override
  void paint(Canvas canvas, Size size) {
    // 퇴화 사각형(드래그 중 교차 등)이면 호모그래피를 풀 수 없다 — 그리드를
    // 조용히 생략한다. computeLaneGuideLines 내부에서 이미 try/catch로
    // ArgumentError를 흡수하므로 여기서는 null 체크만 하면 된다.
    final lines = computeLaneGuideLines(points);
    if (lines == null) return;

    final linePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final line in lines) {
      final left = _toScreen(line.left);
      final right = _toScreen(line.right);
      if (line.drawLine) {
        canvas.drawLine(left, right, linePaint);
      }
      _drawLabel(canvas, line.label, left);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset anchor) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const paddingH = 4.0;
    const paddingV = 2.0;
    final bgRect = Rect.fromLTWH(
      anchor.dx,
      anchor.dy - textPainter.height - paddingV * 2,
      textPainter.width + paddingH * 2,
      textPainter.height + paddingV * 2,
    );
    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(3)), bgPaint);
    textPainter.paint(canvas, Offset(bgRect.left + paddingH, bgRect.top + paddingV));
  }

  @override
  bool shouldRepaint(covariant _LaneGuideGridPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.imageRect != imageRect;
}
