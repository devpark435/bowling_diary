import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:bowling_diary/app/theme/app_colors.dart';
import 'package:bowling_diary/app/theme/app_text_styles.dart';
import 'package:bowling_diary/shared/widgets/loading_widget.dart';
import 'package:bowling_diary/features/auth/presentation/providers/auth_provider.dart';
import 'package:bowling_diary/features/balls/domain/entities/ball_entity.dart';
import 'package:bowling_diary/features/balls/presentation/providers/ball_provider.dart';
import 'package:bowling_diary/features/home/presentation/providers/home_provider.dart';

class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key, this.editSession});

  final EditSessionData? editSession;

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class EditSessionData {
  final String sessionId;
  final DateTime date;
  final String? alleyName;
  final int? laneNumber;
  final String? oilPattern;
  final String? memo;
  final List<EditGameData> games;

  const EditSessionData({
    required this.sessionId,
    required this.date,
    this.alleyName,
    this.laneNumber,
    this.oilPattern,
    this.memo,
    required this.games,
  });
}

class EditGameData {
  final int totalScore;
  final String? ballId;

  const EditGameData({required this.totalScore, this.ballId});
}

class _GameEntry {
  final TextEditingController scoreController;
  BallEntity? selectedBall;
  VoidCallback? _listener;

  _GameEntry() : scoreController = TextEditingController();

  void attachListener(VoidCallback listener) {
    _listener = listener;
    scoreController.addListener(listener);
  }

  void dispose() {
    if (_listener != null) scoreController.removeListener(_listener!);
    scoreController.dispose();
  }
}

class _RecordPageState extends ConsumerState<RecordPage> {
  final _formKey = GlobalKey<FormState>();
  final _alleyNameController = TextEditingController();
  final _laneNumberController = TextEditingController();
  final _oilPatternController = TextEditingController();
  final _memoController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  late final List<_GameEntry> _games;
  bool get _isEditMode => widget.editSession != null;

  @override
  void initState() {
    super.initState();
    final edit = widget.editSession;
    if (edit != null) {
      _selectedDate = edit.date;
      _alleyNameController.text = edit.alleyName ?? '';
      _laneNumberController.text = edit.laneNumber?.toString() ?? '';
      _oilPatternController.text = edit.oilPattern ?? '';
      _memoController.text = edit.memo ?? '';
      _games = edit.games.map((g) {
        final entry = _GameEntry()..attachListener(_onScoreChanged);
        entry.scoreController.text = g.totalScore.toString();
        return entry;
      }).toList();
      if (_games.isEmpty) {
        _games.add(_GameEntry()..attachListener(_onScoreChanged));
      }
    } else {
      _games = [_GameEntry()..attachListener(_onScoreChanged)];
    }
  }

  void _onScoreChanged() => setState(() {});
  bool _isLoading = false;
  bool _didRestoreBalls = false;

  @override
  void dispose() {
    _alleyNameController.dispose();
    _laneNumberController.dispose();
    _oilPatternController.dispose();
    _memoController.dispose();
    for (final g in _games) {
      g.dispose();
    }
    super.dispose();
  }

  void _addGame() {
    if (_games.length >= 10) return;
    final entry = _GameEntry()..attachListener(_onScoreChanged);
    setState(() => _games.add(entry));
  }

  void _removeGame(int index) {
    if (_games.length <= 1) return;
    setState(() {
      _games[index].dispose();
      _games.removeAt(index);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.neonOrange,
              surface: AppColors.darkCard,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _showBallPicker(int gameIndex) {
    final asyncBalls = ref.read(ballsListProvider);
    asyncBalls.whenData((balls) {
      showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.darkCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('사용한 볼 선택', style: AppTextStyles.headingSmall),
                      IconButton(
                        icon: Icon(Icons.close, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(color: AppColors.darkDivider, height: 1),
                ListTile(
                  leading: Icon(Icons.clear, color: AppColors.textHint),
                  title: Text('선택 안 함', style: TextStyle(color: AppColors.textSecondary)),
                  onTap: () {
                    setState(() => _games[gameIndex].selectedBall = null);
                    Navigator.pop(context);
                  },
                ),
                if (balls.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('등록된 볼이 없습니다.\n내 볼 탭에서 먼저 추가해주세요.', 
                      style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
                  )
                else
                  ...balls.map((ball) => ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.darkDivider,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.sports_baseball, color: AppColors.neonOrange, size: 20),
                    ),
                    title: Text(ball.name, style: TextStyle(color: AppColors.textPrimary)),
                    subtitle: ball.brand != null 
                      ? Text('${ball.brand} ${ball.weight != null ? "/ ${ball.weight}lb" : ""}',
                          style: AppTextStyles.bodySmall)
                      : null,
                    trailing: _games[gameIndex].selectedBall?.id == ball.id
                      ? Icon(Icons.check_circle, color: AppColors.neonOrange)
                      : null,
                    onTap: () {
                      setState(() => _games[gameIndex].selectedBall = ball);
                      Navigator.pop(context);
                    },
                  )),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final dataSource = ref.read(sessionRemoteDataSourceProvider);

      if (_isEditMode) {
        final sessionId = widget.editSession!.sessionId;
        await dataSource.updateSession(
          id: sessionId,
          date: _selectedDate,
          alleyName: _alleyNameController.text.trim().isEmpty ? null : _alleyNameController.text.trim(),
          laneNumber: int.tryParse(_laneNumberController.text.trim()),
          oilPattern: _oilPatternController.text.trim().isEmpty ? null : _oilPatternController.text.trim(),
          memo: _memoController.text.trim().isEmpty ? null : _memoController.text.trim(),
        );

        await dataSource.deleteGamesBySessionId(sessionId);
        for (int i = 0; i < _games.length; i++) {
          final entry = _games[i];
          final score = int.tryParse(entry.scoreController.text.trim()) ?? 0;
          await dataSource.createGame(
            id: const Uuid().v4(),
            sessionId: sessionId,
            gameNumber: i + 1,
            ballId: entry.selectedBall?.id,
            totalScore: score,
          );
        }
      } else {
        final sessionId = const Uuid().v4();
        await dataSource.createSession(
          id: sessionId,
          userId: user.id,
          date: _selectedDate,
          alleyName: _alleyNameController.text.trim().isEmpty ? null : _alleyNameController.text.trim(),
          laneNumber: int.tryParse(_laneNumberController.text.trim()),
          oilPattern: _oilPatternController.text.trim().isEmpty ? null : _oilPatternController.text.trim(),
          memo: _memoController.text.trim().isEmpty ? null : _memoController.text.trim(),
        );

        for (int i = 0; i < _games.length; i++) {
          final entry = _games[i];
          final score = int.tryParse(entry.scoreController.text.trim()) ?? 0;
          await dataSource.createGame(
            id: const Uuid().v4(),
            sessionId: sessionId,
            gameNumber: i + 1,
            ballId: entry.selectedBall?.id,
            totalScore: score,
          );
        }
      }

      ref.invalidate(recentGamesProvider);
      ref.invalidate(monthlySummaryProvider);

      if (mounted) {
        final msg = _isEditMode ? '기록이 수정되었습니다!' : '${_games.length}게임이 기록되었습니다!';
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('기록 저장 에러: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장에 실패했습니다. 다시 시도해주세요.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditMode && !_didRestoreBalls) {
      final ballsAsync = ref.watch(ballsListProvider);
      ballsAsync.whenData((balls) {
        final edit = widget.editSession!;
        for (int i = 0; i < _games.length && i < edit.games.length; i++) {
          final ballId = edit.games[i].ballId;
          if (ballId != null) {
            final match = balls.where((b) => b.id == ballId);
            if (match.isNotEmpty) {
              _games[i].selectedBall = match.first;
            }
          }
        }
        _didRestoreBalls = true;
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isEditMode ? '기록 수정' : '게임 기록')),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSessionInfoSection(),
                const SizedBox(height: 28),
                _buildGamesSection(),
                const SizedBox(height: 28),
                _buildMemoSection(),
                const SizedBox(height: 32),
                _buildSubmitButton(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('세션 정보', style: AppTextStyles.headingSmall),
        const SizedBox(height: 16),
        // 날짜 선택
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.darkDivider),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: AppColors.neonOrange, size: 20),
                const SizedBox(width: 12),
                Text(
                  DateFormat('yyyy년 M월 d일 (E)', 'ko').format(_selectedDate),
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                ),
                const Spacer(),
                Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 볼링장 이름
        TextFormField(
          controller: _alleyNameController,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '볼링장 이름',
            prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.textHint, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        // 레인 번호 + 오일 패턴
        Row(
          children: [
            SizedBox(
              width: 120,
              child: TextFormField(
                controller: _laneNumberController,
                style: TextStyle(color: AppColors.textPrimary),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: '레인 번호',
                  prefixIcon: Icon(Icons.tag, color: AppColors.textHint, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _oilPatternController,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '오일 패턴 (예: Kegel Middle Road)',
                  prefixIcon: Icon(Icons.water_drop_outlined, color: AppColors.textHint, size: 18),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGamesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('게임 점수', style: AppTextStyles.headingSmall),
            TextButton.icon(
              onPressed: _games.length < 10 ? _addGame : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('게임 추가'),
              style: TextButton.styleFrom(foregroundColor: AppColors.neonOrange),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._games.asMap().entries.map((entry) {
          final idx = entry.key;
          final game = entry.value;
          return _buildGameCard(idx, game);
        }),
      ],
    );
  }

  Widget _buildGameCard(int index, _GameEntry game) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.neonOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: AppColors.neonOrange,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('게임 ${index + 1}', style: AppTextStyles.labelLarge),
              const Spacer(),
              if (_games.length > 1)
                GestureDetector(
                  onTap: () => _removeGame(index),
                  child: Icon(Icons.remove_circle_outline, color: AppColors.error, size: 22),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // 점수 입력
          TextFormField(
            controller: game.scoreController,
            style: AppTextStyles.scoreDisplay.copyWith(fontSize: 28),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _MaxScoreFormatter(300),
            ],
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: AppTextStyles.scoreDisplay.copyWith(
                fontSize: 28,
                color: AppColors.textHint,
              ),
              filled: true,
              fillColor: AppColors.darkBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return '점수를 입력하세요';
              final score = int.tryParse(v.trim());
              if (score == null || score < 0 || score > 300) return '0~300 사이 점수를 입력하세요';
              return null;
            },
          ),
          const SizedBox(height: 12),
          // 볼 선택
          GestureDetector(
            onTap: () => _showBallPicker(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.darkBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sports_baseball,
                    color: game.selectedBall != null ? AppColors.neonOrange : AppColors.textHint,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    game.selectedBall?.name ?? '사용한 볼 선택',
                    style: TextStyle(
                      color: game.selectedBall != null ? AppColors.textPrimary : AppColors.textHint,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: AppColors.textHint, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('메모', style: AppTextStyles.headingSmall),
        const SizedBox(height: 12),
        TextFormField(
          controller: _memoController,
          style: TextStyle(color: AppColors.textPrimary),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: '오늘의 컨디션, 느낀점 등을 자유롭게 기록하세요',
            prefixIcon: Padding(
              padding: EdgeInsets.only(bottom: 48),
              child: Icon(Icons.edit_note, color: AppColors.textHint, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    final totalScore = _games.fold<int>(0, (sum, g) {
      return sum + (int.tryParse(g.scoreController.text.trim()) ?? 0);
    });
    final avg = _games.isEmpty ? 0.0 : totalScore / _games.length;

    return Column(
      children: [
        if (totalScore > 0)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.darkDivider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text('$totalScore', style: AppTextStyles.scoreDisplay.copyWith(fontSize: 22, color: AppColors.neonOrange)),
                    const SizedBox(height: 2),
                    Text('총 점수', style: AppTextStyles.labelSmall),
                  ],
                ),
                Container(width: 1, height: 36, color: AppColors.darkDivider),
                Column(
                  children: [
                    Text(avg.toStringAsFixed(1), style: AppTextStyles.scoreDisplay.copyWith(fontSize: 22, color: AppColors.mint)),
                    const SizedBox(height: 2),
                    Text('평균', style: AppTextStyles.labelSmall),
                  ],
                ),
                Container(width: 1, height: 36, color: AppColors.darkDivider),
                Column(
                  children: [
                    Text('${_games.length}', style: AppTextStyles.scoreDisplay.copyWith(fontSize: 22)),
                    const SizedBox(height: 2),
                    Text('게임 수', style: AppTextStyles.labelSmall),
                  ],
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            child: Text(_isEditMode ? '수정 저장하기' : '기록 저장하기'),
          ),
        ),
      ],
    );
  }
}

class _MaxScoreFormatter extends TextInputFormatter {
  final int max;
  _MaxScoreFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final value = int.tryParse(newValue.text);
    if (value == null || value > max) return oldValue;
    return newValue;
  }
}
