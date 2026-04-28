import 'package:flutter/material.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';

class LoadingWidget extends StatefulWidget {
  const LoadingWidget({super.key});

  @override
  State<LoadingWidget> createState() => _LoadingWidgetState();
}

class _LoadingWidgetState extends State<LoadingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _dotCount = 3;
  static const _dotSize = 8.0;
  static const _bounceHeight = 10.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        height: _dotSize + _bounceHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_dotCount, (i) {
            // 각 점마다 1/3 주기만큼 stagger
            final start = i / _dotCount;
            final end = start + 1 / _dotCount;

            final bounce = TweenSequence<double>([
              TweenSequenceItem(
                tween: Tween(begin: 0.0, end: 1.0)
                    .chain(CurveTween(curve: Curves.easeOut)),
                weight: 50,
              ),
              TweenSequenceItem(
                tween: Tween(begin: 1.0, end: 0.0)
                    .chain(CurveTween(curve: Curves.easeIn)),
                weight: 50,
              ),
            ]).animate(
              CurvedAnimation(
                parent: _controller,
                curve: Interval(start, end < 1.0 ? end : 1.0),
              ),
            );

            return Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? 0 : 6,
              ),
              child: AnimatedBuilder(
                animation: bounce,
                builder: (_, __) => Transform.translate(
                  offset: Offset(0, -_bounceHeight * bounce.value),
                  child: Container(
                    width: _dotSize,
                    height: _dotSize,
                    decoration: BoxDecoration(
                      color: AppColors.neonOrange
                          .withValues(alpha: 0.4 + 0.6 * bounce.value),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class LoadingOverlay extends StatelessWidget {
  final Widget child;
  final bool isLoading;

  const LoadingOverlay({
    super.key,
    required this.child,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.5),
            child: const LoadingWidget(),
          ),
      ],
    );
  }
}
