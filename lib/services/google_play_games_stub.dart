// services/google_play_games_stub.dart
//
// Phase 10 placeholder for Google Play Games Services integration. The
// real implementation will route through the [games_services] package
// (already in pubspec.yaml). For now every method is a no-op so the
// rest of the app can call into the surface without provisioning a
// real Play Games account or developer console entry.
//
// Once the games_services wiring lands, swap [GooglePlayGamesService]
// with a real implementation; callers won't need to change.

import 'package:flutter/foundation.dart';

abstract class GooglePlayGamesService {
  /// True iff sign-in succeeded (or the platform claims it did).
  /// The stub always returns false.
  Future<bool> signIn();

  /// Submit [score] to the leaderboard with stable id [leaderboardId].
  Future<void> submitScore({
    required String leaderboardId,
    required int score,
  });

  /// Mark [achievementId] as unlocked on the platform side. The Phase
  /// 10 in-app achievement manager is the source of truth; this just
  /// mirrors so platform notifications fire.
  Future<void> unlockAchievement(String achievementId);

  /// Open the platform leaderboard UI for [leaderboardId]. Returns
  /// false if the platform UI couldn't be shown.
  Future<bool> showLeaderboard(String leaderboardId);

  /// Open the platform achievements UI. Returns false if it couldn't
  /// be shown (e.g. user not signed in).
  Future<bool> showAchievements();
}

/// No-op implementation — every call logs in debug and returns a
/// neutral result.
class GooglePlayGamesStub implements GooglePlayGamesService {
  const GooglePlayGamesStub();

  @override
  Future<bool> signIn() async {
    _log('signIn() called — stub no-op');
    return false;
  }

  @override
  Future<void> submitScore({
    required String leaderboardId,
    required int score,
  }) async {
    _log('submitScore(leaderboard=$leaderboardId, score=$score) — stub no-op');
  }

  @override
  Future<void> unlockAchievement(String achievementId) async {
    _log('unlockAchievement($achievementId) — stub no-op');
  }

  @override
  Future<bool> showLeaderboard(String leaderboardId) async {
    _log('showLeaderboard($leaderboardId) — stub no-op');
    return false;
  }

  @override
  Future<bool> showAchievements() async {
    _log('showAchievements() — stub no-op');
    return false;
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[GooglePlayGamesStub] $msg');
  }
}
