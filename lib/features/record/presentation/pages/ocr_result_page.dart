import 'dart:io';

import 'package:flutter/material.dart';

import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/record/domain/entities/game_entity.dart';
import 'package:bowling_diary/features/record/domain/entities/ocr_result.dart';

/// OCR 인식 결과를 확인하고 적용하는 페이지
class OcrResultPage extends StatefulWidget {
  final OcrPlayerResult playerResult;
  final String imagePath;

  const OcrResultPage({
    super.key,
    required this.playerResult,
    required this.imagePath,
  });

  @override
  State<OcrResultPage> createState() => _OcrResultPageState();
}

class _OcrResultPageState extends State<OcrResultPage> {
  late List<OcrFrameResult> _frames;

  @override
  void initState() {
    super.initState();
    _frames = List.from(widget.playerResult.frames);
    // 10프레임까지 빈 프레임 채우기
    for (int i = 1; i <= 10; i++) {
      if (!_frames.any((f) => f.frameNumber == i)) {
        _frames.add(OcrFrameResult(
          frameNumber: i,
          confidence: OcrConfidence.unrecognized,
        ));
      }
    }
    _frames.sort((a, b) => a.frameNumber.compareTo(b.frameNumber));
  }

  int get _recognizedCount =>
      _frames.where((f) =>
        f.confidence != OcrConfidence.unrecognized &&
        (f.firstThrow != null || f.isSpare || f.isStrike)
      ).length;

  List<OcrFrameResult> get _correctedFrames =>
      _frames.where((f) => f.validationStatus == OcrValidationStatus.corrected).toList();

  int? get _estimatedTotal {
    final last = _frames.lastWhere(
      (f) => f.cumulativeScore != null,
      orElse: () => _frames.last,
    );
    return last.cumulativeScore;
  }

  void _applyTotalOnly() {
    final total = _estimatedTotal;
    if (total == null) return;
    Navigator.pop(context, OcrApplyResult.totalOnly(total));
  }

  void _applyFrameDetail() {
    final frameDataList = _frames
        .map((f) => f.toFrameData())
        .whereType<FrameData>()
        .toList();
    Navigator.pop(context, OcrApplyResult.frameDetail(frameDataList));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('인식 결과 확인'),
        actions: [
          TextButton(
            onPressed: _applyFrameDetail,
            child: Text(
              '프레임 적용',
              style: TextStyle(
                color: AppColors.neonOrange,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImagePreview(),
            const SizedBox(height: 20),
            _buildPlayerInfo(),
            const SizedBox(height: 16),
            _buildScoreBoard(),
            const SizedBox(height: 16),
            _buildStatusInfo(),
            const SizedBox(height: 24),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.file(
          File(widget.imagePath),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildPlayerInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.neonOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                widget.playerResult.playerName.isNotEmpty
                    ? widget.playerResult.playerName[0]
                    : '?',
                style: TextStyle(
                  color: AppColors.neonOrange,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.playerResult.playerName,
                  style: AppTextStyles.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  '$_recognizedCount/10 프레임 인식됨',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          if (_estimatedTotal != null)
            Text(
              '$_estimatedTotal점',
              style: AppTextStyles.scoreDisplay.copyWith(
                fontSize: 24,
                color: AppColors.neonOrange,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScoreBoard() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(10, (i) => _buildFrameCell(_frames[i])),
      ),
    );
  }

  Widget _buildFrameCell(OcrFrameResult frame) {
    final isTenth = frame.frameNumber == 10;
    final isRecognized = frame.firstThrow != null || frame.isSpare || frame.isStrike;

    Color borderColor;
    switch (frame.validationStatus) {
      case OcrValidationStatus.validated:
        borderColor = AppColors.success;
      case OcrValidationStatus.corrected:
        borderColor = AppColors.neonOrange;
      case OcrValidationStatus.unverified:
        borderColor = AppColors.textHint;
      case OcrValidationStatus.none:
        if (!isRecognized || frame.confidence == OcrConfidence.unrecognized) {
          borderColor = AppColors.textHint;
        } else if (frame.confidence == OcrConfidence.low) {
          borderColor = AppColors.neonOrange;
        } else {
          borderColor = AppColors.mint;
        }
    }

    return Container(
      width: isTenth ? 90 : 60,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        children: [
          // 프레임 번호
          Container(
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.darkDivider, width: 0.5),
              ),
            ),
            child: Center(
              child: Text(
                '${frame.frameNumber}',
                style: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // 투구 표시
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: isTenth
                  ? _buildTenthThrows(frame)
                  : _buildNormalThrows(frame),
            ),
          ),
          // 누적 점수
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.darkDivider, width: 0.5),
              ),
            ),
            child: Center(
              child: Text(
                frame.cumulativeScore?.toString() ?? '',
                style: AppTextStyles.scoreSmall.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNormalThrows(OcrFrameResult frame) {
    String first = '';
    String second = '';

    if (frame.isStrike || frame.firstThrow == 10) {
      // 스트라이크
      first = 'X';
    } else if (frame.isSpare) {
      // 스페어 확정: firstThrow가 있으면 표시, 없으면 '?'
      first = frame.firstThrow != null ? '${frame.firstThrow}' : '?';
      second = '/';
    } else if (frame.firstThrow != null) {
      // 일반 오픈 또는 미완성 프레임
      first = '${frame.firstThrow}';
      if (frame.secondThrow != null) {
        if ((frame.firstThrow! + frame.secondThrow!) == 10) {
          second = '/';
        } else {
          second = '${frame.secondThrow}';
        }
      }
    }

    return [
      _throwBox(first, first == 'X'),
      const SizedBox(width: 2),
      _throwBox(second, second == '/'),
    ];
  }

  List<Widget> _buildTenthThrows(OcrFrameResult frame) {
    String first = '', second = '', third = '';

    if (frame.firstThrow != null) {
      first = frame.firstThrow == 10 ? 'X' : '${frame.firstThrow}';
    }
    if (frame.secondThrow != null) {
      if (frame.firstThrow == 10 && frame.secondThrow == 10) {
        second = 'X';
      } else if (frame.firstThrow != 10 &&
          frame.firstThrow != null &&
          (frame.firstThrow! + frame.secondThrow!) == 10) {
        second = '/';
      } else {
        second = '${frame.secondThrow}';
      }
    }
    if (frame.thirdThrow != null) {
      if (frame.thirdThrow == 10) {
        third = 'X';
      } else {
        third = '${frame.thirdThrow}';
      }
    }

    return [
      _throwBox(first, first == 'X'),
      const SizedBox(width: 2),
      _throwBox(second, second == 'X' || second == '/'),
      const SizedBox(width: 2),
      _throwBox(third, third == 'X'),
    ];
  }

  Widget _throwBox(String text, bool isHighlight) {
    Color color = AppColors.textPrimary;
    if (text == 'X') color = AppColors.neonOrange;
    if (text == '/') color = AppColors.mint;

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: isHighlight ? color.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: text.isEmpty ? AppColors.textHint : color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildStatusInfo() {
    final unrecognized = _frames
        .where((f) =>
            f.confidence == OcrConfidence.unrecognized ||
            (!f.isSpare && !f.isStrike && f.firstThrow == null))
        .toList();
    final lowConfidence =
        _frames.where((f) => f.confidence == OcrConfidence.low).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 범례
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _legendDot(AppColors.success, '검증 통과'),
            _legendDot(AppColors.mint, '인식 완료'),
            _legendDot(AppColors.neonOrange, '보정됨'),
            _legendDot(AppColors.textHint, '미인식'),
          ],
        ),
        if (unrecognized.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.mint.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.mint.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.mint, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${unrecognized.map((f) => '${f.frameNumber}프레임').join(', ')}은 인식되지 않았습니다.\n적용 후 직접 입력해주세요.',
                    style: TextStyle(
                      color: AppColors.mint,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_correctedFrames.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.neonOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.neonOrange.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_fix_high_rounded,
                    color: AppColors.neonOrange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_correctedFrames.map((f) => '${f.frameNumber}프레임').join(', ')}이 누적 점수 기반으로 보정되었습니다.',
                    style: TextStyle(
                      color: AppColors.neonOrange,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (lowConfidence.isNotEmpty && unrecognized.isEmpty && _correctedFrames.isEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.neonOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.neonOrange.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppColors.neonOrange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '일부 프레임의 인식 정확도가 낮을 수 있습니다. 확인 후 적용해주세요.',
                    style: TextStyle(
                      color: AppColors.neonOrange,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }

  Widget _buildActionButtons() {
    final hasTotal = _estimatedTotal != null;

    return Column(
      children: [
        if (hasTotal)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _applyTotalOnly,
              icon: const Icon(Icons.speed_rounded, size: 20),
              label: Text(
                '총점만 저장 ($_estimatedTotal점)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        if (hasTotal) const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: _recognizedCount > 0
              ? ElevatedButton.icon(
                  onPressed: _applyFrameDetail,
                  icon: const Icon(Icons.grid_on_rounded, size: 20),
                  label: Text(
                    _recognizedCount == 10
                        ? '프레임 상세 적용'
                        : '프레임 적용 후 나머지 직접 입력',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: hasTotal
                      ? ElevatedButton.styleFrom(
                          backgroundColor: AppColors.darkCard,
                          foregroundColor: AppColors.neonOrange,
                          side: BorderSide(color: AppColors.neonOrange),
                        )
                      : null,
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, null),
            icon: Icon(Icons.camera_alt_outlined,
                size: 18, color: AppColors.textSecondary),
            label: Text(
              '다시 촬영하기',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.darkDivider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
