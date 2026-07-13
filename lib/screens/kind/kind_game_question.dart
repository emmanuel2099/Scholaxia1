class GameQuestion {
  final String prompt;
  final List<String> options;
  final int correct;

  /// Stable identifier used to remember which questions were already shown.
  final String? qid;

  /// If set, a speaker button prefers reading this word aloud (Spelling Bee).
  final String? speakWord;

  const GameQuestion({
    required this.prompt,
    required this.options,
    required this.correct,
    this.qid,
    this.speakWord,
  });

  String get id => qid ?? prompt;
}
