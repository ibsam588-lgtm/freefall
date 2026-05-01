// services/google_play_games_stub.dart
//
// Phase-10 surface for Google Play Games Services. The class itself
// is concrete with no-op defaults — that doubles as the null backend
// (offline / unsupported platforms / unit tests).
//
// Phase 13 ships the real backend in [GamesServicesPlayGames]
// (lib/services/google_play_games_service.dart) which subclasses this
// and overrides the methods to call into `games_services`.
//
// Why concrete instead of abstract: every method has a sane no-op
// default (return false / null / void). A real subclass overrides
// only what it needs; tests can do the same. There's no abstract
// contract anything else relies on, so an abstract class would just
// force the stub to repeat every signature.
//
// Leaderboard ids live as constants here so the wire-up site doesn't
// have to remember the placeholder strings. Replace these with the
// production CgkI... ids once Play Console provisioning lands.

import 'package:flutter/foundation.dart';

class GooglePlayGamesService {
  /// Placeholder Google Play Games leaderboard ids. The CgkI prefix
  /// matches the format Play Console issues; the suffixes are stable
  /// names so callers reference them by intent ("best score") rather
  /// than the opaque id string.
  static const String bestScoreLeaderboardId = 'CgkI_freefall_best_score';
  static const String bestDepthLeaderboardId = 'CgkI_freefall_best_depth';

  const GooglePlayGamesService();

  /// True iff the player is currently signed in to Play Games / Game
  /// Center. Default no-op returns false.
  Future<bool> isSignedIn() async => false;

  /// Trigger the platform sign-in flow. Returns true on success,
  /// false on failure / cancellation. The default no-op returns false
  /// so the rest of the app degrades cleanly.
  Future<bool> signIn() async {
    _log('signIn() — null backend, no-op');
    return false;
  }

  /// Player's display name once signed in. Null when offline or on a
  /// platform that doesn't expose it.
  Future<String?> getPlayerName() async => null;

  /// Submit [score] to leaderboard [leaderboardId]. Default no-op.
  Future<void> submitScore({
    required String leaderboardId,
    required int score,
  }) async {
    _log('submitScore(leaderboard=$leaderboardId, score=$score) — no-op');
  }

  /// Convenience wrapper that submits the player's deepest fall to
  /// [bestDepthLeaderboardId]. Depth is rounded to whole meters since
  /// Play Games leaderboards take ints.
  Future<void> submitDepthScore(double depthMeters) async {
    final rounded = depthMeters.round();
    if (rounded <= 0) return;
    await submitScore(
      leaderboardId: bestDepthLeaderboardId,
      score: rounded,
    );
  }

  /// Mark [achievementId] as unlocked on the platform side. The
  /// in-app [AchievementManager] is the source of truth; this just
  /// mirrors so the platform notification fires.
  Future<void> unlockAchievement(String achievementId) async {
    _log('unlockAchievement($achievementId) — no-op');
  }

  /// Open the platform leaderboard UI for [leaderboardId]. Returns
  /// false if the UI couldn't be shown.
  Future<bool> showLeaderboard(String leaderboardId) async {
    _log('showLeaderboard($leaderboardId) — no-op');
    return false;
  }

  /// Open the platform UI listing every leaderboard.
  Future<bool> showAllLeaderboards() async {
    _log('showAllLeaderboards() — no-op');
    return false;
  }

  /// Open the platform achievements UI.
  Future<bool> showAchievements() async {
    _log('showAchievements() — no-op');
    return false;
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[GooglePlayGames null] $msg');
  }
}

/// Explicit null backend. Identical behavior to the base class — this
/// alias just lets call sites write `GooglePlayGamesStub()` when they
/// want to be unambiguous about wiring the offline path.
class GooglePlayGamesStub extends GooglePlayGamesService {
  const GooglePlayGamesStub();
}
