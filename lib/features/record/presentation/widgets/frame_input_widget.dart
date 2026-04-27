import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/features/record/domain/entities/game_entity.dart';

class FrameInputWidget extends StatefulWidget {
  final List<FrameData>? initialFrames;
  final ValueChanged<List<FrameData>> onFramesChanged;
  final ValueChanged<int> onTotalScoreChanged;

  const FrameInputWidget({
    super.key,
    this.initialFrames,
    required this.onFramesChanged,
    required this.onTotalScoreChanged,
  });

  @override
  State<FrameInputWidget> createState() => _FrameInputWidgetState();
}

class _FrameInputWidgetState extends State<FrameInputWidget> {
  late List<_FrameState> _frames;
  int _currentFrame = 0;
  int _currentThrow = 0; // 0=first, 1=second, 2=third (10프레임)
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _frames = List.generate(10, (i) => _FrameState(frameNumber: i + 1));
    if (widget.initialFrames != null) {
      for (final f in widget.initialFrames!) {
        if (f.frameNumber >= 1 && f.frameNumber <= 10) {
          final idx = f.frameNumber - 1;
          _frames[idx].firstThrow = f.firstThrow;
          _frames[idx].secondThrow = f.secondThrow;
          _frames[idx].thirdThrow = f.thirdThrow;
          _frames[idx].isComplete = _isFrameComplete(f);
        }
      }
      _findNextInput();
      WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentFrame() {
    if (!_scrollController.hasClients) return;
    const frameWidth = 64.0; // 60 + 4 margin
    final targetOffset = (_currentFrame * frameWidth) -
        (_scrollController.position.viewportDimension / 2) +
        (frameWidth / 2);
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _findNextInput() {
    for (int i = 0; i < 10; i++) {
      if (!_frames[i].isComplete) {
        _currentFrame = i;
        if (_frames[i].firstThrow == null) {
          _currentThrow = 0;
        } else if (_frames[i].secondThrow == null) {
          _currentThrow = 1;
        } else {
          _currentThrow = 2;
        }
        return;
      }
    }
    _currentFrame = 9;
    _currentThrow = -1;
  }

  /// FrameData가 완전한 프레임인지 판별
  bool _isFrameComplete(FrameData f) {
    if (f.frameNumber < 10) {
      return f.firstThrow == 10 || f.secondThrow != null;
    }
    // 10프레임
    if (f.secondThrow == null) return false;
    final needsThird =
        f.firstThrow == 10 || (f.firstThrow + f.secondThrow!) == 10;
    return needsThird ? f.thirdThrow != null : true;
  }

  bool get _isGameComplete => _frames.every((f) => f.isComplete);

  int get _maxPins {
    final frame = _frames[_currentFrame];
    if (_currentFrame < 9) {
      if (_currentThrow == 0) return 10;
      return 10 - (frame.firstThrow ?? 0);
    }
    // 10프레임
    if (_currentThrow == 0) return 10;
    if (_currentThrow == 1) {
      if (frame.firstThrow == 10) return 10;
      return 10 - (frame.firstThrow ?? 0);
    }
    // 세 번째 투구
    if (frame.firstThrow == 10 && frame.secondThrow == 10) return 10;
    if (frame.firstThrow == 10) return 10 - (frame.secondThrow ?? 0);
    return 10;
  }

  void _recordThrow(int pins) {
    if (_isGameComplete) return;

    setState(() {
      final frame = _frames[_currentFrame];

      if (_currentFrame < 9) {
        if (_currentThrow == 0) {
          frame.firstThrow = pins;
          if (pins == 10) {
            frame.isComplete = true;
          } else {
            _currentThrow = 1;
            _notify();
            return;
          }
        } else {
          frame.secondThrow = pins;
          frame.isComplete = true;
        }
      } else {
        // 10프레임
        if (_currentThrow == 0) {
          frame.firstThrow = pins;
          _currentThrow = 1;
          _notify();
          return;
        } else if (_currentThrow == 1) {
          frame.secondThrow = pins;
          final needsThird = frame.firstThrow == 10 ||
              (frame.firstThrow! + pins) == 10;
          if (needsThird) {
            _currentThrow = 2;
            _notify();
            return;
          } else {
            frame.isComplete = true;
          }
        } else {
          frame.thirdThrow = pins;
          frame.isComplete = true;
        }
      }

      _findNextInput();
      _notify();
    });
  }

  void _undo() {
    setState(() {
      for (int i = 9; i >= 0; i--) {
        final frame = _frames[i];
        if (i == 9) {
          if (frame.thirdThrow != null) {
            frame.thirdThrow = null;
            frame.isComplete = false;
            _currentFrame = 9;
            _currentThrow = 2;
            _notify();
            return;
          }
          if (frame.secondThrow != null) {
            frame.secondThrow = null;
            frame.isComplete = false;
            _currentFrame = 9;
            _currentThrow = 1;
            _notify();
            return;
          }
          if (frame.firstThrow != null) {
            frame.firstThrow = null;
            frame.isComplete = false;
            _currentFrame = 9;
            _currentThrow = 0;
            _notify();
            return;
          }
        } else {
          if (frame.secondThrow != null) {
            frame.secondThrow = null;
            frame.isComplete = false;
            _currentFrame = i;
            _currentThrow = 1;
            _notify();
            return;
          }
          if (frame.firstThrow != null) {
            frame.firstThrow = null;
            frame.isComplete = false;
            _currentFrame = i;
            _currentThrow = 0;
            _notify();
            return;
          }
        }
      }
    });
  }

  void _reset() {
    setState(() {
      _frames = List.generate(10, (i) => _FrameState(frameNumber: i + 1));
      _currentFrame = 0;
      _currentThrow = 0;
      _notify();
    });
  }

  void _notify() {
    final frameDataList = _frames
        .where((f) => f.firstThrow != null)
        .map((f) => FrameData(
              frameNumber: f.frameNumber,
              firstThrow: f.firstThrow!,
              secondThrow: f.secondThrow,
              thirdThrow: f.thirdThrow,
            ))
        .toList();
    widget.onFramesChanged(frameDataList);
    widget.onTotalScoreChanged(_calculateTotal());
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentFrame());
  }

  int _calculateTotal() {
    int total = 0;
    for (int i = 0; i < 10; i++) {
      final f = _frames[i];
      if (f.firstThrow == null) break;

      if (i < 9) {
        if (f.isStrike) {
          total += 10 + _nextTwoBalls(i);
        } else if (f.isSpare) {
          total += 10 + _nextOneBall(i);
        } else {
          total += f.firstThrow! + (f.secondThrow ?? 0);
        }
      } else {
        total += f.firstThrow! + (f.secondThrow ?? 0) + (f.thirdThrow ?? 0);
      }
    }
    return total;
  }

  int _nextOneBall(int frameIdx) {
    if (frameIdx + 1 < 10) {
      return _frames[frameIdx + 1].firstThrow ?? 0;
    }
    return 0;
  }

  int _nextTwoBalls(int frameIdx) {
    final next = frameIdx + 1;
    if (next >= 10) return 0;
    final f = _frames[next];
    if (f.firstThrow == null) return 0;

    if (next < 9 && f.isStrike) {
      return 10 + _nextOneBall(next);
    }
    return f.firstThrow! + (f.secondThrow ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildScoreBoard(),
        const SizedBox(height: 16),
        if (!_isGameComplete) _buildPinButtons(),
        const SizedBox(height: 12),
        _buildControls(),
      ],
    );
  }

  Widget _buildScoreBoard() {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(10, (i) => _buildFrameCell(i)),
      ),
    );
  }

  Widget _buildFrameCell(int idx) {
    final frame = _frames[idx];
    final isCurrent = idx == _currentFrame && !_isGameComplete;
    final isTenth = idx == 9;

    return Container(
      width: isTenth ? 90 : 60,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.neonOrange.withValues(alpha: 0.1)
            : AppColors.darkCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrent ? AppColors.neonOrange : AppColors.darkDivider,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.darkDivider, width: 0.5),
              ),
            ),
            child: Center(
              child: Text(
                '${idx + 1}',
                style: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: isTenth
                  ? _buildTenthFrameThrows(frame)
                  : _buildNormalFrameThrows(frame),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.darkDivider, width: 0.5),
              ),
            ),
            child: Center(
              child: Text(
                frame.isComplete ? '${_cumulativeScore(idx)}' : '',
                style: AppTextStyles.scoreSmall.copyWith(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNormalFrameThrows(_FrameState frame) {
    return [
      _throwBox(frame.firstDisplay, frame.isStrike),
      const SizedBox(width: 2),
      _throwBox(frame.secondDisplay, frame.isSpare),
    ];
  }

  List<Widget> _buildTenthFrameThrows(_FrameState frame) {
    final first = frame.firstThrow;
    final second = frame.secondThrow;
    final third = frame.thirdThrow;

    String firstStr = first == null ? '' : (first == 10 ? 'X' : '$first');
    String secondStr = '';
    if (second != null) {
      if (first == 10 && second == 10) {
        secondStr = 'X';
      } else if (first != 10 && (first! + second) == 10) {
        secondStr = '/';
      } else {
        secondStr = '$second';
      }
    }
    String thirdStr = '';
    if (third != null) {
      if (third == 10) {
        thirdStr = 'X';
      } else if (second != null) {
        final prevPins = (first == 10 && second == 10) ? 0 :
                         (first == 10) ? second : 0;
        if (prevPins + third == 10 && prevPins != 10) {
          thirdStr = '/';
        } else {
          thirdStr = '$third';
        }
      }
    }

    return [
      _throwBox(firstStr, firstStr == 'X'),
      const SizedBox(width: 2),
      _throwBox(secondStr, secondStr == 'X' || secondStr == '/'),
      const SizedBox(width: 2),
      _throwBox(thirdStr, thirdStr == 'X' || thirdStr == '/'),
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
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  int _cumulativeScore(int upTo) {
    int total = 0;
    for (int i = 0; i <= upTo; i++) {
      final f = _frames[i];
      if (f.firstThrow == null) return total;
      if (i < 9) {
        if (f.isStrike) {
          total += 10 + _nextTwoBalls(i);
        } else if (f.isSpare) {
          total += 10 + _nextOneBall(i);
        } else {
          total += f.firstThrow! + (f.secondThrow ?? 0);
        }
      } else {
        total += f.firstThrow! + (f.secondThrow ?? 0) + (f.thirdThrow ?? 0);
      }
    }
    return total;
  }

  Widget _buildPinButtons() {
    final max = _maxPins;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: List.generate(max + 1, (pins) {
        final isStrike = pins == 10;
        return GestureDetector(
          onTap: () => _recordThrow(pins),
          child: Container(
            width: isStrike ? 64 : 48,
            height: 48,
            decoration: BoxDecoration(
              color: isStrike
                  ? AppColors.neonOrange.withValues(alpha: 0.15)
                  : pins == 0
                      ? AppColors.darkDivider
                      : AppColors.darkCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isStrike ? AppColors.neonOrange : AppColors.darkDivider,
              ),
            ),
            child: Center(
              child: Text(
                isStrike ? 'X' : '$pins',
                style: TextStyle(
                  color: isStrike ? AppColors.neonOrange : AppColors.textPrimary,
                  fontSize: isStrike ? 18 : 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        Expanded(
          child: Text(
            _isGameComplete
                ? '게임 완료! 총 ${_calculateTotal()}점'
                : '${_currentFrame + 1}프레임 ${_currentThrow == 0 ? "1투" : _currentThrow == 1 ? "2투" : "3투"}',
            style: AppTextStyles.labelLarge,
          ),
        ),
        TextButton.icon(
          onPressed: _undo,
          icon: Icon(PhosphorIconsRegular.arrowCounterClockwise, size: 16, color: AppColors.textSecondary),
          label: Text('되돌리기', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
        TextButton.icon(
          onPressed: _reset,
          icon: Icon(PhosphorIconsRegular.arrowClockwise, size: 16, color: AppColors.textHint),
          label: Text('초기화', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
        ),
      ],
    );
  }
}

class _FrameState {
  final int frameNumber;
  int? firstThrow;
  int? secondThrow;
  int? thirdThrow;
  bool isComplete;

  _FrameState({required this.frameNumber})
      : isComplete = false;

  bool get isStrike => firstThrow == 10 && frameNumber < 10;
  bool get isSpare =>
      !isStrike &&
      firstThrow != null &&
      secondThrow != null &&
      (firstThrow! + secondThrow!) == 10 &&
      frameNumber < 10;

  String get firstDisplay {
    if (firstThrow == null) return '';
    if (firstThrow == 10) return 'X';
    return '$firstThrow';
  }

  String get secondDisplay {
    if (secondThrow == null) return '';
    if (isSpare) return '/';
    return '$secondThrow';
  }
}
