import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/balls/domain/entities/ball_entity.dart';
import 'package:bowling_diary/features/balls/presentation/providers/ball_provider.dart';
import 'package:bowling_diary/shared/providers/theme_provider.dart';
import 'package:bowling_diary/shared/widgets/loading_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';

class BallsPage extends ConsumerWidget {
  const BallsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(colorThemeProvider);
    final asyncBalls = ref.watch(ballsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 볼'),
      ),
      body: asyncBalls.when(
        data: (balls) {
          if (balls.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIconsFill.bowlingBall, size: 80, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text('등록된 볼이 없어요', style: AppTextStyles.headingSmall.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Text('우측 하단 + 버튼으로 볼을 추가하세요', style: AppTextStyles.bodySmall),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: balls.length,
            itemBuilder: (context, index) => _BallCard(ball: balls[index]),
          );
        },
        loading: () => const LoadingWidget(),
        error: (e, st) {
          debugPrint('볼 목록 로드 에러: $e\n$st');
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'balls_fab',
        onPressed: () => context.push('/ball/add'),
        child: const Icon(PhosphorIconsBold.plus),
      ),
    );
  }
}

class _BallCard extends StatelessWidget {
  final BallEntity ball;

  const _BallCard({required this.ball});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/ball/edit/${ball.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ball.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: ball.imageUrl!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: AppColors.darkDivider,
                          child: Icon(PhosphorIconsFill.bowlingBall, color: AppColors.textHint),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.darkDivider,
                          child: Icon(PhosphorIconsRegular.imageBroken, color: AppColors.textHint),
                        ),
                      )
                    : Container(
                        width: 72,
                        height: 72,
                        color: AppColors.darkDivider,
                        child: Icon(PhosphorIconsFill.bowlingBall, color: AppColors.textHint, size: 36),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ball.name, style: AppTextStyles.labelLarge),
                    if (ball.brand != null && ball.brand!.isNotEmpty)
                      Text(ball.brand!, style: AppTextStyles.bodySmall),
                    if (ball.weight != null)
                      Text('${ball.weight} lb', style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              Icon(PhosphorIconsRegular.caretRight, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}
