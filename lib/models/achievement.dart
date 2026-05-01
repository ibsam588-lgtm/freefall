// models/achievement.dart
//
// Phase 10 achievement catalog data model. Each Achievement is a stable
// id + display copy + a target value the player has to hit, along with
// a tag describing which lifetime/run counter feeds its progress. The
// AchievementManager reads [type] to know where to pull the current
// value from when computing 0..1 progress.
//
// Pure data — no Flame, no Flutter. Equality comparable so tests can
// build expected values inline.

/// Counter feeds for achievement progress. Keep these as a closed set
/// so the manager can switch over them exhaustively.
enum AchievementType {
  /// Lifetime depth fallen, in meters (StatsRepository.totalDepth/highDepth
  /// is per-run; we use the cumulative aggregate the manager keeps).
  totalDepth,

  /// Single-run depth in meters — read off RunStats.depthMeters.
  singleRunDepth,

  /// Highest combo reached on a single run.
  comboReached,

  /// Combo reached at any point during a run (in-run event).
  comboInRun,

  /// Gems collected in one run.
  gemsInRun,

  /// First skin purchased — boolean flag.
  firstSkinBought,

  /// Any powerup upgrade reached its max level.
  upgradeMaxed,

  /// Player descended deep enough to hit the Core zone.
  reachedCore,

  /// Lifetime deaths to lightning.
  lightningDeaths,

  /// Lifetime deaths to a jellyfish stun aftermath.
  jellyfishDeaths,

  /// Lifetime deaths to a lava jet.
  lavaDeaths,

  /// Lifetime coins earned.
  lifetimeCoins,

  /// Lifetime near-misses.
  nearMissesTotal,

  /// Speed gates passed in one run.
  speedGatesInRun,

  /// Consecutive daily login days.
  consecutiveDays,

  /// Survived all 5 zones in a single run.
  allZonesInRun,

  /// Completed any zone without being hit (per-run event).
  zoneCompleteNoHit,
}

/// One row in the achievement catalog. The id is stable forever — used
/// as a SharedPreferences key — so renaming it is a breaking change.
class Achievement {
  /// Stable storage id. Lowercase snake_case.
  final String id;

  /// Player-facing title.
  final String title;

  /// One-line player-facing description.
  final String description;

  /// Threshold the underlying counter has to reach for [id] to unlock.
  /// For boolean-ish achievements (firstSkinBought, upgradeMaxed,
  /// reachedCore, allZonesInRun, zoneCompleteNoHit) the target is 1.
  final int targetValue;

  /// Which feed populates progress for this achievement.
  final AchievementType type;

  /// Coin reward granted on unlock. Defaults to 0 (Phase-10 ships every
  /// achievement at 0; future phases can opt in per-row).
  final int coinReward;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.targetValue,
    required this.type,
    this.coinReward = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is Achievement &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.targetValue == targetValue &&
      other.type == type &&
      other.coinReward == coinReward;

  @override
  int get hashCode =>
      Object.hash(id, title, description, targetValue, type, coinReward);

  @override
  String toString() =>
      'Achievement(id=$id, target=$targetValue, type=${type.name})';
}
