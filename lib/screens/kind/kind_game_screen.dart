import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import 'kind_adventure_banks.dart';
import 'kind_game_banks.dart';
import 'kind_game_question.dart';
import 'kind_leaf_progress.dart';

export 'kind_game_question.dart';

class KindGameScreen extends StatefulWidget {
  final String gameId;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;

  /// Builder returns the FULL question pool; the screen selects fresh
  /// (not-yet-seen) questions for each play session.
  final List<GameQuestion> Function() questionBuilder;

  const KindGameScreen({
    super.key,
    required this.gameId,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.questionBuilder,
  });

  @override
  State<KindGameScreen> createState() => _KindGameScreenState();
}

class _KindGameScreenState extends State<KindGameScreen> {
  /// Up to 50 questions per play. Banks are 50+; admin questions grow the
  /// bank so full recycle only happens after every question was seen.
  static const _sessionSize = 50;

  List<GameQuestion> _questions = [];
  int _index = 0;
  int _score = 0;
  int? _selected;
  bool _answered = false;
  bool _finished = false;
  bool _ready = false;
  int _leafLevel = 1;
  LeafUnlockResult? _leafResult;
  int _poolSize = 0;
  final _tts = FlutterTts();
  final _api = ApiService();

  String get _seenKey => 'kidgame_seen_${widget.gameId}';

  @override
  void initState() {
    super.initState();
    _initTts();
    _prepareSession();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setSpeechRate(0.42);
      await _tts.setPitch(1.05);
      await _tts.setLanguage('en-US');
    } catch (_) {}
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<List<GameQuestion>> _loadAdminQuestions() async {
    // Offline-first: never block play on network. Admin Qs are a bonus when online.
    try {
      final raw = await _api
          .kindGameQuestions(widget.gameId)
          .timeout(const Duration(seconds: 4));
      return raw
          .map((m) {
            final opts = (m['options'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                <String>[];
            if (opts.length < 2) return null;
            final ci = (m['correct_index'] as num?)?.toInt() ?? 0;
            final safeCi = ci.clamp(0, opts.length - 1);
            return GameQuestion(
              prompt: m['prompt']?.toString() ?? '',
              options: opts,
              correct: safeCi,
              speakWord: m['speak_word']?.toString(),
              qid: 'admin_${m['id']}',
            );
          })
          .whereType<GameQuestion>()
          .where((q) => q.prompt.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _prepareSession() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenKey) ?? <String>[];
    final builtin = widget.questionBuilder();
    final adminQs = await _loadAdminQuestions();

    final byId = <String, GameQuestion>{};
    for (final q in [...adminQs, ...builtin]) {
      byId.putIfAbsent(q.id, () => q);
    }
    final pool = byId.values.toList();
    _poolSize = pool.length;

    var unseen = pool.where((q) => !seen.contains(q.id)).toList();
    // Only recycle after the entire bank has been used (takes longer as bank grows).
    if (unseen.isEmpty) {
      seen.clear();
      unseen = List<GameQuestion>.from(pool);
    }
    unseen.shuffle(kidGameRand);

    final take = min(_sessionSize, unseen.length);
    final selected = unseen.take(take).toList();
    seen.addAll(selected.map((q) => q.id));
    final poolIds = pool.map((q) => q.id).toSet();
    seen.removeWhere((id) => !poolIds.contains(id));
    await prefs.setStringList(_seenKey, seen);

    final leaf = await KindLeafProgress.leafLevel(widget.gameId);

    if (!mounted) return;
    setState(() {
      _questions = selected;
      _index = 0;
      _score = 0;
      _selected = null;
      _answered = false;
      _finished = false;
      _leafResult = null;
      _leafLevel = leaf;
      _ready = true;
    });
    _maybeSpeak();
  }

  /// Speak the target word (Spelling Bee) or the full question text.
  String _speakText(GameQuestion q) {
    if (q.speakWord != null && q.speakWord!.trim().isNotEmpty) {
      return q.speakWord!.trim();
    }
    return q.prompt
        .replaceAll('\n', '. ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _maybeSpeak() async {
    if (!_ready || _index >= _questions.length) return;
    final text = _speakText(_questions[_index]);
    if (text.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  void _pick(int i) {
    if (_answered) return;
    setState(() {
      _selected = i;
      _answered = true;
      if (i == _questions[_index].correct) _score++;
    });
  }

  Future<void> _next() async {
    if (_index + 1 >= _questions.length) {
      final result = await KindLeafProgress.recordSession(
        gameId: widget.gameId,
        score: _score,
      );
      if (!mounted) return;
      setState(() {
        _finished = true;
        _leafResult = result;
        _leafLevel = result.currentLeaf;
      });
      return;
    }
    setState(() {
      _index++;
      _selected = null;
      _answered = false;
    });
    _maybeSpeak();
  }

  void _restart() {
    setState(() => _ready = false);
    _prepareSession();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.gradient.first;
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: !_ready
                  ? Center(
                      child:
                          CircularProgressIndicator(color: context.accentColor))
                  : _questions.isEmpty
                      ? Center(
                          child: Text('No questions available.',
                              style: TextStyle(color: context.greyColor)))
                      : _finished
                          ? _resultView(context, accent)
                          : _questionView(context, accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final accent = widget.gradient.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: Icon(Icons.arrow_back_rounded, color: context.textColor),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _poolSize > 0
                      ? '$_poolSize questions in bank · Leaf $_leafLevel'
                      : 'Leaf $_leafLevel',
                  style: TextStyle(color: context.greyColor, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.eco_rounded, size: 16, color: accent),
                const SizedBox(width: 4),
                Text(
                  'Leaf $_leafLevel',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionView(BuildContext context, Color accent) {
    final q = _questions[_index];
    final progress = (_index + 1) / _questions.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          children: [
            Text(
              'Question ${_index + 1} of ${_questions.length}',
              style: TextStyle(color: context.greyColor, fontSize: 13),
            ),
            const Spacer(),
            Icon(Icons.star_rounded, color: accent, size: 18),
            const SizedBox(width: 4),
            Text(
              '$_score',
              style: TextStyle(
                color: context.textColor,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: accent.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(widget.icon, color: Colors.white.withOpacity(0.9), size: 30),
              const SizedBox(height: 14),
              Text(
                q.prompt,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _maybeSpeak,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.volume_up_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text('Hear question',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ...List.generate(q.options.length, (i) => _optionTile(context, q, i)),
        if (_answered) ...[
          const SizedBox(height: 12),
          Text(
            _selected == q.correct ? '🎉 Correct! Great job!' : '💡 Good try!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _selected == q.correct
                  ? const Color(0xFF22C55E)
                  : context.greyColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _index + 1 >= _questions.length ? 'See my score' : 'Next',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _optionTile(BuildContext context, GameQuestion q, int i) {
    final isCorrect = i == q.correct;
    final isSelected = i == _selected;
    Color bg = context.cardColor;
    Color border = context.borderColor;
    Color fg = context.textColor;
    IconData? trailing;

    if (_answered) {
      if (isCorrect) {
        bg = const Color(0xFF22C55E).withOpacity(0.15);
        border = const Color(0xFF22C55E);
        fg = const Color(0xFF16A34A);
        trailing = Icons.check_circle_rounded;
      } else if (isSelected) {
        bg = const Color(0xFFEF4444).withOpacity(0.12);
        border = const Color(0xFFEF4444);
        fg = const Color(0xFFDC2626);
        trailing = Icons.cancel_rounded;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _pick(i),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    q.options[i],
                    style: TextStyle(
                      color: fg,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) Icon(trailing, color: border, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultView(BuildContext context, Color accent) {
    final total = _questions.length;
    final pct = total == 0 ? 0 : (_score / total * 100).round();
    final stars = pct >= 80 ? 3 : (pct >= 50 ? 2 : 1);
    final message = pct >= 80
        ? 'Amazing! You are a star! 🌟'
        : pct >= 50
            ? 'Well done! Keep practicing! 👏'
            : 'Good try! Play again to improve! 💪';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const SizedBox(height: 20),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              3,
              (i) => Icon(
                Icons.star_rounded,
                size: 44,
                color: i < stars ? const Color(0xFFF59E0B) : context.borderColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: widget.gradient),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              const Text(
                'Your Score',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                '$_score / $total',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Fresh questions until the whole bank is used!',
            style: TextStyle(color: context.greyColor, fontSize: 12.5),
          ),
        ),
        if (_leafResult != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.eco_rounded, color: accent, size: 28),
                    const SizedBox(width: 8),
                    Text(
                      _leafResult!.newlyUnlocked
                          ? 'Unlocked Leaf ${_leafResult!.currentLeaf}!'
                          : 'Leaf ${_leafResult!.currentLeaf}',
                      style: TextStyle(
                        color: context.textColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _leafResult!.newlyUnlocked
                      ? 'A new leaf grew from your play!'
                      : 'Get ${KindLeafProgress.correctsPerLeaf} correct answers to unlock the next leaf.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.greyColor, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: KindLeafProgress.progressToNext(
                        _leafResult!.totalCorrect),
                    minHeight: 10,
                    backgroundColor: context.borderColor,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_leafResult!.totalCorrect} correct lifetime · $_poolSize in bank',
                  style: TextStyle(color: context.greyColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.refresh_rounded),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            label: const Text('Play again',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.textColor,
              side: BorderSide(color: context.borderColor),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Back to games',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }
}

// ── Game catalog ──────────────────────────────────────────────────────────────

class KidGame {
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final List<GameQuestion> Function() builder;

  const KidGame({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.builder,
  });
}

const _kGames = <KidGame>[
  KidGame(
    id: 'spelling-bee',
    icon: Icons.spellcheck_rounded,
    title: 'Spelling Bee',
    subtitle: 'Practice spelling fun words.',
    gradient: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
    builder: buildSpellingBee,
  ),
  KidGame(
    id: 'math-challenge',
    icon: Icons.calculate_rounded,
    title: 'Math Challenge',
    subtitle: 'Quick number puzzles.',
    gradient: [Color(0xFF6366F1), Color(0xFF818CF8)],
    builder: buildMathChallenge,
  ),
  KidGame(
    id: 'counting-fun',
    icon: Icons.filter_9_plus_rounded,
    title: 'Counting Fun',
    subtitle: 'Count the objects.',
    gradient: [Color(0xFFEC4899), Color(0xFFF472B6)],
    builder: buildCountingFun,
  ),
  KidGame(
    id: 'word-builder',
    icon: Icons.menu_book_rounded,
    title: 'Word Builder',
    subtitle: 'Learn new vocabulary.',
    gradient: [Color(0xFF10B981), Color(0xFF34D399)],
    builder: buildWordBuilder,
  ),
  KidGame(
    id: 'abc-phonics',
    icon: Icons.abc_rounded,
    title: 'ABC Phonics',
    subtitle: 'Letters & sounds.',
    gradient: [Color(0xFF14B8A6), Color(0xFF2DD4BF)],
    builder: buildAbcPhonics,
  ),
  KidGame(
    id: 'shapes-colors',
    icon: Icons.category_rounded,
    title: 'Shapes & Colors',
    subtitle: 'Spot shapes and colors.',
    gradient: [Color(0xFFF97316), Color(0xFFFB923C)],
    builder: buildShapesColors,
  ),
  KidGame(
    id: 'opposites',
    icon: Icons.swap_horiz_rounded,
    title: 'Opposites',
    subtitle: 'Find the opposite word.',
    gradient: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
    builder: buildOpposites,
  ),
  KidGame(
    id: 'rhyming-words',
    icon: Icons.music_note_rounded,
    title: 'Rhyming Words',
    subtitle: 'Match words that rhyme.',
    gradient: [Color(0xFFA855F7), Color(0xFFD946EF)],
    builder: buildRhyming,
  ),
  KidGame(
    id: 'fun-quiz',
    icon: Icons.quiz_rounded,
    title: 'Fun Quiz',
    subtitle: 'Questions on any topic.',
    gradient: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    builder: buildFunQuiz,
  ),
  KidGame(
    id: 'science-facts',
    icon: Icons.science_rounded,
    title: 'Science Facts',
    subtitle: 'Discover how things work.',
    gradient: [Color(0xFF06B6D4), Color(0xFF22D3EE)],
    builder: buildScienceFacts,
  ),
  KidGame(
    id: 'geography',
    icon: Icons.public_rounded,
    title: 'Geography',
    subtitle: 'Countries, flags & places.',
    gradient: [Color(0xFFEF4444), Color(0xFFF87171)],
    builder: buildGeography,
  ),
  KidGame(
    id: 'animals',
    icon: Icons.pets_rounded,
    title: 'Animals & Sounds',
    subtitle: 'Meet the animals.',
    gradient: [Color(0xFF84CC16), Color(0xFFA3E635)],
    builder: buildAnimals,
  ),
  KidGame(
    id: 'time-calendar',
    icon: Icons.schedule_rounded,
    title: 'Time & Calendar',
    subtitle: 'Days, months & clocks.',
    gradient: [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
    builder: buildTimeCalendar,
  ),
  KidGame(
    id: 'good-manners',
    icon: Icons.favorite_rounded,
    title: 'Good Manners',
    subtitle: 'Learn to be kind.',
    gradient: [Color(0xFFF43F5E), Color(0xFFFB7185)],
    builder: buildGoodManners,
  ),
  KidGame(
    id: 'my-body',
    icon: Icons.accessibility_new_rounded,
    title: 'My Body',
    subtitle: 'Body parts & health.',
    gradient: [Color(0xFF8B5CF6), Color(0xFFC084FC)],
    builder: buildMyBody,
  ),

  // ── Adventure pack (added alongside existing games) ──────────────────────
  KidGame(
    id: 'alphabet-adventure',
    icon: Icons.abc_rounded,
    title: 'Alphabet Adventure',
    subtitle: 'Match letters, find hidden ones & phonics.',
    gradient: [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
    builder: buildAlphabetAdventure,
  ),
  KidGame(
    id: 'number-kingdom',
    icon: Icons.looks_one_rounded,
    title: 'Number Kingdom',
    subtitle: 'Counting, +/−, multiply & math races.',
    gradient: [Color(0xFF7C3AED), Color(0xFFA78BFA)],
    builder: buildNumberKingdom,
  ),
  KidGame(
    id: 'word-builder-adventure',
    icon: Icons.font_download_rounded,
    title: 'Word Builder Lab',
    subtitle: 'Build words, spell gaps & picture match.',
    gradient: [Color(0xFF059669), Color(0xFF34D399)],
    builder: buildWordBuilderAdventure,
  ),
  KidGame(
    id: 'reading-adventure',
    icon: Icons.auto_stories_rounded,
    title: 'Reading Adventure',
    subtitle: 'Short stories, listen & comprehension.',
    gradient: [Color(0xFFDB2777), Color(0xFFF472B6)],
    builder: buildReadingAdventure,
  ),
  KidGame(
    id: 'science-explorer',
    icon: Icons.biotech_rounded,
    title: 'Science Explorer',
    subtitle: 'Body, plants, animals, weather & space.',
    gradient: [Color(0xFF0891B2), Color(0xFF22D3EE)],
    builder: buildScienceExplorer,
  ),
  KidGame(
    id: 'geography-explorer',
    icon: Icons.travel_explore_rounded,
    title: 'Geography Explorer',
    subtitle: 'Maps, flags, capitals & landmarks.',
    gradient: [Color(0xFFDC2626), Color(0xFFF87171)],
    builder: buildGeographyExplorer,
  ),
  KidGame(
    id: 'coding-for-kids',
    icon: Icons.smart_toy_rounded,
    title: 'Coding for Kids',
    subtitle: 'Blocks, logic & robot maze puzzles.',
    gradient: [Color(0xFF4F46E5), Color(0xFF818CF8)],
    builder: buildCodingForKids,
  ),
  KidGame(
    id: 'art-studio',
    icon: Icons.palette_rounded,
    title: 'Art Studio',
    subtitle: 'Colors, shapes, patterns & stickers.',
    gradient: [Color(0xFFEA580C), Color(0xFFFB923C)],
    builder: buildArtStudioQuiz,
  ),
  KidGame(
    id: 'music-academy',
    icon: Icons.library_music_rounded,
    title: 'Music Academy',
    subtitle: 'Notes, piano, rhythm & instruments.',
    gradient: [Color(0xFF9333EA), Color(0xFFC084FC)],
    builder: buildMusicAcademy,
  ),
  KidGame(
    id: 'memory-challenge',
    icon: Icons.psychology_rounded,
    title: 'Memory Challenge',
    subtitle: 'Sequences, cards & concentration.',
    gradient: [Color(0xFF2563EB), Color(0xFF60A5FA)],
    builder: buildMemoryChallengeQuiz,
  ),
  KidGame(
    id: 'puzzle-world',
    icon: Icons.extension_rounded,
    title: 'Puzzle World',
    subtitle: 'Jigsaw tips, shapes & logic puzzles.',
    gradient: [Color(0xFFCA8A04), Color(0xFFFACC15)],
    builder: buildPuzzleWorld,
  ),
  KidGame(
    id: 'quiz-battle',
    icon: Icons.sports_esports_rounded,
    title: 'Quiz Battle',
    subtitle: 'Timed mixed challenges & trophies.',
    gradient: [Color(0xFFBE123C), Color(0xFFFB7185)],
    builder: buildQuizBattle,
  ),
  KidGame(
    id: 'treasure-hunt',
    icon: Icons.vpn_key_rounded,
    title: 'Treasure Hunt',
    subtitle: 'Unlock chests, maps, badges & coins.',
    gradient: [Color(0xFFB45309), Color(0xFFFBBF24)],
    builder: buildTreasureHunt,
  ),
  KidGame(
    id: 'virtual-pet',
    icon: Icons.pets_rounded,
    title: 'Virtual Pet',
    subtitle: 'Grow your pet by finishing lessons.',
    gradient: [Color(0xFF16A34A), Color(0xFF4ADE80)],
    builder: buildVirtualPetQuiz,
  ),
  KidGame(
    id: 'school-city-builder',
    icon: Icons.location_city_rounded,
    title: 'School City Builder',
    subtitle: 'Earn coins from lessons & quizzes.',
    gradient: [Color(0xFF0F766E), Color(0xFF2DD4BF)],
    builder: buildSchoolCityBuilder,
  ),
];

List<KidGame> get kidGames => _kGames;
