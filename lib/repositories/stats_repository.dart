// repositories/stats_repository.dart
//
// Persists lifetime stats across runs. Backed by SharedPreferences in
// production; tests inject an in-memory implementation.
//
// Stored keys:
//   high_score              int — best run score ever
//   high_depth              int — deepest run, in meters (rounded)
//   total_coins             int — every coin ever collected
//   total_gems              int — every gem ever collected
//   total_near_misses       int — every near-miss ever
//   total_games_played      int — number of completed runs
//
// updateAfterRun(stats) atomically bumps each counter and returns
// the resolved (post-update) snapshot so the caller can drive the
// "NEW BEST!" callout off the same numbers it just persisted.

import 'package:shared_preferences/shared_preferences.dart';

import '../models/run_stats.dart';

/// Minimal abstraction over the shared_preferences key/value store.
abstract class StatsStorage {
  Future<int> getInt(String key, {int fallback = 0});
  Future<void> setInt(String key, int value);
}

class SharedPreferencesStatsStorage implements StatsStorage {
  /// Cached future so concurrent reads share the same getInstance call.
  Future<SharedPreferences>? _instance;

  Future<SharedPreferences> _prefs() => _instance ??= SharedPreferences.getInstance();

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
}

/// In-memory stats storage for unit tests + headless contexts.
class InMemoryStatsStorage implements StatsStorage {
  final Map<String, int> _data = {};

  @override
  Future<int> getInt(String key, {int fallback = 0}) async =>
      _data[key] ?? fallback;

  @override
  Future<void> setInt(String key, int value) async {
    _data[key] = value;
  }

  /// Test helper.
  void seed(String key, int value) {
    _data[key] = value;
  }

  /// Test helper.
  int? peek(String key) => _data[key];
}

/// Read-only view of every persisted lifetime counter. Returned by
/// [StatsRepository.snapshot] so the menu screen has a single struct
/// to bind against.
class LifetimeStats {
  final int highScore;
  final int highDepthMeters;
  final int totalCoins;
  final int totalGems;
  final int totalNearMisses;
  final int totalGamesPlayed;

  const LifetimeStats({
    required this.highScore,
    required this.highDepthMeters,
    required this.totalCoins,
    required this.totalGems,
    required this.totalNearMisses,
    required this.totalGamesPlayed,
  });
}

class StatsRepository {
  static const String highScoreKey = 'high_score';
  static const String highDepthKey = 'high_depth';
  static const String totalCoinsKey = 'total_coins';
  static const String totalGemsKey = 'total_gems';
  static const String totalNearMissesKey = 'total_near_misses';
  static const String totalGamesPlayedKey = 'total_games_played';

  final StatsStorage storage;

  StatsRepository({StatsStorage? storage})
      : storage = storage ?? SharedPreferencesStatsStorage();

  Future<int> getHighScore() => storage.getInt(highScoreKey);
  Future<int> getHighDepthMeters() => storage.getInt(highDepthKey);
  Future<int> getTotalCoins() => storage.getInt(totalCoinsKey);
  Future<int> getTotalGems() => storage.getInt(totalGemsKey);
  Future<int> getTotalNearMisses() => storage.getInt(totalNearMissesKey);
  Future<int> getTotalGamesPlayed() => storage.getInt(totalGamesPlayedKey);

  /// Atomic snapshot — fan out one read per counter.
  Future<LifetimeStats> snapshot() async {
    final results = await Future.wait<int>([
      getHighScore(),
      getHighDepthMeters(),
      getTotalCoins(),
      getTotalGems(),
      getTotalNearMisses(),
      getTotalGamesPlayed(),
    ]);
    return LifetimeStats(
      highScore: results[0],
      highDepthMeters: results[1],
      totalCoins: results[2],
      totalGems: results[3],
      totalNearMisses: results[4],
      totalGamesPlayed: results[5],
    );
  }

  /// Apply a finished run's stats to lifetime counters.
  ///
  /// * [highScore] / [highDepth] only update if [stats] beat them.
  /// * Cumulative counters always increment.
  /// * Returns a [RunStats] copy with [isNewHighScore] resolved against
  ///   the *previous* high score, so the caller can use it directly to
  ///   drive the summary screen's "NEW BEST!" decision.
  Future<RunStats> updateAfterRun(RunStats stats) async {
    final prevHigh = await getHighScore();
    final prevDepth = await getHighDepthMeters();
    final prevCoins = await getTotalCoins();
    final prevGems = await getTotalGems();
    final prevNearMisses = await getTotalNearMisses();
    final prevGames = await getTotalGamesPlayed();

    final isNewHigh = stats.score > prevHigh;
    final depthInt = stats.depthMeters.round();

    if (isNewHigh) {
      await storage.setInt(highScoreKey, stats.score);
    }
    if (depthInt > prevDepth) {
      await storage.setInt(highDepthKey, depthInt);
    }
    await storage.setInt(totalCoinsKey, prevCoins + stats.coinsEarned);
    await storage.setInt(totalGemsKey, prevGems + stats.gemsCollected);
    await storage.setInt(totalNearMissesKey, prevNearMisses + stats.nearMisses);
    await storage.setInt(totalGamesPlayedKey, prevGames + 1);

    return stats.copyWith(isNewHighScore: isNewHigh);
  }
}
