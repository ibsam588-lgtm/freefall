// repositories/daily_login_repository.dart
//
// Tracks the daily-login streak and awards a coin bonus on each
// claim. State machine:
//   * If today's date != last login date → claim is available.
//   * If gap is 0 days → already claimed today, claim is rejected.
//   * If gap is exactly 1 day → streak advances by one (with wrap at 7).
//   * If gap is >1 day → streak resets to Day 1.
//
// The repository ONLY tracks the streak; awarding the coins to the
// player's balance is the caller's job (so daily-login can compose
// with ad-reward / IAP coin grants without circular deps).
//
// Persistence is via the same `StatsStorage` shape we use for run
// stats — int + string IO. We extend it minimally with a `getString`
// hook so the last login date can be persisted as ISO-8601.

import 'package:shared_preferences/shared_preferences.dart';

import '../models/daily_login_bonus.dart';

/// Storage abstraction shared by daily-login + ad-reward + settings —
/// anything that needs both ints and strings out of SharedPreferences.
abstract class LoginStorage {
  Future<int> getInt(String key, {int fallback = 0});
  Future<void> setInt(String key, int value);
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

/// SharedPreferences adapter. Caches the SharedPreferences instance so
/// concurrent reads share one getInstance call. Production default.
class SharedPreferencesLoginStorage implements LoginStorage {
  Future<SharedPreferences>? _instance;
  Future<SharedPreferences> _prefs() =>
      _instance ??= SharedPreferences.getInstance();

  @override
  Future<int> getInt(String key, {int fallback = 0}) async {
    final prefs = await _prefs();
    return prefs.getInt(key) ?? fallback;
  }

  @override
  Future<void> setInt(String key, int value) async {
    final prefs = await _prefs();
    await prefs.setInt(key, value);
  }

  @override
  Future<String?> getString(String key) async {
    final prefs = await _prefs();
    return prefs.getString(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    final prefs = await _prefs();
    await prefs.setString(key, value);
  }
}

/// In-memory implementation for tests + headless contexts.
class InMemoryLoginStorage implements LoginStorage {
  final Map<String, int> _ints = {};
  final Map<String, String> _strings = {};

  @override
  Future<int> getInt(String key, {int fallback = 0}) async =>
      _ints[key] ?? fallback;

  @override
  Future<void> setInt(String key, int value) async {
    _ints[key] = value;
  }

  @override
  Future<String?> getString(String key) async => _strings[key];

  @override
  Future<void> setString(String key, String value) async {
    _strings[key] = value;
  }

  /// Test helper.
  void seed({String? lastLogin, int? consecutiveDays}) {
    if (lastLogin != null) _strings['last_login_date'] = lastLogin;
    if (consecutiveDays != null) {
      _ints['consecutive_login_days'] = consecutiveDays;
    }
  }
}

/// Outcome of a [DailyLoginRepository.recordLogin] call. Returned to
/// the screen so it can render either "Claimed +N!" or
/// "Already claimed today".
class DailyLoginResult {
  /// Coins to award (0 if already claimed today).
  final int coins;

  /// 1-indexed day in the streak after the claim landed (1..7). Equal
  /// to the previous value if [coins] is 0.
  final int day;

  /// True iff the claim actually credited a bonus this call.
  final bool claimed;

  const DailyLoginResult({
    required this.coins,
    required this.day,
    required this.claimed,
  });
}

class DailyLoginRepository {
  static const String lastLoginKey = 'last_login_date';
  static const String streakKey = 'consecutive_login_days';

  final LoginStorage storage;

  /// Override clock for testing — defaults to [DateTime.now].
  final DateTime Function() now;

  DailyLoginRepository({
    LoginStorage? storage,
    DateTime Function()? now,
  })  : storage = storage ?? SharedPreferencesLoginStorage(),
        now = now ?? DateTime.now;

  /// Last claimed login date (date-only — local midnight). Null if
  /// the user has never claimed.
  Future<DateTime?> getLastLoginDate() async {
    final raw = await storage.getString(lastLoginKey);
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    // Strip time-of-day to keep the comparison day-aligned.
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// Current streak length. 0 if the user has never claimed.
  Future<int> getConsecutiveDays() => storage.getInt(streakKey);

  /// Coins that *would* be awarded if the user claimed right now.
  /// Returns 0 if already claimed today.
  Future<int> getPendingReward() async {
    if (!await isClaimAvailable()) return 0;
    final nextDay = await _peekNextDay();
    return DailyLoginBonus.forDay(nextDay);
  }

  /// True iff the user can claim today (date has changed since the
  /// last claim). False if they already claimed today.
  Future<bool> isClaimAvailable() async {
    final last = await getLastLoginDate();
    if (last == null) return true;
    final today = _today();
    return today.isAfter(last);
  }

  /// Claim today's bonus, returning the [DailyLoginResult].
  ///
  /// Rules:
  ///   * First-ever claim → Day 1.
  ///   * Same day as last claim → no-op, [DailyLoginResult.claimed] is false.
  ///   * Exactly 1 day later → streak advances by one (wraps Day 7 → Day 1).
  ///   * Gap > 1 day → streak resets to Day 1.
  Future<DailyLoginResult> recordLogin() async {
    final today = _today();
    final last = await getLastLoginDate();
    final prevStreak = await getConsecutiveDays();

    if (last != null && !today.isAfter(last)) {
      // Already claimed today (or, defensively, last login is in the
      // future — treat as already claimed).
      return DailyLoginResult(
        coins: 0,
        day: prevStreak == 0 ? 1 : prevStreak,
        claimed: false,
      );
    }

    final newDay = _resolveNextDay(prevStreak: prevStreak, last: last, today: today);
    final coins = DailyLoginBonus.forDay(newDay);

    await storage.setInt(streakKey, newDay);
    await storage.setString(
      lastLoginKey,
      // Store as ISO date (YYYY-MM-DD) so future readers don't have
      // to handle stray time-of-day components.
      _formatDate(today),
    );

    return DailyLoginResult(coins: coins, day: newDay, claimed: true);
  }

  // --------- internals ------------------------------------------------------

  DateTime _today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }

  /// What day will be claimed *next*, without mutating storage. Used
  /// by [getPendingReward] so the UI can preview the reward.
  Future<int> _peekNextDay() async {
    final last = await getLastLoginDate();
    final prevStreak = await getConsecutiveDays();
    return _resolveNextDay(
      prevStreak: prevStreak,
      last: last,
      today: _today(),
    );
  }

  int _resolveNextDay({
    required int prevStreak,
    required DateTime? last,
    required DateTime today,
  }) {
    if (last == null || prevStreak <= 0) return 1;
    final diff = today.difference(last).inDays;
    if (diff == 1) {
      // Continued streak. Wrap Day 7 → Day 1.
      return prevStreak >= DailyLoginBonus.cycleLength ? 1 : prevStreak + 1;
    }
    // diff > 1 → missed at least one day → reset.
    return 1;
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
