import 'package:shared_preferences/shared_preferences.dart';

/// Leaf unlock progression for kids games.
/// Leaf 1 starts unlocked. Earn correct answers → unlock Leaf 2, 3, …
class KindLeafProgress {
  KindLeafProgress._();

  static const maxLeaf = 30;
  /// Correct answers needed to unlock each next leaf.
  static const correctsPerLeaf = 20;

  static String _correctKey(String gameId) => 'kidgame_correct_$gameId';
  static String _sessionsKey(String gameId) => 'kidgame_sessions_$gameId';

  static Future<int> totalCorrect(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_correctKey(gameId)) ?? 0;
  }

  static Future<int> sessionsDone(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_sessionsKey(gameId)) ?? 0;
  }

  /// Current unlocked leaf (1–30).
  static int leafLevelFromCorrect(int totalCorrect) {
    final level = 1 + (totalCorrect ~/ correctsPerLeaf);
    return level.clamp(1, maxLeaf);
  }

  static Future<int> leafLevel(String gameId) async {
    return leafLevelFromCorrect(await totalCorrect(gameId));
  }

  /// Progress toward the next leaf (0.0–1.0). At max leaf → 1.0.
  static double progressToNext(int totalCorrect) {
    final level = leafLevelFromCorrect(totalCorrect);
    if (level >= maxLeaf) return 1;
    final into = totalCorrect % correctsPerLeaf;
    return into / correctsPerLeaf;
  }

  static Future<LeafUnlockResult> recordSession({
    required String gameId,
    required int score,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getInt(_correctKey(gameId)) ?? 0;
    final sessions = prefs.getInt(_sessionsKey(gameId)) ?? 0;
    final after = before + score;
    await prefs.setInt(_correctKey(gameId), after);
    await prefs.setInt(_sessionsKey(gameId), sessions + 1);

    final oldLeaf = leafLevelFromCorrect(before);
    final newLeaf = leafLevelFromCorrect(after);
    return LeafUnlockResult(
      totalCorrect: after,
      sessionsDone: sessions + 1,
      previousLeaf: oldLeaf,
      currentLeaf: newLeaf,
      newlyUnlocked: newLeaf > oldLeaf,
    );
  }
}

class LeafUnlockResult {
  final int totalCorrect;
  final int sessionsDone;
  final int previousLeaf;
  final int currentLeaf;
  final bool newlyUnlocked;

  const LeafUnlockResult({
    required this.totalCorrect,
    required this.sessionsDone,
    required this.previousLeaf,
    required this.currentLeaf,
    required this.newlyUnlocked,
  });
}
