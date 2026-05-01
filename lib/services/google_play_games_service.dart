// services/google_play_games_service.dart
//
// Phase 13 real backend for [GooglePlayGamesService]. Wraps the
// `games_services` plugin (which itself wraps Play Games on Android +
// Game Center on iOS).
//
// The base class in [google_play_games_stub.dart] exposes the surface
// + the placeholder leaderboard ids. This subclass overrides each
// method to call into the plugin, with try/catch on every call so a
// missing native plugin (web, headless tests, builds without Play
// Services) doesn't crash the rest of the app — it just falls through
// the no-op default.
//
// Sign-in is cached: [signIn] flips a local flag so subsequent
// [isSignedIn] checks don't have to round-trip to the platform if
// nothing else has changed. The plugin also exposes a player stream;
// we listen to it so a sign-out elsewhere reflects here too.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;

import 'google_play_games_stub.dart';

class GamesServicesPlayGames extends GooglePlayGamesService {
  GamesServicesPlayGames() : super() {
    _subscribePlayerStream();
  }

  bool _signedIn = false;
  String? _playerName;
  StreamSubscription<gs.PlayerData?>? _playerSub;

  void _subscribePlayerStream() {
    try {
      _playerSub = gs.GameAuth.player.listen((data) {
        _signedIn = data != null;
        _playerName = data?.displayName;
      }, onError: (_) {
        // Plugin not registered / no Play Services — leave the
        // cached state at "not signed in" and stop listening.
        _signedIn = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GamesServicesPlayGames] player stream skipped: $e');
      }
    }
  }

  @override
  Future<bool> isSignedIn() async {
    try {
      _signedIn = await gs.GameAuth.isSignedIn;
      return _signedIn;
    } catch (e) {
      if (kDebugMode) debugPrint('[GamesServicesPlayGames] isSignedIn: $e');
      return false;
    }
  }

  @override
  Future<bool> signIn() async {
    try {
      // The plugin returns null on success and an error string on
      // failure. We translate the absence of an error into "signed in".
      final err = await gs.GameAuth.signIn();
      _signedIn = err == null;
      return _signedIn;
    } catch (e) {
      if (kDebugMode) debugPrint('[GamesServicesPlayGames] signIn: $e');
      return false;
    }
  }

  @override
  Future<String?> getPlayerName() async {
    if (_playerName != null) return _playerName;
    return null;
  }

  @override
  Future<void> submitScore({
    required String leaderboardId,
    required int score,
  }) async {
    if (!_signedIn) {
      // Mirror the plugin behavior — never attempt a submission while
      // signed out, and don't trigger a sign-in popover from here.
      return;
    }
    try {
      await gs.Leaderboards.submitScore(
        score: gs.Score(
          androidLeaderboardID: leaderboardId,
          iOSLeaderboardID: leaderboardId,
          value: score,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[GamesServicesPlayGames] submitScore: $e');
    }
  }

  @override
  Future<void> unlockAchievement(String achievementId) async {
    if (!_signedIn) return;
    try {
      await gs.Achievements.unlock(
        achievement: gs.Achievement(
          androidID: achievementId,
          iOSID: achievementId,
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GamesServicesPlayGames] unlockAchievement: $e');
      }
    }
  }

  @override
  Future<bool> showLeaderboard(String leaderboardId) async {
    if (!_signedIn) return false;
    try {
      await gs.Leaderboards.showLeaderboards(
        androidLeaderboardID: leaderboardId,
        iOSLeaderboardID: leaderboardId,
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GamesServicesPlayGames] showLeaderboard: $e');
      }
      return false;
    }
  }

  @override
  Future<bool> showAllLeaderboards() async {
    if (!_signedIn) return false;
    try {
      await gs.Leaderboards.showLeaderboards();
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GamesServicesPlayGames] showAllLeaderboards: $e');
      }
      return false;
    }
  }

  @override
  Future<bool> showAchievements() async {
    if (!_signedIn) return false;
    try {
      await gs.Achievements.showAchievements();
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GamesServicesPlayGames] showAchievements: $e');
      }
      return false;
    }
  }

  Future<void> dispose() async {
    await _playerSub?.cancel();
    _playerSub = null;
  }
}
