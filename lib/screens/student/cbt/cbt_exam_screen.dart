import 'dart:async';
import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'cbt_result_screen.dart';

class CbtExamScreen extends StatefulWidget {
  final String subject;
  final int totalQuestions;
  final int durationSeconds;
  final String? sessionId;
  final List<CbtQuestion> questions;

  /// When set, this is an internal (school) exam taken offline; on submit we
  /// send answers to the internal-exam endpoint (scored server-side) instead of
  /// the normal session submit.
  final String? internalExamId;

  const CbtExamScreen({
    super.key,
    this.subject = 'BIOLOGY',
    this.totalQuestions = 60,
    this.durationSeconds = 7200,
    this.sessionId,
    this.questions = const [],
    this.internalExamId,
  });

  @override
  State<CbtExamScreen> createState() => _CbtExamScreenState();
}

class _CbtExamScreenState extends State<CbtExamScreen> {
  int _currentQuestion = 1; // 1-based
  int _selectedOption = -1;
  late int _remainingSeconds;
  Timer? _timer;
  bool _isSubmitting = false;
  final Map<String, String> _answers = {};
  final Set<String> _bookmarked = {};
  final _scrollCtrl = ScrollController();
  final _api = ApiService();

  late List<CbtQuestion> _questions;

  @override
  void initState() {
    super.initState();
    _questions = widget.questions.isNotEmpty
        ? widget.questions
        : _fallbackQuestions(widget.totalQuestions);
    _remainingSeconds = widget.durationSeconds;
    _restoreSelection();
    _startTimer();
  }

  List<CbtQuestion> _fallbackQuestions(int count) {
    return List.generate(count, (i) => CbtQuestion(
          id: 'q${i + 1}',
          text: 'Sample question ${i + 1}. Select the best answer from the options below.',
          options: const [
            'Option A',
            'Option B',
            'Option C',
            'Option D',
          ],
        ));
  }

  CbtQuestion get _activeQuestion => _questions[_currentQuestion - 1];

  int get _questionCount => _questions.length;

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        _timer?.cancel();
        _submitExam(isAutoSubmit: true);
      }
    });
  }

  void _saveCurrentAnswer() {
    if (_selectedOption >= 0) {
      final labels = ['A', 'B', 'C', 'D'];
      _answers[_activeQuestion.id] = labels[_selectedOption];
    }
  }

  void _restoreSelection() {
    final saved = _answers[_activeQuestion.id];
    if (saved == null) {
      _selectedOption = -1;
      return;
    }
    const labels = ['A', 'B', 'C', 'D'];
    _selectedOption = labels.indexOf(saved);
  }

  void _goToQuestion(int questionNumber) {
    if (questionNumber < 1 || questionNumber > _questionCount) return;
    _saveCurrentAnswer();
    setState(() {
      _currentQuestion = questionNumber;
      _restoreSelection();
    });
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _submitExam({bool isAutoSubmit = false}) async {
    if (_isSubmitting) return;
    _saveCurrentAnswer();
    _timer?.cancel();
    setState(() => _isSubmitting = true);

    CbtResult? result;
    String? submitError;
    if (widget.internalExamId != null) {
      try {
        result = await _api.submitInternalExam(
          examId: widget.internalExamId!,
          answers: _answers,
          isAutoSubmit: isAutoSubmit,
        );
      } catch (e) {
        submitError = e.toString();
      }
    } else if (widget.sessionId != null) {
      try {
        result = await _api.cbtSubmit(
          sessionId: widget.sessionId!,
          answers: _answers,
          isAutoSubmit: isAutoSubmit,
        );
      } catch (_) {}
    }

    if (!mounted) return;
    if (widget.internalExamId != null && result == null) {
      // Offline or failed submit — let the student know it will be retried.
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            submitError != null && submitError.contains('already')
                ? 'You already submitted this exam.'
                : 'Could not submit now. Reconnect and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CbtResultScreen(
          sessionId: widget.sessionId ?? '',
          result: result,
        ),
      ),
    );
  }

  String get _timerDisplay {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color _timerColor(BuildContext context) {
    if (_remainingSeconds < 300) return const Color(0xFFEF4444);
    if (_remainingSeconds < 600) return context.accentColor;
    return context.textColor;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final question = _activeQuestion;
    final btnFg = context.isDark ? AppColors.background : Colors.white;
    final isBookmarked = _bookmarked.contains(question.id);

    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _buildQuestionCard(context, question, isBookmarked),
                    const SizedBox(height: 16),
                    ...List.generate(
                      question.options.length,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildOptionTile(context, i, question.options[i]),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            _buildBottomBar(context, btnFg),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.accentColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.subject,
              style: TextStyle(
                color: context.isDark ? AppColors.background : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(Icons.timer_outlined, color: context.accentColor, size: 16),
              const SizedBox(width: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  color: _timerColor(context),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                child: Text(_timerDisplay),
              ),
            ],
          ),
          const Spacer(),
          Text(
            '$_currentQuestion / $_questionCount',
            style: TextStyle(
              color: context.greyColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(BuildContext context, CbtQuestion question, bool isBookmarked) {
    return Container(
      key: ValueKey(question.id),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (question.topic != null && question.topic!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(question.topic!,
                      style: TextStyle(
                          color: context.accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() {
                  if (isBookmarked) {
                    _bookmarked.remove(question.id);
                  } else {
                    _bookmarked.add(question.id);
                  }
                }),
                child: Icon(
                  isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                  color: isBookmarked ? context.accentColor : context.greyColor,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            question.text,
            style: TextStyle(
              color: context.textColor,
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (question.hasImage) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                question.imageUrl!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 160,
                  color: context.surfColor,
                  child: Icon(Icons.broken_image_outlined, color: context.greyColor),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionTile(BuildContext context, int index, String text) {
    final labels = ['A', 'B', 'C', 'D'];
    final isSelected = _selectedOption == index;
    final labelFg = isSelected
        ? (context.isDark ? AppColors.background : Colors.white)
        : context.greyColor;

    return GestureDetector(
      onTap: () => setState(() => _selectedOption = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? context.accentColor.withOpacity(context.isDark ? 0.12 : 0.08)
              : context.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? context.accentColor : context.borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? context.accentColor : context.surfColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(labels[index],
                    style: TextStyle(
                      color: labelFg,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    )),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                    color: isSelected ? context.textColor : context.greyColor,
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  )),
            ),
            if (isSelected)
              Icon(Icons.radio_button_checked, color: context.accentColor, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, Color btnFg) {
    final isLast = _currentQuestion >= _questionCount;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: context.headerColor,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_currentQuestion > 1) _goToQuestion(_currentQuestion - 1);
            },
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _currentQuestion > 1
                    ? context.surfColor
                    : context.surfColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Icon(Icons.arrow_back,
                  color: _currentQuestion > 1 ? context.textColor : context.greyColor,
                  size: 20),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _showQuestionMap,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: context.surfColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Icon(Icons.grid_view_rounded, color: context.textColor, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: _isSubmitting
                    ? null
                    : () {
                        _saveCurrentAnswer();
                        if (isLast) {
                          _submitExam();
                        } else {
                          _goToQuestion(_currentQuestion + 1);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  disabledBackgroundColor: context.accentColor.withOpacity(0.4),
                  foregroundColor: btnFg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: btnFg))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLast ? 'Submit Exam' : 'Next',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(width: 6),
                          Icon(isLast ? Icons.check_circle_outline : Icons.arrow_forward, size: 18),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuestionMap() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Question Map',
                style: TextStyle(
                    color: ctx.textColor, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 10,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1,
              ),
              itemCount: _questionCount,
              itemBuilder: (_, i) {
                final num = i + 1;
                final isCurrent = num == _currentQuestion;
                final qId = _questions[i].id;
                final isAnswered = _answers.containsKey(qId);
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _goToQuestion(num);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? ctx.accentColor
                          : isAnswered
                              ? ctx.accentColor.withOpacity(0.25)
                              : ctx.surfColor,
                      borderRadius: BorderRadius.circular(6),
                      border: isCurrent ? null : Border.all(color: ctx.borderColor),
                    ),
                    child: Center(
                      child: Text('$num',
                          style: TextStyle(
                            color: isCurrent
                                ? (ctx.isDark ? AppColors.background : Colors.white)
                                : ctx.greyColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _MapLegend(color: ctx.accentColor, label: 'Current'),
                const SizedBox(width: 16),
                _MapLegend(color: ctx.accentColor.withOpacity(0.25), label: 'Answered'),
                const SizedBox(width: 16),
                _MapLegend(color: ctx.surfColor, label: 'Unanswered'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _MapLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: context.greyColor, fontSize: 11)),
      ],
    );
  }
}
