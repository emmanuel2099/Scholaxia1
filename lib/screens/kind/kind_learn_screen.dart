import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/student_ui.dart';
import 'kind_shared.dart';

class KindLearnScreen extends StatefulWidget {
  const KindLearnScreen({super.key});

  @override
  State<KindLearnScreen> createState() => _KindLearnScreenState();
}

class _KindLearnScreenState extends State<KindLearnScreen> {
  final _api = ApiService();
  final _topicCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();
  String _subject = 'General';
  String? _lessonText;
  KindQuizResult? _quiz;
  bool _loading = false;
  bool _checking = false;
  String? _feedback;
  List<String> _subjects = ['General'];

  /// Selected option letter per question id.
  final Map<String, String> _answers = {};
  bool _quizFinished = false;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    try {
      final subs = await _api.kindSubjects();
      if (mounted && subs.isNotEmpty) setState(() => _subjects = subs);
    } catch (_) {}
  }

  Future<void> _run({required bool quiz}) async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _lessonText = null;
      _quiz = null;
      _feedback = null;
      _answers.clear();
      _quizFinished = false;
      _score = 0;
      _replyCtrl.clear();
    });
    try {
      if (quiz) {
        final result = await _api.kindSiaQuiz(topic: topic, subject: _subject);
        if (mounted) setState(() => _quiz = result);
      } else {
        final text = await _api.kindSiaLearn(topic: topic, subject: _subject);
        if (mounted) setState(() => _lessonText = text);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _lessonText = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pickAnswer(KindQuizQuestion q, String letter) {
    if (_quizFinished) return;
    setState(() => _answers[q.id] = letter);
  }

  Future<void> _submitQuiz() async {
    final quiz = _quiz;
    if (quiz == null || quiz.questions.isEmpty) return;
    final unanswered =
        quiz.questions.where((q) => !_answers.containsKey(q.id)).toList();
    if (unanswered.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Answer all questions first (${unanswered.length} left).',
          ),
        ),
      );
      return;
    }

    final withKeys = quiz.questions.every((q) => q.hasAnswerKey);
    if (withKeys) {
      var score = 0;
      for (final q in quiz.questions) {
        if (_answers[q.id] == q.correct) score++;
      }
      setState(() {
        _score = score;
        _quizFinished = true;
        _feedback =
            'You got $score / ${quiz.questions.length} correct. Great effort!';
      });
      return;
    }

    // No answer key from server — ask Sia to check.
    setState(() => _checking = true);
    final lines = quiz.questions
        .map((q) => 'Q${q.id}: ${_answers[q.id]}')
        .join('\n');
    try {
      final history = <Map<String, dynamic>>[
        {
          'role': 'assistant',
          'content': quiz.rawText.isNotEmpty ? quiz.rawText : quiz.intro,
        },
      ];
      final r = await _api.kindSiaChat(
        question:
            'I finished the quiz. Please check my answers and tell me my score:\n$lines',
        subject: _subject,
        conversationHistory: history,
      );
      if (mounted) {
        setState(() {
          _quizFinished = true;
          _feedback = r.text;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _feedback = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    final quiz = _quiz;
    if (text.isEmpty || quiz == null || _checking) return;
    setState(() => _checking = true);
    try {
      final history = <Map<String, dynamic>>[
        {
          'role': 'assistant',
          'content': quiz.rawText.isNotEmpty ? quiz.rawText : quiz.intro,
        },
      ];
      final r = await _api.kindSiaChat(
        question: text,
        subject: _subject,
        conversationHistory: history,
      );
      if (mounted) {
        setState(() {
          _feedback = r.text;
          _replyCtrl.clear();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _feedback = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  const StudentBackButton(),
                  Text(
                    'Learn & Play',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            KindHeroHeader(
              greeting: 'Learn & Play',
              subtitle:
                  'Pick a topic and get a mini-lesson or fun quiz from Sia.',
              icon: Icons.menu_book_rounded,
            ),
            const StudentSectionTitle(title: 'Choose a topic'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Subject',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: context.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _subjects.contains(_subject)
                            ? _subject
                            : _subjects.first,
                        isExpanded: true,
                        dropdownColor: context.cardColor,
                        style: TextStyle(color: context.textColor),
                        items: _subjects
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _subject = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Topic',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _topicCtrl,
                    style: TextStyle(color: context.textColor),
                    decoration: InputDecoration(
                      hintText: 'e.g. Adding numbers, Animals, Colors...',
                      hintStyle: TextStyle(color: context.greyLColor),
                      filled: true,
                      fillColor: context.cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                            color: context.accentColor, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _actionButton(
                          context,
                          icon: Icons.menu_book_rounded,
                          label: 'Lesson',
                          colors: const [
                            Color(0xFF10B981),
                            Color(0xFF34D399),
                          ],
                          onTap: _loading ? null : () => _run(quiz: false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionButton(
                          context,
                          icon: Icons.quiz_rounded,
                          label: 'Quiz',
                          colors: const [
                            Color(0xFFF59E0B),
                            Color(0xFFFBBF24),
                          ],
                          onTap: _loading ? null : () => _run(quiz: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 32),
              Center(
                child: CircularProgressIndicator(color: context.accentColor),
              ),
            ],
            if (_lessonText != null) ...[
              const StudentSectionTitle(title: 'Lesson'),
              _resultCard(context, _lessonText!),
            ],
            if (_quiz != null) ...[
              const StudentSectionTitle(title: 'Quiz'),
              if (_quiz!.intro.trim().isNotEmpty)
                _resultCard(
                  context,
                  _quiz!.isInteractive
                      ? _quiz!.intro
                      : (_quiz!.rawText.isNotEmpty
                          ? _quiz!.rawText
                          : _quiz!.intro),
                ),
              if (_quiz!.isInteractive) ...[
                const SizedBox(height: 12),
                ..._quiz!.questions.map(_questionCard),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_checking || _quizFinished)
                          ? null
                          : _submitQuiz,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _checking
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              _quizFinished
                                  ? 'Finished · $_score / ${_quiz!.questions.length}'
                                  : 'Check my answers',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                    ),
                  ),
                ),
              ] else ...[
                // Plain text quiz (no parseable options): allow typed reply.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replyCtrl,
                          enabled: !_checking,
                          style: TextStyle(color: context.textColor),
                          decoration: InputDecoration(
                            hintText: 'Type your answers, e.g. Q1: C, Q2: A',
                            hintStyle: TextStyle(color: context.greyLColor),
                            filled: true,
                            fillColor: context.cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide:
                                  BorderSide(color: context.borderColor),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                          onSubmitted: (_) => _sendReply(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: _checking ? null : _sendReply,
                        style: IconButton.styleFrom(
                          backgroundColor: context.accentColor,
                          foregroundColor: Colors.white,
                        ),
                        icon: _checking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ],
              if (_feedback != null) ...[
                const StudentSectionTitle(title: 'Sia says'),
                _resultCard(context, _feedback!),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _questionCard(KindQuizQuestion q) {
    final selected = _answers[q.id];
    final letters = q.options.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Q${q.id}. ${q.question}',
              style: TextStyle(
                color: context.textColor,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            ...letters.map((letter) {
              final text = q.options[letter] ?? '';
              final isSel = selected == letter;
              final showMark = _quizFinished && q.hasAnswerKey;
              final isCorrect = letter == q.correct;
              Color border = context.borderColor;
              Color fill = context.surfColor;
              if (isSel && !showMark) {
                border = context.accentColor;
                fill = context.accentColor.withOpacity(0.12);
              }
              if (showMark && isCorrect) {
                border = const Color(0xFF22C55E);
                fill = const Color(0xFF22C55E).withOpacity(0.12);
              } else if (showMark && isSel && !isCorrect) {
                border = const Color(0xFFEF4444);
                fill = const Color(0xFFEF4444).withOpacity(0.10);
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: fill,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _quizFinished ? null : () => _pickAnswer(q, letter),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: isSel
                                ? context.accentColor
                                : context.borderColor,
                            child: Text(
                              letter,
                              style: TextStyle(
                                color: isSel ? Colors.white : context.textColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              text,
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: context.isDark
                ? [const Color(0xFF1A1428), const Color(0xFF221A35)]
                : [Colors.white, const Color(0xFFF3EEFF)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: context.accentColor.withOpacity(0.2),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: context.textColor,
            fontSize: 14,
            height: 1.55,
          ),
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required List<Color> colors,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colors.last.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
