import 'dart:math';

/// Runs levels 1–30 with no repeated question indices in one play-through.
class GameSessionQueue {
  static const int maxLevels = 30;

  final List<int> _order;
  int _index = 0;

  GameSessionQueue({
    required int poolSize,
    Random? rng,
  }) : _order = _buildOrder(poolSize, rng ?? Random()) {
    assert(poolSize >= maxLevels,
        'Question pool must have at least $maxLevels items');
  }

  static List<int> _buildOrder(int poolSize, Random rng) {
    final all = List<int>.generate(poolSize, (i) => i)..shuffle(rng);
    return all.take(maxLevels).toList();
  }

  /// Current level number (1–30).
  int get level => _index + 1;

  /// Levels completed so far.
  int get completed => _index;

  bool get isFinished => _index >= maxLevels;

  /// Returns the next pool index, or null when all 30 levels are done.
  int? nextIndex() {
    if (isFinished) return null;
    return _order[_index++];
  }

  void reset({required int poolSize, Random? rng}) {
    final fresh = _buildOrder(poolSize, rng ?? Random());
    _order
      ..clear()
      ..addAll(fresh);
    _index = 0;
  }
}
