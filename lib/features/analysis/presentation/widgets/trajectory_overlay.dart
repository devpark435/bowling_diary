import 'package:flutter/material.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';

/// [BoxFit.cover]로 렌더링된 영상이 [containerSize] 안에서 실제로 차지하는
/// 사각형을 계산한다. 컨테이너를 레터박스 없이 꽉 채우도록 확대하며, 넘치는
/// 부분은 컨테이너 경계 밖으로 나간다(음수 left/top 또는 컨테이너보다 큰
/// width/height로 표현됨). CustomPaint는 기본적으로 클리핑하지 않는다 — 이
/// 위젯에서 화면 밖으로 나가는 게 문제되지 않는 건 컨테이너 밖 좌표가 실제로도
/// 화면 밖(잘려나간 영상 영역)에 해당해서 우연히 안전한 것이지, 별도 클리핑
/// 보장이 있는 게 아니다. 명시적 보장이 필요해지면 ClipRect로 감쌀 것.
///
/// [lane_corner_overlay.dart]의 computeContainRect와 형태는 같지만 스케일
/// 계산이 반대(compare: min → contain, max → cover)다. 그 함수는 여전히
/// BoxFit.contain을 쓰는 화면(레인 확인 화면)에서 쓰이므로 건드리지 않는다.
///
/// 순수 함수 — 위젯 트리 없이 단위 테스트 가능.
Rect computeCoverRect(Size containerSize, Size imageSize) {
  if (imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      containerSize.width <= 0 ||
      containerSize.height <= 0) {
    return Offset.zero & containerSize;
  }

  final scale = (containerSize.width / imageSize.width) >
          (containerSize.height / imageSize.height)
      ? containerSize.width / imageSize.width
      : containerSize.height / imageSize.height;

  final width = imageSize.width * scale;
  final height = imageSize.height * scale;
  final left = (containerSize.width - width) / 2;
  final top = (containerSize.height - height) / 2;
  return Rect.fromLTWH(left, top, width, height);
}

/// 볼 궤적을 [BoxFit.cover]로 렌더링 중인 영상 위에 폴리라인으로 그리는
/// 비인터랙티브 오버레이. 드래그/탭 처리 없음 — 순수 표시용(spec §11).
///
/// [points]는 이미 프레임 정규화좌표(FramePoint)로 변환되어 있다고 가정한다
/// (AnalysisPipeline이 homography.laneToFrame()을 미리 적용함). 2개 미만이면
/// 그릴 선이 없으므로 아무것도 렌더링하지 않는다.
class TrajectoryOverlay extends StatelessWidget {
  final List<FramePoint> points;

  /// 렌더링 중인 영상의 고유(intrinsic) 픽셀 크기. BoxFit.cover 렌더링 영역을
  /// 계산하기 위해 필요하다(VideoPlayerController.value.size).
  final Size videoSize;

  const TrajectoryOverlay({
    super.key,
    required this.points,
    required this.videoSize,
  });

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = constraints.biggest;
        final videoRect = computeCoverRect(containerSize, videoSize);
        return CustomPaint(
          size: containerSize,
          painter: _TrajectoryPainter(points, videoRect),
        );
      },
    );
  }
}

class _TrajectoryPainter extends CustomPainter {
  final List<FramePoint> points;
  final Rect videoRect;
  _TrajectoryPainter(this.points, this.videoRect);

  Offset _offsetFor(int index) {
    final p = points[index];
    return Offset(
      videoRect.left + p.nx * videoRect.width,
      videoRect.top + p.ny * videoRect.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(_offsetFor(0).dx, _offsetFor(0).dy);
    for (var i = 1; i < points.length; i++) {
      final o = _offsetFor(i);
      path.lineTo(o.dx, o.dy);
    }

    final strokePaint = Paint()
      ..color = AppColors.neonOrange.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.videoRect != videoRect;
}
