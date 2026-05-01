// models/collectible.dart
//
// Pure-data taxonomy for Phase-5 collectibles. Three flavors:
//  * coins (4 tiers, 1/5/25/100 value),
//  * gems (3 tiers, 1/5/25 value, also boosts score),
//  * powerups (6 effect kinds, durations vary).
//
// Engine-agnostic on purpose — no Flame, no Flutter — so the values
// table can be unit-tested directly and re-used by the HUD, the
// spawner, and the run-summary screen without wiring any of them up.

enum CoinType { bronze, silver, gold, diamond }

enum GemType { bronze, silver, gold }

enum PowerupType {
  shield,
  magnet,
  slowMo,
  scoreMultiplier,
  coinMultiplier,
  extraLife,
}

/// Coin denomination → currency value table.
class CoinValue {
  static int forType(CoinType t) => switch (t) {
        CoinType.bronze => 1,
        CoinType.silver => 5,
        CoinType.gold => 25,
        CoinType.diamond => 100,
      };
}

/// Gem denomination → currency value table. Gems also award score
/// directly, but the score amount is the same as the coin value
/// (scoring is layered on top of currency).
class GemValue {
  static int forType(GemType t) => switch (t) {
        GemType.bronze => 1,
        GemType.silver => 5,
        GemType.gold => 25,
      };
}

/// Default lifetime of each powerup effect. extraLife is instant —
/// it adds a life and immediately ends, so its duration is 0.
class PowerupDuration {
  static const double shieldSeconds = double.infinity;
  static const double magnetSeconds = 10;
  static const double slowMoSeconds = 5;
  static const double scoreMultiplierSeconds = 15;
  static const double coinMultiplierSeconds = 15;
  static const double extraLifeSeconds = 0;

  static double forType(PowerupType t) => switch (t) {
        // Shield is consumed on the next hit, not on a timer. The manager
        // still tracks "active" so the player visual can read it; the
        // duration here is "until consumed", expressed as +inf.
        PowerupType.shield => shieldSeconds,
        PowerupType.magnet => magnetSeconds,
        PowerupType.slowMo => slowMoSeconds,
        PowerupType.scoreMultiplier => scoreMultiplierSeconds,
        PowerupType.coinMultiplier => coinMultiplierSeconds,
        PowerupType.extraLife => extraLifeSeconds,
      };
}
