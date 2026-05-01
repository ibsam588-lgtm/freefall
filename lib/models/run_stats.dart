// models/run_stats.dart
//
// Snapshot of a single completed run. Built by the host at the moment
// of death (or quit), handed to the run summary screen for display
// and to StatsRepository for persistence + lifetime aggregation.
//
// Pure data — no Flame, no Flutter. Equality comparable so tests
// can build expected values inline.

class RunStats {
  /// Final score for the run.
  final int score;

  /// Maximum depth (in meters) reached.
  final double depthMeters;

  /// Coins picked up this run (already adjusted by any coin multiplier).
  final int coinsEarned;

  /// Gems picked up this run.
  final int gemsCollected;

  /// Total near-miss events this run.
  final int nearMisses;

  /// Highest combo count reached during the run.
  final int bestCombo;

  /// True iff [score] beat the previous all-time high. The summary
  /// screen reads this to decide whether to play the "NEW BEST!" sting.
  final bool isNewHighScore;

  const RunStats({
    required this.score,
    required this.depthMeters,
    required this.coinsEarned,
    required this.gemsCollected,
    required this.nearMisses,
    required this.bestCombo,
    required this.isNewHighScore,
  });

  /// Convenience for tests.
  static const RunStats empty = RunStats(
    score: 0,
    depthMeters: 0,
    coinsEarned: 0,
    gemsCollected: 0,
    nearMisses: 0,
    bestCombo: 0,
    isNewHighScore: false,
  );

  RunStats copyWith({
    int? score,
    double? depthMeters,
    int? coinsEarned,
    int? gemsCollected,
    int? nearMisses,
    int? bestCombo,
    bool? isNewHighScore,
  }) {
    return RunStats(
      score: score ?? this.score,
      depthMeters: depthMeters ?? this.depthMeters,
      coinsEarned: coinsEarned ?? this.coinsEarned,
      gemsCollected: gemsCollected ?? this.gemsCollected,
      nearMisses: nearMisses ?? this.nearMisses,
      bestCombo: bestCombo ?? this.bestCombo,
      isNewHighScore: isNewHighScore ?? this.isNewHighScore,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RunStats &&
        other.score == score &&
        other.depthMeters == depthMeters &&
        other.coinsEarned == coinsEarned &&
        other.gemsCollected == gemsCollected &&
        other.nearMisses == nearMisses &&
        other.bestCombo == bestCombo &&
        other.isNewHighScore == isNewHighScore;
  }

  @override
  int get hashCode => Object.hash(score, depthMeters, coinsEarned,
      gemsCollected, nearMisses, bestCombo, isNewHighScore);

  @override
  String toString() =>
      'RunStats(score=$score, depth=${depthMeters.toStringAsFixed(1)}m, '
      'coins=$coinsEarned, gems=$gemsCollected, nearMisses=$nearMisses, '
      'bestCombo=$bestCombo, newHigh=$isNewHighScore)';
}
