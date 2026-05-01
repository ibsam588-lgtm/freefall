// repositories/ad_reward_repository.dart
//
// Tracks how many rewarded ads the player has watched today (max 5).
// Counter resets at local midnight: a new calendar day means a fresh
// 5-reward budget.
//
// State stored:
//   ad_reward_date    — ISO date (YYYY-MM-DD) of the last reset
//   ad_rewards_today  — int, count of rewards already credited today
//
// The repository does NOT credit coins — the caller (ad service)
// reads `getCoinsForAdReward` and pushes the value into CoinRepository
// itself. Same separation-of-concerns rule as DailyLoginRepository.

import 'daily_login_repository.dart';

class AdRewardRepository {
  /// Hard daily cap. Set deliberately low — rewarded ads are a
  /// monetization lever, not a primary economy source.
  static const int dailyLimit = 5;

  /// Coin reward per rewarded-ad view.
  static const int coinsPerReward = 200;

  static const String dateKey = 'ad_reward_date';
  static const String countKey = 'ad_rewards_today';

  final LoginStorage storage;
  final DateTime Function() now;

  AdRewardRepository({
    LoginStorage? storage,
    DateTime Function()? now,
  })  : storage = storage ?? SharedPreferencesLoginStorage(),
        now = now ?? DateTime.now;

  /// How many rewards remain in today's budget. 0..[dailyLimit].
  Future<int> getRemainingAdRewards() async {
    await _maybeRollOver();
    final used = await storage.getInt(countKey);
    final left = dailyLimit - used;
    if (left < 0) return 0;
    return left;
  }

  /// Flat per-reward coin value. Constant for the whole phase; future
  /// phases may replace with a tier table.
  int getCoinsForAdReward() => coinsPerReward;

  /// True iff the player still has a rewarded ad available today.
  Future<bool> canRewardToday() async => (await getRemainingAdRewards()) > 0;

  /// Increment today's count by one. Returns false (and is a no-op on
  /// storage) if the daily cap is already hit.
  Future<bool> recordAdReward() async {
    await _maybeRollOver();
    final used = await storage.getInt(countKey);
    if (used >= dailyLimit) return false;
    await storage.setInt(countKey, used + 1);
    return true;
  }

  /// If the persisted date is older than today, reset the counter to 0
  /// and bump the date. Idempotent — fine to call on every read.
  Future<void> _maybeRollOver() async {
    final today = _today();
    final last = await storage.getString(dateKey);
    if (last == _formatDate(today)) return;
    await storage.setString(dateKey, _formatDate(today));
    await storage.setInt(countKey, 0);
  }

  DateTime _today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
