import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'sil_anticheat_service.dart';
import 'sil_face_verify_screen.dart';
import 'sil_models.dart';
import 'sil_results_screen.dart';
import 'sil_widgets.dart';

class SilQuizScreen extends StatefulWidget {
  final String mode;
  final String subject;
  final SilProfile profile;
  final bool offline;
  final ValueChanged<SilProfile>? onProfileUpdate;
  final int? aiLevel;
  final int? betCoins;
  final String? opponentTag;

  const SilQuizScreen({
    super.key,
    required this.mode,
    required this.subject,
    required this.profile,
    this.offline = false,
    this.onProfileUpdate,
    this.aiLevel,
    this.betCoins,
    this.opponentTag,
  });

  @override
  State<SilQuizScreen> createState() => _SilQuizScreenState();
}

class _SilQuizScreenState extends State<SilQuizScreen>
    with WidgetsBindingObserver {
  final _api = ApiService();
  bool _loading = true;
  String? _matchId;
  List<SilQuestion> _questions = [];
  int _index = 0;
  int? _selected;
  int _score = 0;
  int _seconds = 20;
  Timer? _timer;
  DateTime? _qStarted;
  final List<Map<String, dynamic>> _answers = [];
  bool _used5050 = false;
  bool _usedHint = false;
  Set<int> _hiddenOptions = {};
  String? _hintText;
  bool _busy = false;
  bool _pausedForCheat = false;
  bool _showProctor = false;
  int _cheatStrikes = 0;

  bool get _isCompetitive => widget.mode != 'practice';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootSecureMatch();
  }

  Future<void> _bootSecureMatch() async {
    if (_isCompetitive) {
      // Device integrity gate (emulator / root / jailbreak)
      final gate = await SilAntiCheatService.instance.runDeviceGate();
      if (!mounted) return;
      if (gate['allowed'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Blocked by anti-cheat: ${gate['reason'] ?? 'unsafe device'}'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
        return;
      }

      final ok = await SilFaceVerifyScreen.open(
        context,
        title: 'Verify before challenge',
        subtitle:
            'Liveness + face required. Front camera monitors you for the whole match.',
        requireApi: !widget.offline,
      );
      if (!mounted) return;
      if (ok == null) {
        Navigator.pop(context);
        return;
      }
      setState(() => _showProctor = true);
    }
    await _startMatch();
    if (_isCompetitive && _matchId != null && mounted) {
      await SilAntiCheatService.instance.runDeviceGate(matchId: _matchId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isCompetitive || _matchId == null) return;
    if (state == AppLifecycleState.paused) {
      _onBackgroundCheat();
    } else if (state == AppLifecycleState.resumed && _pausedForCheat) {
      _resumeAfterVerify();
    }
  }

  Future<void> _onBackgroundCheat() async {
    _timer?.cancel();
    _pausedForCheat = true;
    _cheatStrikes++;
    final res = await SilAntiCheatService.instance
        .reportEvent(_matchId!, 'background', detail: 'app_backgrounded');
    if (res['forfeited'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match forfeited — anti-cheat violation.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Match paused (strike $_cheatStrikes). Re-verify face to continue.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _resumeAfterVerify() async {
    final ok = await SilFaceVerifyScreen.open(
      context,
      title: 'Re-verify to resume',
      subtitle: 'You left the app during a live challenge. Verify again.',
      matchId: _matchId,
      requireApi: !widget.offline,
    );
    if (!mounted) return;
    if (ok == null || _cheatStrikes >= 3) {
      await SilAntiCheatService.instance
          .reportEvent(_matchId!, 'forfeit_strikes');
      Navigator.pop(context);
      return;
    }
    try {
      await _api.silFaceVerify(
        faceSelfieB64: ok,
        matchId: _matchId,
        livenessOk: true,
      );
    } catch (_) {}
    _pausedForCheat = false;
    _beginQuestion();
  }

  void _onCameraLost() {
    if (!_isCompetitive || _matchId == null) return;
    _cheatStrikes++;
    SilAntiCheatService.instance.reportEvent(
      _matchId!,
      'no_face',
      detail: 'camera_lost_or_covered',
    );
    if (_cheatStrikes >= 3 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Forfeited — camera / face monitoring failed.'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context);
    }
  }

  void _onProctorSignal(Map<String, dynamic> res) {
    if (res['forfeited'] == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Match forfeited by server anti-cheat.'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context);
      return;
    }
    if (res['paused'] == true && mounted) {
      setState(() => _pausedForCheat = true);
      _timer?.cancel();
      _resumeAfterVerify();
    }
  }

  Future<void> _startMatch() async {
    try {
      Map<String, dynamic> data;
      if (widget.offline) {
        data = _localMatch();
      } else {
        switch (widget.mode) {
          case 'ai_challenge':
            data = await _api.silStartAi(widget.aiLevel ?? 1);
            break;
          case 'student_challenge':
            data = await _api.silStartStudentChallenge(
              opponentGamerTag: widget.opponentTag,
              betCoins: widget.betCoins ?? 100,
              subject: widget.subject,
            );
            break;
          case 'class_challenge':
            data = await _api.silStartClassChallenge();
            break;
          case 'school_challenge':
            data = await _api.silStartSchoolChallenge();
            break;
          case 'friday_national':
            data = await _api.silStartFriday();
            break;
          default:
            data = await _api.silStartPractice(
              subject: widget.subject,
              questionCount: 10,
            );
        }
      }
      final match = SilMatch.fromJson(data);
      // If server stripped correct_index, keep local bank indices for offline grading fallback
      var qs = match.questions;
      if (qs.isEmpty) {
        qs = SilLocalBank.practice.take(10).toList();
      }
      if (!mounted) return;
      setState(() {
        _matchId = match.id;
        _questions = qs;
        _seconds = match.secondsPerQuestion;
        _loading = false;
      });
      _beginQuestion();
    } catch (_) {
      final data = _localMatch();
      final match = SilMatch.fromJson(data);
      if (!mounted) return;
      setState(() {
        _matchId = match.id;
        _questions = match.questions;
        _seconds = 20;
        _loading = false;
      });
      _beginQuestion();
    }
  }

  Map<String, dynamic> _localMatch() {
    final count = widget.mode == 'friday_national'
        ? 15
        : (widget.mode.contains('class') || widget.mode.contains('school')
            ? 10
            : (widget.mode == 'practice' ? 10 : 5));
    final pool = List<SilQuestion>.from(SilLocalBank.practice)..shuffle();
    final qs = pool.take(min(count, pool.length)).toList();
    return {
      'id': 'local_${DateTime.now().millisecondsSinceEpoch}',
      'mode': widget.mode,
      'status': 'live',
      'subject': widget.subject,
      'question_count': qs.length,
      'seconds_per_question': 20,
      'entry_coins': widget.betCoins ?? 0,
      'face_required': widget.mode != 'practice',
      'questions': qs
          .map((q) => {
                'id': q.id,
                'text': q.text,
                'options': q.options,
                'hint': q.hint,
                'subject': q.subject,
                'correct_index': q.correctIndex,
              })
          .toList(),
    };
  }

  void _beginQuestion() {
    _timer?.cancel();
    _selected = null;
    _used5050 = false;
    _usedHint = false;
    _hiddenOptions = {};
    _hintText = null;
    _qStarted = DateTime.now();
    _seconds = 20;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_seconds <= 1) {
        t.cancel();
        _lockIn(auto: true);
      } else {
        setState(() => _seconds--);
      }
    });
    setState(() {});
  }

  void _fiftyFifty() {
    if (_used5050 || _selected != null) return;
    final q = _questions[_index];
    final correct = q.correctIndex ?? 0;
    final wrong = [0, 1, 2, 3].where((i) => i != correct).toList()..shuffle();
    setState(() {
      _used5050 = true;
      _hiddenOptions = wrong.take(2).toSet();
    });
  }

  void _showHint() {
    if (_usedHint) return;
    setState(() {
      _usedHint = true;
      _hintText = _questions[_index].hint ?? 'Think carefully about the basics.';
    });
  }

  void _skip() {
    _lockIn(skip: true);
  }

  Future<void> _lockIn({bool auto = false, bool skip = false}) async {
    if (_busy) return;
    _timer?.cancel();
    final elapsed = DateTime.now().difference(_qStarted ?? DateTime.now()).inMilliseconds;
    final q = _questions[_index];
    final selected = skip || auto && _selected == null ? null : _selected;
    final correct = q.correctIndex;
    if (correct != null && selected == correct) {
      _score += 100 + max(0, 50 - elapsed ~/ 400);
    }
    _answers.add({
      'question_index': _index,
      'selected_index': selected,
      'elapsed_ms': elapsed,
      'skipped': skip,
      'used_skip': skip,
      'used_5050': _used5050,
      'used_hint': _usedHint,
    });

    if (_index + 1 >= _questions.length) {
      await _finish();
      return;
    }
    setState(() => _index++);
    _beginQuestion();
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    if (_isCompetitive &&
        _matchId != null &&
        SilAntiCheatService.instance.looksSuspiciousTiming(_answers)) {
      await SilAntiCheatService.instance.reportEvent(
        _matchId!,
        'suspicious_timing',
        detail: 'too_many_sub_800ms_answers',
      );
    }
    Map<String, dynamic> result;
    try {
      if (!widget.offline &&
          _matchId != null &&
          !_matchId!.startsWith('local_')) {
        result = await _api.silFinishMatch(_matchId!, _answers);
      } else {
        result = _localResult();
      }
    } catch (_) {
      result = _localResult();
    }
    if (!mounted) return;
    final coinsEarned = (result['coins_earned'] as num?)?.toInt() ?? 0;
    final updated = widget.profile.copyWith(
      coins: (result['coins'] as num?)?.toInt() ??
          (widget.profile.coins + coinsEarned),
      wins: widget.profile.wins + ((result['won'] == true) ? 1 : 0),
      losses: widget.profile.losses + ((result['won'] == true) ? 0 : 1),
    );
    widget.onProfileUpdate?.call(updated);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SilResultsScreen(
          result: result,
          subject: widget.subject,
          profile: updated,
        ),
      ),
    );
  }

  Map<String, dynamic> _localResult() {
    var correct = 0;
    for (final a in _answers) {
      final qi = a['question_index'] as int;
      final sel = a['selected_index'];
      if (qi < _questions.length &&
          sel != null &&
          sel == _questions[qi].correctIndex) {
        correct++;
      }
    }
    final total = _questions.length;
    final won = correct >= ((total + 1) ~/ 2);
    final coins = widget.mode == 'practice'
        ? 0
        : (won ? (widget.betCoins ?? 50) : 0);
    return {
      'won': won,
      'correct': correct,
      'total': total,
      'score': _score,
      'longest_streak': correct,
      'coins_earned': coins,
      'coins': widget.profile.coins + coins,
      'time_taken_ms': _answers.fold<int>(
          0, (s, a) => s + ((a['elapsed_ms'] as num?)?.toInt() ?? 0)),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: SilColors.purple)),
      );
    }
    final q = _questions[_index];
    final letters = ['A', 'B', 'C', 'D'];

    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded,
                        color: context.textColor),
                  ),
                  Expanded(
                    child: Text(widget.subject,
                        style: TextStyle(
                            color: context.textColor,
                            fontWeight: FontWeight.w800)),
                  ),
                  if (_isCompetitive)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('ANTI-CHEAT ON',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _seconds <= 5
                          ? Colors.red.shade100
                          : SilColors.purpleSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$_seconds sec',
                        style: TextStyle(
                          color: _seconds <= 5
                              ? Colors.red
                              : SilColors.purple,
                          fontWeight: FontWeight.w800,
                        )),
                  ),
                  const SizedBox(width: 8),
                  SilCoinChip(coins: widget.profile.coins),
                ],
              ),
              const SizedBox(height: 8),
              Text('Question ${_index + 1}/${_questions.length}',
                  style: TextStyle(color: context.greyColor, fontSize: 13)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (_index + 1) / _questions.length,
                  minHeight: 8,
                  color: SilColors.purple,
                  backgroundColor: SilColors.purpleSoft,
                ),
              ),
              const SizedBox(height: 8),
              Text('Score $_score',
                  style: const TextStyle(
                      color: SilColors.purple, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Text(
                q.text,
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              if (_hintText != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SilColors.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Hint: $_hintText',
                      style: TextStyle(color: context.textColor)),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: q.options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    if (_hiddenOptions.contains(i)) {
                      return const SizedBox.shrink();
                    }
                    final selected = _selected == i;
                    return InkWell(
                      onTap: _pausedForCheat
                          ? null
                          : () => setState(() => _selected = i),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? SilColors.purple
                              : (context.isDark
                                  ? const Color(0xFF1A1228)
                                  : Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? SilColors.purple
                                : SilColors.purple.withOpacity(0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: selected
                                  ? Colors.white24
                                  : SilColors.purpleSoft,
                              child: Text(letters[i],
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : SilColors.purple,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  )),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                q.options[i],
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : context.textColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(Icons.check_circle,
                                  color: Colors.white),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: [
                  _life('50:50', Icons.filter_2_rounded, _fiftyFifty),
                  const SizedBox(width: 8),
                  _life('Hint', Icons.lightbulb_outline, _showHint),
                  const SizedBox(width: 8),
                  _life('Skip', Icons.skip_next_rounded, _skip),
                ],
              ),
              const SizedBox(height: 12),
              SilPrimaryButton(
                label: _index + 1 >= _questions.length
                    ? 'See results'
                    : 'Next Question →',
                loading: _busy,
                onPressed: (_selected == null && !_busy) || _pausedForCheat
                    ? null
                    : () => _lockIn(),
              ),
            ],
              ),
            ),
            if (_showProctor)
              Positioned(
                right: 12,
                top: 56,
                child: SilProctorPip(
                  matchId: _matchId,
                  onCameraLost: _onCameraLost,
                  onServerSignal: _onProctorSignal,
                ),
              ),
            if (_pausedForCheat)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Match paused — complete face re-verify to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  Widget _life(String label, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          foregroundColor: SilColors.purple,
          side: const BorderSide(color: SilColors.purple),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
