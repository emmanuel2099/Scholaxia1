import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import 'game_session.dart';

class WordArrangementScreen extends StatefulWidget {
  const WordArrangementScreen({super.key});

  @override
  State<WordArrangementScreen> createState() => _WordArrangementScreenState();
}

class _WordArrangementScreenState extends State<WordArrangementScreen> {
  final _rng = Random();
  late GameSessionQueue _queue;
  Timer? _timer;

  int _score = 0;
  int _lives = 3;
  int _timeLeft = 25;
  late _Puzzle _puzzle;
  final List<String> _picked = [];
  List<String> _pool = [];
  bool _locked = false;
  bool _finished = false;

  static const _puzzles = <_Puzzle>[
    _Puzzle(sentence: 'The mitochondria is the powerhouse of the cell', hint: 'Biology'),
    _Puzzle(sentence: 'Photosynthesis converts light energy into chemical energy', hint: 'Plant science'),
    _Puzzle(sentence: 'Newton second law relates force mass and acceleration', hint: 'Physics'),
    _Puzzle(sentence: 'Democracy derives its legitimacy from the consent of the governed', hint: 'Government'),
    _Puzzle(sentence: 'Supply and demand determine equilibrium price in a free market', hint: 'Economics'),
    _Puzzle(sentence: 'Metamorphic rocks form under intense heat and pressure', hint: 'Geology'),
    _Puzzle(sentence: 'The hypotenuse is the longest side of a right triangle', hint: 'Mathematics'),
    _Puzzle(sentence: 'Chlorophyll absorbs red and blue wavelengths of light', hint: 'Botany'),
    _Puzzle(sentence: 'Entropy always increases in an isolated thermodynamic system', hint: 'Thermodynamics'),
    _Puzzle(sentence: 'The Magna Carta limited the power of the English monarch', hint: 'History'),
    _Puzzle(sentence: 'Osmosis is the movement of water across a membrane', hint: 'Biology'),
    _Puzzle(sentence: 'Velocity equals displacement divided by time elapsed', hint: 'Physics'),
    _Puzzle(sentence: 'A catalyst speeds up a reaction without being consumed', hint: 'Chemistry'),
    _Puzzle(sentence: 'The executive branch enforces laws passed by the legislature', hint: 'Civics'),
    _Puzzle(sentence: 'Inflation reduces the purchasing power of money over time', hint: 'Economics'),
    _Puzzle(sentence: 'Igneous rocks crystallize from molten magma or lava', hint: 'Geology'),
    _Puzzle(sentence: 'The area of a circle equals pi times radius squared', hint: 'Mathematics'),
    _Puzzle(sentence: 'Evaporation occurs when molecules escape from liquid surface', hint: 'Chemistry'),
    _Puzzle(sentence: 'The Bill of Rights protects individual freedoms from government', hint: 'History'),
    _Puzzle(sentence: 'DNA carries genetic instructions for all living organisms', hint: 'Biology'),
    _Puzzle(sentence: 'Friction opposes the relative motion of surfaces in contact', hint: 'Physics'),
    _Puzzle(sentence: 'A balanced chemical equation obeys the law of conservation', hint: 'Chemistry'),
    _Puzzle(sentence: 'Separation of powers prevents any branch from dominating', hint: 'Government'),
    _Puzzle(sentence: 'Opportunity cost is the value of the next best alternative', hint: 'Economics'),
    _Puzzle(sentence: 'Sedimentary rocks form from compressed layers of sediment', hint: 'Geology'),
    _Puzzle(sentence: 'The Pythagorean theorem relates sides of a right triangle', hint: 'Mathematics'),
    _Puzzle(sentence: 'Transpiration releases water vapor through plant stomata', hint: 'Botany'),
    _Puzzle(sentence: 'The Renaissance sparked renewed interest in classical learning', hint: 'History'),
    _Puzzle(sentence: 'An ecosystem includes all living and nonliving components', hint: 'Ecology'),
    _Puzzle(sentence: 'Gravitational force is proportional to mass and inversely to distance', hint: 'Physics'),
  ];

  @override
  void initState() {
    super.initState();
    _queue = GameSessionQueue(poolSize: _puzzles.length, rng: _rng);
    _newRound();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _newRound() {
    _timer?.cancel();
    if (_lives <= 0) return;
    final idx = _queue.nextIndex();
    if (idx == null) {
      setState(() => _finished = true);
      return;
    }
    _locked = false;
    _picked.clear();
    _puzzle = _puzzles[idx];
    _pool = _puzzle.words.toList()..shuffle(_rng);
    _timeLeft = max(12, 28 - (_queue.level ~/ 3));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _timeLeft = max(0, _timeLeft - 1));
      if (_timeLeft == 0) _fail('Time up');
    });
    if (mounted) setState(() {});
  }

  void _tapWord(String word) {
    if (_locked || _lives <= 0 || _finished) return;
    setState(() {
      _picked.add(word);
      _pool.remove(word);
    });
    if (_picked.length == _puzzle.words.length) _check();
  }

  void _undoLast() {
    if (_locked || _picked.isEmpty) return;
    setState(() {
      final w = _picked.removeLast();
      _pool.add(w);
    });
  }

  void _check() {
    final attempt = _picked.join(' ').toLowerCase();
    final target = _puzzle.sentence.toLowerCase();
    if (attempt == target) {
      _timer?.cancel();
      setState(() {
        _score += 30 + _timeLeft + _queue.level * 2;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfect!'),
          backgroundColor: Color(0xFF22C55E),
          duration: Duration(milliseconds: 600),
        ),
      );
      Future.delayed(const Duration(milliseconds: 450), _newRound);
    } else {
      _fail('Wrong order');
    }
  }

  void _fail(String reason) {
    _timer?.cancel();
    setState(() {
      _locked = true;
      _lives = max(0, _lives - 1);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$reason — answer shown'),
        backgroundColor: const Color(0xFFEF4444),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _restart() {
    _queue.reset(poolSize: _puzzles.length, rng: _rng);
    setState(() {
      _score = 0;
      _lives = 3;
      _finished = false;
    });
    _newRound();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _buildFinished(context);
    final dead = _lives <= 0;
    final urgent = _timeLeft <= 6;
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const StudentBackButton(),
                  Text('Word Arrangement',
                      style: TextStyle(
                          color: context.textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  _pill(context,
                      'Level', '${_queue.level}/${GameSessionQueue.maxLevels}'),
                  const SizedBox(width: 8),
                  _pill(context, 'Score', '$_score'),
                  const Spacer(),
                  _pill(context, 'Lives', '$_lives',
                      color: _lives <= 1
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  _pill(context, 'Time', '${_timeLeft}s',
                      color: urgent
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF6366F1)),
                ],
              ),
            ),
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
            if (dead)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text('Game Over',
                        style: TextStyle(
                            color: context.textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text('Score: $_score — Level ${_queue.completed}',
                        style: TextStyle(color: context.greyColor)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _restart,
                      child: const Text('Restart'),
                    ),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(
                  'Hint: ${_puzzle.hint}',
                  style: TextStyle(
                      color: context.greyColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.accentColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: context.accentColor.withOpacity(0.25)),
                ),
                child: _picked.isEmpty
                    ? Text(
                        'Tap words below in the correct order…',
                        style: TextStyle(
                            color: context.greyColor, fontSize: 13),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _picked
                            .map((w) => Chip(
                                  label: Text(w),
                                  backgroundColor:
                                      context.accentColor.withOpacity(0.15),
                                ))
                            .toList(),
                      ),
              ),
              if (_locked) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Text(
                    _puzzle.sentence,
                    style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: TextButton(
                    onPressed: _lives > 0 ? _newRound : null,
                    child: const Text('Next sentence'),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _pool
                      .map(
                        (w) => ActionChip(
                          label: Text(w),
                          onPressed: _locked ? null : () => _tapWord(w),
                          backgroundColor: context.cardColor,
                          side: BorderSide(color: context.borderColor),
                        ),
                      )
                      .toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: _locked ? null : _undoLast,
                      child: const Text('Undo'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: (_locked ||
                              _picked.length != _puzzle.words.length)
                          ? null
                          : _check,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.accentColor,
                        foregroundColor: context.isDark
                            ? AppColors.background
                            : Colors.white,
                      ),
                      child: const Text('Check',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ],
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

  Widget _pill(BuildContext context, String label, String value, {Color? color}) {
    final c = color ?? context.accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.25)),
      ),
      child: Text('$label $value',
          style: TextStyle(
              color: context.textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _Puzzle {
  final String sentence;
  final String hint;
  List<String> get words => sentence.split(' ');
  const _Puzzle({required this.sentence, required this.hint});
}
