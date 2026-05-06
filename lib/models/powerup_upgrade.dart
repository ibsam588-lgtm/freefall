// models/powerup_upgrade.dart
//
// Persistent power-up upgrades the player buys with coins. Each
// upgrade has 3 levels; level 0 means "not bought yet". The store
// surfaces the cost of the *next* level and the resulting effect
// value so the player can compare.
//
// Pure data — StoreRepository owns the per-level state machine,
// gameplay systems read [valueAtLevel] to apply the effect.

enum PowerupUpgradeId {
  magnetRange,
  shieldDuration,
  slowMoDuration,
  scoreMultiplier,
  coinMultiplier,
  extraStartingLife,
  luckyDrop,
}

class PowerupUpgrade {
  final PowerupUpgradeId id;
  final String name;
  final String description;

  /// Coin cost per level. Index 0 == cost to go from level 0 → 1.
  /// Length == [maxLevel].
  final List<int> costPerLevel;

  /// Effect value at each level. Index 0 == base (level 0); index 1 ==
  /// level 1 effect; etc. Length == [maxLevel] + 1.
  final List<double> valuePerLevel;

  /// Human-readable suffix attached to the value when displayed.
  /// Example: 'px', 's', 'x', '%'.
  final String unit;

  /// Hard cap. Phase-8 ships every upgrade at 3 levels; the field
  /// stays explicit so future tiers can add more without code churn.
  final int maxLevel;

  const PowerupUpgrade({
    required this.id,
    required this.name,
    required this.description,
    required this.costPerLevel,
    required this.valuePerLevel,
    required this.unit,
    this.maxLevel = 3,
  });

  /// Cost of going from [currentLevel] to [currentLevel] + 1. Returns 0
  /// if already at max — caller should treat that as "no more levels".
  int costForNextLevel(int currentLevel) {
    if (currentLevel >= maxLevel) return 0;
    return costPerLevel[currentLevel];
  }

  /// Effect value at [level]. Clamped into [0..maxLevel] so callers
  /// don't have to bounds-check.
  double valueAtLevel(int level) =>
      valuePerLevel[level.clamp(0, maxLevel)];

  /// Default-locked catalog. Every upgrade starts at level 0 in
  /// StoreRepository — the entries below describe how each level moves
  /// the underlying gameplay number.
  ///
  /// Pricing: every level fits under the 200-coin store ceiling. We
  /// keep a flat 100 / 150 / 200 ramp across all upgrades so a player
  /// can plan around a known budget rather than tier-chasing the
  /// expensive ones. The effect values are unchanged — only the cost
  /// curve was flattened.
  static const List<PowerupUpgrade> catalog = [
    PowerupUpgrade(
      id: PowerupUpgradeId.magnetRange,
      name: 'Magnet Range',
      description: 'Larger pickup radius when the magnet powerup is active.',
      costPerLevel: [100, 150, 200],
      // Base 150px (slightly under the 200px Phase-5 default so level 1
      // is a real upgrade, not a sidegrade).
      valuePerLevel: [150, 200, 250, 300],
      unit: 'px',
    ),
    PowerupUpgrade(
      id: PowerupUpgradeId.shieldDuration,
      name: 'Shield Duration',
      description: 'Shield i-frames last longer per hit.',
      costPerLevel: [100, 150, 200],
      // Base 2s (the Phase-4 i-frame default), +1s/level.
      valuePerLevel: [2.0, 3.0, 4.0, 5.0],
      unit: 's',
    ),
    PowerupUpgrade(
      id: PowerupUpgradeId.slowMoDuration,
      name: 'Slow-Mo Duration',
      description: 'Slow-mo lasts longer once activated.',
      costPerLevel: [100, 150, 200],
      // Base 5s (Phase-5 default), +1.5s/level.
      valuePerLevel: [5.0, 6.5, 8.0, 9.5],
      unit: 's',
    ),
    PowerupUpgrade(
      id: PowerupUpgradeId.scoreMultiplier,
      name: 'Score Multiplier',
      description: 'Higher score multiplier on every run.',
      costPerLevel: [100, 150, 200],
      // Base 1.0×, +0.2/level.
      valuePerLevel: [1.0, 1.2, 1.4, 1.6],
      unit: 'x',
    ),
    PowerupUpgrade(
      id: PowerupUpgradeId.coinMultiplier,
      name: 'Coin Multiplier',
      description: 'Higher coin multiplier on every run.',
      costPerLevel: [100, 150, 200],
      valuePerLevel: [1.0, 1.2, 1.4, 1.6],
      unit: 'x',
    ),
    PowerupUpgrade(
      id: PowerupUpgradeId.extraStartingLife,
      name: 'Extra Starting Life',
      description: 'Begin each run with extra lives.',
      costPerLevel: [100, 150, 200],
      // Whole-number bonus lives. Player.absoluteMaxLives is 4 so the
      // upgrade caps at +1 base life worth — Phase 8 grants the bonus
      // through the regular life pipeline (capped at the absolute max).
      valuePerLevel: [0, 1, 2, 3],
      unit: ' lives',
    ),
    PowerupUpgrade(
      id: PowerupUpgradeId.luckyDrop,
      name: 'Lucky Drop',
      description: 'Higher gem spawn rate while you fall.',
      costPerLevel: [100, 150, 200],
      // Base spawn-rate scalar 1.0 (gems land at the Phase-5 default).
      valuePerLevel: [1.0, 1.25, 1.5, 2.0],
      unit: 'x gems',
    ),
  ];

  static PowerupUpgrade byId(PowerupUpgradeId id) =>
      catalog.firstWhere((u) => u.id == id);
}
