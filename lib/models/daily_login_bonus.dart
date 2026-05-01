// models/daily_login_bonus.dart
//
// Pure-data lookup for the 7-day daily-login bonus ladder. Day 8 wraps
// back to Day 1, so [forDay] clamps the input into the valid range.
//
// Engine-agnostic — no Flutter, no platform deps. The repository
// owns the streak state machine; this class is just the table.

class DailyLoginBonus {
  /// Coin reward per consecutive login day. Index 0 == Day 1.
  static const List<int> bonusCoins = [50, 100, 150, 200, 300, 500, 1000];

  /// Length of the bonus cycle. After Day 7, the next claim is Day 1.
  static const int cycleLength = 7;

  /// Coins to award for a 1-indexed [day]. Negative or zero days are
  /// treated as Day 1; days past the cycle clamp to Day 7.
  static int forDay(int day) => bonusCoins[(day - 1).clamp(0, cycleLength - 1)];
}
