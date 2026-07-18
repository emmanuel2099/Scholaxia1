import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import 'game_session.dart';

class MathArenaScreen extends StatefulWidget {
  const MathArenaScreen({super.key});

  @override
  State<MathArenaScreen> createState() => _MathArenaScreenState();
}

class _MathArenaScreenState extends State<MathArenaScreen> {
  final _rng = Random();
  final _input = TextEditingController();
  late GameSessionQueue _queue;
  late List<_Equation> _equations;
  Timer? _timer;

  int _score = 0;
  int _lives = 3;
  int _timeTotal = 18;
  int _timeLeft = 18;
  late _Equation _eq;
  bool _locked = false;
  bool _finished = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _equations = _buildEquationPool();
    _queue = GameSessionQueue(poolSize: _equations.length, rng: _rng);
    _startRound();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  List<_Equation> _buildEquationPool() {
    final seen = <String>{};
    final pool = <_Equation>[];
    var seed = 0;
    while (pool.length < GameSessionQueue.maxLevels && seed < 500) {
      final eq = _generate(pool.length + 1, Random(seed * 31 + 7));
      if (seen.add(eq.expression)) pool.add(eq);
      seed++;
    }
    while (pool.length < GameSessionQueue.maxLevels) {
      final n = pool.length + 1;
      pool.add(_generate(n, Random(n * 101)));
    }
    return pool;
  }

  void _startRound() {
    _timer?.cancel();
    final idx = _queue.nextIndex();
    if (idx == null) {
      setState(() => _finished = true);
      return;
    }
    _locked = false;
    _feedback = null;
    _input.clear();
    final level = _queue.level;
    _timeTotal = max(7, 18 - (level ~/ 3));
    _timeLeft = _timeTotal;
    _eq = _equations[idx];
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _timeLeft = max(0, _timeLeft - 1));
      if (_timeLeft == 0) _wrong('Time up');
    });
    if (mounted) setState(() {});
  }

  void _submit() {
    if (_locked || _lives <= 0 || _finished) return;
    final val = int.tryParse(_input.text.trim());
    if (val == null) {
      setState(() => _feedback = 'Enter an integer for x');
      return;
    }
    if (val == _eq.solution) {
      _timer?.cancel();
      final bonus = _timeLeft + min(25, _queue.level).toInt();
      setState(() {
        _score += 25 + bonus;
        _feedback = 'Correct! +${25 + bonus}';
      });
      Future.delayed(const Duration(milliseconds: 500), _startRound);
    } else {
      _wrong('Wrong');
    }
  }

  void _wrong(String reason) {
    if (_locked) return;
    _timer?.cancel();
    setState(() {
      _locked = true;
      _lives = max(0, _lives - 1);
      _feedback = '$reason — x = ${_eq.solution}';
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (_lives <= 0) {
        setState(() {});
        return;
      }
      _startRound();
    });
  }

  void _restart() {
    _equations = _buildEquationPool();
    _queue.reset(poolSize: _equations.length, rng: _rng);
    setState(() {
      _score = 0;
      _lives = 3;
      _finished = false;
      _feedback = null;
    });
    _startRound();
  }

  _Equation _generate(int level, Random rng) {
    final x = rng.nextInt(21) - 10;
    final diff = min(6, 1 + (level ~/ 3));
    int a = _nz(rng.nextInt(11) - 5);
    int b = rng.nextInt(21) - 10;
    int c = _nz(rng.nextInt(11) - 5);
    int d = _nz(rng.nextInt(9) - 4);
    int e = rng.nextInt(21) - 10;
    int k = diff >= 4 ? rng.nextInt(17) - 8 : 0;

    if (diff <= 2) {
      final rhs = a * (x + b) + c;
      return _Equation(
        expression: '${_fmt(a)}(x ${_pm(b)}) ${_pm(c)} = $rhs',
        solution: x,
      );
    }
    k = a * (x + b) + c - d * (x + e);
    return _Equation(
      expression:
          '${_fmt(a)}(x ${_pm(b)}) ${_pm(c)} = ${_fmt(d)}(x ${_pm(e)}) ${_pm(k)}',
      solution: x,
    );
  }

  int _nz(int v) => v == 0 ? 1 : v;
  String _pm(int n) => n >= 0 ? '+ $n' : '- ${n.abs()}';
  String _fmt(int n) => n == 1 ? '' : (n == -1 ? '-' : '$n');

  @override
  Widget build(BuildContext context) {
    if (_finished) return _buildFinished(context);
    final dead = _lives <= 0;
    final pct = (_timeLeft / _timeTotal).clamp(0.0, 1.0);
    final urgent = _timeLeft <= 4;
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
                  Text('Math Arena',
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
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _queue.completed / GameSessionQueue.maxLevels,
                  minHeight: 6,
                  backgroundColor: context.borderColor.withOpacity(0.7),
                  valueColor: AlwaysStoppedAnimation(context.accentColor),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: context.borderColor.withOpacity(0.7),
                  valueColor: AlwaysStoppedAnimation(
                    urgent ? const Color(0xFFEF4444) : context.accentColor,
                  ),
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
                  Text('Solve for x',
                      style: TextStyle(
                          color: context.greyColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text(
                    dead ? 'Game Over — Score: $_score' : _eq.expression,
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_feedback != null) ...[
                    const SizedBox(height: 10),
                    Text(_feedback!,
                        style: TextStyle(
                            color: _feedback!.contains('Correct')
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFEF4444),
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ],
                ],
              ),
            ),
            if (!dead) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: TextField(
                  controller: _input,
                  enabled: !_locked,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'x = ?',
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
                child: ElevatedButton(
                  onPressed: _locked ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor:
                        context.isDark ? AppColors.background : Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Submit',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.all(24),
                child: ElevatedButton(
                  onPressed: _restart,
                  child: const Text('Restart'),
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

class _Equation {
  final String expression;
  final int solution;
  const _Equation({required this.expression, required this.solution});
}
