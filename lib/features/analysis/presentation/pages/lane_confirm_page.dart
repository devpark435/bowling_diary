import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/analysis/domain/entities/coord.dart';
import 'package:bowling_diary/features/analysis/domain/entities/lane_detection_result.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/lane_corner_overlay.dart';
import 'package:bowling_diary/features/analysis/presentation/widgets/lane_verification_grid_overlay.dart';

/// 영상 첫 프레임에서 자동검출된 레인 4코너를 사용자가 확인/보정하는 화면.
///
/// spec §10 원칙: 자동검출 결과를 확인 없이 그대로 쓰지 않는다 — 등급이
/// good이어도 이 화면은 항상 노출되고, 사용자가 확정해야 다음 단계로 넘어간다.
class LaneConfirmPage extends StatefulWidget {
  final String framePath;
  final LaneDetectionResult detection;

  const LaneConfirmPage({
    super.key,
    required this.framePath,
    required this.detection,
  });

  @override
  State<LaneConfirmPage> createState() => _LaneConfirmPageState();
}

class _LaneConfirmPageState extends State<LaneConfirmPage> {
  late List<FramePoint> _points;
  Size? _imageSize;
  bool _imageLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _points = List.of(widget.detection.corners);
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    try {
      final bytes = await File(widget.framePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (!mounted) return;
      if (decoded == null) {
        setState(() => _imageLoadFailed = true);
        return;
      }
      setState(() {
        _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _imageLoadFailed = true);
    }
  }

  /// 세 가지 정보를 반드시 포함한다: ①가까운 두 점=파울라인, 먼 두 점=구석
  /// 핀(7번·10번)의 머리 높이 ②안내선(에로우·레인지파인더)이 실제 레인
  /// 마킹과 겹치면 정확히 맞은 것이라는 활용법.
  ///
  /// 먼 두 점을 "핀 발밑(바닥)" 기준으로 잡으면 광각 렌즈의 중·원거리
  /// 압축 때문에 구속이 과대 산출됐다(실측: 37.8 → 발밑 기준). 구석 핀
  /// 머리 높이까지 올려서 잡으면 현실값(28.7)에 근접해, 이 경험칙으로
  /// 문구를 바꿨다.
  static const _guideText = '가까운 두 점은 파울라인 양끝, 먼 두 점은 구석 핀(7번·10번)의 머리 높이에 '
      '맞춰 주세요. 핀 발밑이 아니라 머리 높이 기준입니다. 안내선(에로우·레인지파인더)이 실제 레인 '
      '마킹과 겹치면 정확히 맞은 거예요.';

  String get _bannerText {
    switch (widget.detection.quality) {
      case LaneDetectionQuality.good:
        return '레인을 자동으로 인식했어요. 위치가 맞는지 확인해 주세요.\n$_guideText';
      case LaneDetectionQuality.rough:
      case LaneDetectionQuality.notFound:
        return '점을 드래그해서 레인 네 모서리에 맞춰 주세요.\n$_guideText';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkCard,
        title: Text('레인 위치 확인', style: AppTextStyles.headingSmall.copyWith(color: AppColors.textPrimary)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.darkCard,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              _bannerText,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.neonOrange),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: _imageLoadFailed
                ? Center(
                    child: Text(
                      '이미지를 불러올 수 없습니다',
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                    ),
                  )
                : _imageSize == null
                    ? const Center(child: CircularProgressIndicator())
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(widget.framePath), fit: BoxFit.contain),
                          LaneVerificationGridOverlay(
                            points: _points,
                            imageSize: _imageSize!,
                          ),
                          LaneCornerOverlay(
                            points: _points,
                            imageSize: _imageSize!,
                            onChanged: (updated) => setState(() => _points = updated),
                          ),
                        ],
                      ),
          ),
          Container(
            color: AppColors.darkCard,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_points),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonOrange,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  '이 위치로 분석하기',
                  style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
