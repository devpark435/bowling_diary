import 'package:flutter/material.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
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

/// 레인 4코너(자동검출 또는 기본값)를 이미지 위에 레인 영역(사변형)으로 표시하고,
/// 드래그로 보정할 수 있게 하는 오버레이.
///
/// [points]는 항상 정확히 4개가 존재한다는 전제로 동작한다 — 이 위젯은 점을
/// 추가/삭제하지 않고, 기존 점을 드래그로 옮기는 것만 지원한다(자동검출
/// 결과의 확인/보정 용도).
class LaneCornerOverlay extends StatefulWidget {
  final List<FramePoint> points;
  final ValueChanged<List<FramePoint>> onChanged;

  /// 렌더링 중인 프레임 이미지의 고유(intrinsic) 픽셀 크기. [BoxFit.contain]
  /// 렌더링 영역을 계산하기 위해 필요하다.
  final Size imageSize;

  const LaneCornerOverlay({
    super.key,
    required this.points,
    required this.onChanged,
    required this.imageSize,
  });

  @override
  State<LaneCornerOverlay> createState() => _LaneCornerOverlayState();
}

class _LaneCornerOverlayState extends State<LaneCornerOverlay> {
  /// 드래그 시작점 판정 반경(논리 픽셀). 이 범위 밖에서 시작된 드래그는 무시한다
  /// (레터박스 영역 등에서 실수로 시작된 제스처가 아무 점도 옮기지 않게 함).
  static const double _hitRadiusPx = 32.0;

  int? _draggingIndex;

  Offset _pointOffset(Rect imageRect, int index) {
    final p = widget.points[index];
    return Offset(
      imageRect.left + p.nx * imageRect.width,
      imageRect.top + p.ny * imageRect.height,
    );
  }

  FramePoint _clampToRect(Rect imageRect, Offset local) {
    final nx = ((local.dx - imageRect.left) / imageRect.width).clamp(0.0, 1.0);
    final ny = ((local.dy - imageRect.top) / imageRect.height).clamp(0.0, 1.0);
    return FramePoint(nx: nx, ny: ny);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = constraints.biggest;
        final imageRect = computeContainRect(containerSize, widget.imageSize);

        return GestureDetector(
          onPanStart: (details) {
            final pos = details.localPosition;
            int? nearestIndex;
            var nearestDist = double.infinity;
            for (var i = 0; i < widget.points.length; i++) {
              final dist = (_pointOffset(imageRect, i) - pos).distance;
              if (dist < nearestDist) {
                nearestDist = dist;
                nearestIndex = i;
              }
            }
            _draggingIndex = (nearestIndex != null && nearestDist <= _hitRadiusPx) ? nearestIndex : null;
          },
          onPanUpdate: (details) {
            final idx = _draggingIndex;
            if (idx == null) return;
            final updated = List<FramePoint>.of(widget.points);
            updated[idx] = _clampToRect(imageRect, details.localPosition);
            widget.onChanged(updated);
          },
          onPanEnd: (_) => _draggingIndex = null,
          onPanCancel: () => _draggingIndex = null,
          child: CustomPaint(
            size: containerSize,
            painter: _LaneRegionPainter(widget.points, imageRect),
          ),
        );
      },
    );
  }
}

/// 레인 4코너를 이어 반투명 사변형(영역)으로 그리고, 각 꼭짓점에 드래그용
/// 핸들 원을 그리는 페인터. 점(들)이 아니라 레인 영역 자체가 시각적으로
/// 읽히도록 하는 것이 목적 — 번호 라벨은 없다(외곽선 자체로 파울/핀 코너
/// 구분이 명확함).
class _LaneRegionPainter extends CustomPainter {
  final List<FramePoint> points;
  final Rect imageRect;
  _LaneRegionPainter(this.points, this.imageRect);

  /// 이미지-상대 정규화 좌표를 화면 좌표로 역변환한다.
  Offset _offsetFor(int index) {
    final p = points[index];
    return Offset(
      imageRect.left + p.nx * imageRect.width,
      imageRect.top + p.ny * imageRect.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final regionColor = AppColors.neonOrange;
    final path = Path()..moveTo(_offsetFor(0).dx, _offsetFor(0).dy);
    for (var i = 1; i < points.length; i++) {
      final offset = _offsetFor(i);
      path.lineTo(offset.dx, offset.dy);
    }
    path.close();

    final fillPaint = Paint()
      ..color = regionColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = regionColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    final handlePaint = Paint()
      ..color = regionColor
      ..style = PaintingStyle.fill;
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(_offsetFor(i), 10, handlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LaneRegionPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.imageRect != imageRect;
}
