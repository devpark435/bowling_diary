import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';
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

/// 재생 위치 → 분석 프레임 인덱스 (내림).
int frameForPosition(Duration position, int fps) =>
    (position.inMicroseconds * fps) ~/ Duration.microsecondsPerSecond;

/// frame 오름차순 정렬된 points에서 frame <= currentFrame 인 선두 구간 길이.
int visiblePointCount(List<TrajectoryRibbonPoint> points, int currentFrame) {
  var count = 0;
  for (final p in points) {
    if (p.frame > currentFrame) break;
    count++;
  }
  return count;
}

/// 볼 궤적을 [BoxFit.cover]로 렌더링 중인 영상 위에 레인 평면 리본(폭이 있는
/// 폴리곤)으로 그리는 비인터랙티브 오버레이. 드래그/탭 처리 없음 — 순수
/// 표시용(spec §11). 균일 두께 중심선 대신 공 폭만큼 벌린 좌우 가장자리를
/// 잇는 리본을 그려, 원근(가까우면 넓고 멀면 좁음)이 반영된 "레인 위에 그려진"
/// 느낌을 준다.
///
/// 재생 위치에 동기화된 점진적 렌더링: 공이 실제로 지나간 지점까지만 리본이
/// 그려지고, 그 이후(아직 재생되지 않은) 구간은 보이지 않는다. 루프가
/// 재시작되면 position이 0으로 돌아가므로 리본도 자연히 리셋된다.
///
/// [VideoPlayerValue.position]은 내부 타이머로 ~500ms 간격으로만 갱신되는데,
/// 이 위젯이 목표로 하는 0.25x 재생에서는 500ms가 분석 프레임 기준 ~3.75프레임에
/// 해당해 그대로 쓰면 선이 뚝뚝 끊겨 늘어나 보인다. 그래서 매 vsync(Ticker)마다
/// 마지막으로 통지받은 position을 기준으로 경과 시간을 더해 현재 위치를
/// 보간 추정한다.
///
/// [points]는 이미 프레임 정규화좌표(FramePoint)로 변환되어 있고 frame 오름차순
/// 정렬되어 있다고 가정한다(AnalysisPipeline이 refineTrajectory + homography로
/// 미리 리본 좌표를 산출함). 현재 프레임까지 보이는 점이 2개 미만이면 그릴
/// 리본이 없으므로 아무것도 렌더링하지 않는다.
class TrajectoryOverlay extends StatefulWidget {
  final List<TrajectoryRibbonPoint> points;

  /// 렌더링 중인 영상의 고유(intrinsic) 픽셀 크기. BoxFit.cover 렌더링 영역을
  /// 계산하기 위해 필요하다(VideoPlayerController.value.size).
  final Size videoSize;

  /// 재생 위치 통지원. VideoPlayerController가 곧 `ValueNotifier<VideoPlayerValue>`라
  /// 그대로 넘길 수 있다. 위젯테스트에서는 `ValueNotifier<VideoPlayerValue>`를 직접
  /// 주입해 플랫폼 스텁 없이 구동할 수 있다.
  final ValueListenable<VideoPlayerValue> playback;

  /// 분석 프레임 추출 fps (AnalysisData.fpsUsed). frameForPosition 계산 기준.
  final int fps;

  const TrajectoryOverlay({
    super.key,
    required this.points,
    required this.videoSize,
    required this.playback,
    required this.fps,
  });

  @override
  State<TrajectoryOverlay> createState() => _TrajectoryOverlayState();
}

class _TrajectoryOverlayState extends State<TrajectoryOverlay>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  Duration _basePosition = Duration.zero;
  Duration _baseElapsed = Duration.zero;
  Duration _lastElapsed = Duration.zero;
  int _visibleCount = 0;

  /// 재생 위치→프레임 매핑 지연 진단용. 매 vsync(최대 초당 수십 회)마다 찍으면
  /// 로그가 너무 시끄러워지므로 마지막 출력 이후 경과(ticker elapsed, 실시간
  /// 기준)가 1초 이상일 때만 출력한다.
  Duration? _lastLogElapsed;

  @override
  void initState() {
    super.initState();
    widget.playback.addListener(_syncBaseline);
    _syncBaseline();
    _ticker = createTicker(_onTick)..start();
  }

  void _syncBaseline() {
    _basePosition = widget.playback.value.position;
    _baseElapsed = _lastElapsed;
  }

  void _onTick(Duration elapsed) {
    _lastElapsed = elapsed;
    final v = widget.playback.value;
    var estimated = v.isPlaying
        ? _basePosition + (elapsed - _baseElapsed) * v.playbackSpeed
        : _basePosition;
    if (v.duration > Duration.zero && estimated > v.duration) {
      estimated = v.duration;
    }
    if (estimated < Duration.zero) estimated = Duration.zero;

    final currentFrame = frameForPosition(estimated, widget.fps);
    final count = visiblePointCount(widget.points, currentFrame);
    if (count != _visibleCount) {
      setState(() => _visibleCount = count);
    }

    if (kDebugMode) {
      if (_lastLogElapsed == null ||
          elapsed - _lastLogElapsed! >= const Duration(seconds: 1)) {
        _lastLogElapsed = elapsed;
        debugPrint(
          '[Overlay] pos=${_formatSeconds(v.position)}s '
          'est=${_formatSeconds(estimated)}s '
          'playing=${v.isPlaying} speed=${v.playbackSpeed} '
          'frame=$currentFrame visible=$count/${widget.points.length}',
        );
      }
    }
  }

  String _formatSeconds(Duration d) =>
      (d.inMilliseconds / 1000).toStringAsFixed(2);

  @override
  void didUpdateWidget(covariant TrajectoryOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.playback, widget.playback)) {
      oldWidget.playback.removeListener(_syncBaseline);
      widget.playback.addListener(_syncBaseline);
      _syncBaseline();
    }
    if (!identical(oldWidget.points, widget.points)) {
      final v = widget.playback.value;
      final currentFrame = frameForPosition(v.position, widget.fps);
      _visibleCount = visiblePointCount(widget.points, currentFrame);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.playback.removeListener(_syncBaseline);
    // playback(ValueListenable/VideoPlayerController)은 부모 소유 — 여기서 dispose하지 않는다.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.points.sublist(
      0,
      _visibleCount.clamp(0, widget.points.length),
    );
    if (visible.length < 2) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = constraints.biggest;
        final videoRect = computeCoverRect(containerSize, widget.videoSize);
        return CustomPaint(
          size: containerSize,
          painter: _TrajectoryPainter(visible, videoRect),
        );
      },
    );
  }
}

/// 코멧(혜성) 스타일 페인터 — 골프 샷 트레이서류를 참조. 리본을 세그먼트별
/// 사각형(quad)으로 채우되 꼬리(오래된 구간)는 옅게, 머리(최신 구간)는
/// 진하게 불투명도를 램프시켜 진행 방향감을 준다. 인접 quad가 변을 공유해
/// 이음새가 보이지 않으므로 stroke는 그리지 않는다(seg 경계에 stroke를 그으면
/// 오히려 각짐이 도드라짐). 머리 끝에는 바깥 블러 글로우 + 안쪽 선명한 코어
/// 두 겹의 원을 그려 "빛나는 공 머리" 느낌을 더한다.
class _TrajectoryPainter extends CustomPainter {
  final List<TrajectoryRibbonPoint> points;
  final Rect videoRect;
  _TrajectoryPainter(this.points, this.videoRect);

  Offset _project(FramePoint p) => Offset(
        videoRect.left + p.nx * videoRect.width,
        videoRect.top + p.ny * videoRect.height,
      );

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final left = points.map((p) => _project(p.left)).toList();
    final right = points.map((p) => _project(p.right)).toList();
    final segCount = points.length - 1;

    final fillPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < segCount; i++) {
      final t = segCount > 1 ? i / (segCount - 1) : 1.0;
      final alpha = ui.lerpDouble(0.12, 0.6, t)!;
      final quad = Path()
        ..moveTo(left[i].dx, left[i].dy)
        ..lineTo(left[i + 1].dx, left[i + 1].dy)
        ..lineTo(right[i + 1].dx, right[i + 1].dy)
        ..lineTo(right[i].dx, right[i].dy)
        ..close();
      fillPaint.color = AppColors.neonOrange.withValues(alpha: alpha);
      canvas.drawPath(quad, fillPaint);
    }

    final head = (left.last + right.last) / 2;
    final headWidth = (right.last - left.last).distance;
    final outerRadius = math.max(4.0, headWidth * 0.7);
    final innerRadius = outerRadius * 0.55;

    final outerGlow = Paint()
      ..color = AppColors.neonOrange.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(head, outerRadius, outerGlow);

    final innerCore = Paint()..color = AppColors.neonOrange.withValues(alpha: 0.95);
    canvas.drawCircle(head, innerRadius, innerCore);
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter oldDelegate) =>
      oldDelegate.points.length != points.length ||
      oldDelegate.points != points ||
      oldDelegate.videoRect != videoRect;
}
