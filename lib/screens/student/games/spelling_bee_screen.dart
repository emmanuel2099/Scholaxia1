import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import 'game_session.dart';

class SpellingBeeScreen extends StatefulWidget {
  const SpellingBeeScreen({super.key});

  @override
  State<SpellingBeeScreen> createState() => _SpellingBeeScreenState();
}

class _SpellingBeeScreenState extends State<SpellingBeeScreen> {
  static const _roundSeconds = 18;
  final _rng = Random();
  final _input = TextEditingController();
  late GameSessionQueue _queue;
  Timer? _timer;

  int _timeLeft = _roundSeconds;
  int _score = 0;
  int _streak = 0;
  bool _showAnswer = false;
  bool _finished = false;
  late _Word _current;

  static const _words = <_Word>[
    _Word(word: 'metamorphosis', clue: 'Complete change of form in biology.'),
    _Word(word: 'circumlocution', clue: 'Talking around a point without being direct.'),
    _Word(word: 'sesquipedalian', clue: 'Fond of using very long words.'),
    _Word(word: 'synecdoche', clue: 'Figure of speech: part for the whole.'),
    _Word(word: 'epistemology', clue: 'Branch of philosophy about knowledge.'),
    _Word(word: 'inconsequential', clue: 'Not important; insignificant.'),
    _Word(word: 'quintessential', clue: 'The most perfect example of something.'),
    _Word(word: 'idiosyncrasy', clue: 'A peculiar personal habit or trait.'),
    _Word(word: 'pharmacopoeia', clue: 'Official book of medicines and drugs.'),
    _Word(word: 'onomatopoeia', clue: 'Word that imitates a sound.'),
    _Word(word: 'acquiescence', clue: 'Acceptance without protest.'),
    _Word(word: 'bureaucracy', clue: 'System of government by officials.'),
    _Word(word: 'conscientious', clue: 'Wishing to do what is right.'),
    _Word(word: 'deleterious', clue: 'Causing harm or damage.'),
    _Word(word: 'ecclesiastical', clue: 'Relating to the Christian Church.'),
    _Word(word: 'flabbergasted', clue: 'Greatly surprised or astonished.'),
    _Word(word: 'grandiloquent', clue: 'Pompous or extravagant in language.'),
    _Word(word: 'heterogeneous', clue: 'Diverse in character or content.'),
    _Word(word: 'idempotent', clue: 'Unchanged when applied repeatedly.'),
    _Word(word: 'juxtaposition', clue: 'Placing things side by side for contrast.'),
    _Word(word: 'kaleidoscope', clue: 'Constantly changing pattern or scene.'),
    _Word(word: 'labyrinthine', clue: 'Like a maze; complicated.'),
    _Word(word: 'magnanimous', clue: 'Generous in forgiving.'),
    _Word(word: 'nomenclature', clue: 'System of naming things.'),
    _Word(word: 'obstreperous', clue: 'Noisy and difficult to control.'),
    _Word(word: 'perspicacious', clue: 'Having keen mental perception.'),
    _Word(word: 'quintessence', clue: 'The most perfect embodiment of something.'),
    _Word(word: 'recalcitrant', clue: 'Stubbornly uncooperative.'),
    _Word(word: 'serendipitous', clue: 'Found by happy accident.'),
    _Word(word: 'transcendental', clue: 'Beyond ordinary physical experience.'),
  ];

  @override
  void initState() {
    super.initState();
    _queue = GameSessionQueue(poolSize: _words.length, rng: _rng);
    _loadNext();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _loadNext() {
    _timer?.cancel();
    final idx = _queue.nextIndex();
    if (idx == null) {
      setState(() => _finished = true);
      return;
    }
    _showAnswer = false;
    _input.clear();
    _timeLeft = max(8, _roundSeconds - (_queue.completed ~/ 4));
    _current = _words[idx];
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _timeLeft = max(0, _timeLeft - 1));
      if (_timeLeft == 0) _fail('Time up');
    });
    if (mounted) setState(() {});
  }

  void _submit() {
    final typed = _input.text.trim().toLowerCase();
    if (typed.isEmpty) return;
    if (typed == _current.word.toLowerCase()) {
      _timer?.cancel();
      final bonus = min(15, _streak * 2);
      setState(() {
        _score += 15 + bonus + _queue.level;
        _streak += 1;
      });
      Future.delayed(const Duration(milliseconds: 400), _loadNext);
    } else {
      _fail('Wrong spelling');
    }
  }

  void _fail(String reason) {
    _timer?.cancel();
    setState(() {
      _streak = 0;
      _showAnswer = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$reason — correct: ${_current.word}'),
        backgroundColor: const Color(0xFFEF4444),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _restart() {
    _queue.reset(poolSize: _words.length, rng: _rng);
    setState(() {
      _score = 0;
      _streak = 0;
      _finished = false;
    });
    _loadNext();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _buildFinished(context);
    final pct = (_timeLeft / _roundSeconds).clamp(0.0, 1.0);
    final urgent = _timeLeft <= 5;
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
          children: [
            _header(context, 'Spelling Bee'),
            _stats(context, urgent),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _queue.completed / GameSessionQueue.maxLevels,
                  minHeight: 8,
                  backgroundColor: context.borderColor.withOpacity(0.7),
                  valueColor: AlwaysStoppedAnimation(context.accentColor),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'Level ${_queue.level} of ${GameSessionQueue.maxLevels} — no repeats',
                style: TextStyle(color: context.greyColor, fontSize: 11),
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Clue', style: _labelStyle(context)),
                  const SizedBox(height: 6),
                  Text(
                    _current.clue,
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (_showAnswer) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _current.word,
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        TextButton(onPressed: _loadNext, child: const Text('Next')),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: TextField(
                controller: _input,
                enabled: !_showAnswer && _timeLeft > 0,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Type exact spelling…',
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
                    borderSide:
                        BorderSide(color: context.accentColor, width: 1.5),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_showAnswer || _timeLeft == 0) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor:
                        context.isDark ? AppColors.background : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Submit',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinished(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const StudentBackButton(),
              const Spacer(),
              const Text('🏆', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text('All 30 levels complete!',
                  style: TextStyle(
                      color: context.textColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Final score: $_score',
                  style: TextStyle(color: context.greyColor, fontSize: 15)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _restart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor:
                      context.isDark ? AppColors.background : Colors.white,
                ),
                child: const Text('Play again'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const StudentBackButton(),
          Text(title,
              style: TextStyle(
                  color: context.textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _stats(BuildContext context, bool urgent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _pill(context, 'Score', '$_score', context.accentColor),
          const SizedBox(width: 8),
          _pill(context, 'Streak', '$_streak', const Color(0xFF22C55E)),
          const SizedBox(width: 8),
          _pill(context, 'Level', '${_queue.level}/${GameSessionQueue.maxLevels}',
              const Color(0xFF6366F1)),
          const Spacer(),
          _pill(context, 'Time', '${_timeLeft}s',
              urgent ? const Color(0xFFEF4444) : const Color(0xFF6366F1)),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text('$label $value',
          style: TextStyle(
              color: context.textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }

  TextStyle _labelStyle(BuildContext context) => TextStyle(
        color: context.greyColor,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      );
}

class _Word {
  final String word;
  final String clue;
  const _Word({required this.word, required this.clue});
}
