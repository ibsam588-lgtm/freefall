// Phase-13 Google Play Games + Achievement-sync tests.
//
// We can't drive the real `games_services` plugin from a unit test
// (it requires a host platform with Play Services / Game Center). All
// of the tests here drive a [_RecordingPlayGames] subclass that
// captures the leaderboard / achievement / sign-in calls without
// touching the platform.
//
// What we verify:
//   * the base [GooglePlayGamesService] is a safe no-op,
//   * leaderboard ids match the spec'd CgkI_freefall_* placeholders,
//   * `submitDepthScore` rounds the depth and routes to the depth
//     leaderboard,
//   * `submitDepthScore` ignores zero / negative depths,
//   * `submitScore` is silent when the spy reports signed-out (we
//     mirror the real plugin's "no-op while offline" behavior),
//   * `AchievementManager` mirrors freshly-unlocked rows to Play
//     Games via `unlockAchievement`, using the row's `playGamesId`,
//   * already-unlocked rows do NOT re-fire on subsequent events,
//   * every catalog row carries a non-null `playGamesId`.

import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/repositories/daily_login_repository.dart';
import 'package:freefall/services/google_play_games_stub.dart';
import 'package:freefall/systems/achievement_manager.dart';

class _RecordingPlayGames extends GooglePlayGamesService {
  _RecordingPlayGames({this.signedIn = false});

  bool signedIn;

  final List<({String leaderboardId, int score})> scoreSubmissions = [];
  final List<String> achievementUnlocks = [];
  int signInCalls = 0;
  int showLeaderboardCalls = 0;
  int showAllLeaderboardsCalls = 0;
  int showAchievementsCalls = 0;

  @override
  Future<bool> isSignedIn() async => signedIn;

  @override
  Future<bool> signIn() async {
    signInCalls++;
    signedIn = true;
    return true;
  }

  @override
  Future<String?> getPlayerName() async =>
      signedIn ? 'Test Faller' : null;

  @override
  Future<void> submitScore({
    required String leaderboardId,
    required int score,
  }) async {
    if (!signedIn) return;
    scoreSubmissions.add((leaderboardId: leaderboardId, score: score));
  }

  @override
  Future<void> unlockAchievement(String achievementId) async {
    achievementUnlocks.add(achievementId);
  }

  @override
  Future<bool> showLeaderboard(String leaderboardId) async {
    showLeaderboardCalls++;
    return signedIn;
  }

  @override
  Future<bool> showAllLeaderboards() async {
    showAllLeaderboardsCalls++;
    return signedIn;
  }

  @override
  Future<bool> showAchievements() async {
    showAchievementsCalls++;
    return signedIn;
  }
}

void main() {
  group('Base GooglePlayGamesService is a safe no-op', () {
    test('every public method returns a sane default without throwing',
        () async {
      const svc = GooglePlayGamesService();
      expect(await svc.isSignedIn(), isFalse);
      expect(await svc.signIn(), isFalse);
      expect(await svc.getPlayerName(), isNull);
      await svc.submitScore(leaderboardId: 'x', score: 0);
      await svc.submitDepthScore(123.4);
      await svc.unlockAchievement('any_id');
      expect(await svc.showLeaderboard('x'), isFalse);
      expect(await svc.showAllLeaderboards(), isFalse);
      expect(await svc.showAchievements(), isFalse);
    });

    test('GooglePlayGamesStub is the same surface', () async {
      const stub = GooglePlayGamesStub();
      expect(await stub.isSignedIn(), isFalse);
      await stub.submitScore(leaderboardId: 'x', score: 5);
      await stub.unlockAchievement('y');
    });
  });

  group('Leaderboard ids', () {
    test('best score id is the spec\'d CgkI_freefall_best_score', () {
      expect(GooglePlayGamesService.bestScoreLeaderboardId,
          'CgkI_freefall_best_score');
    });

    test('best depth id is the spec\'d CgkI_freefall_best_depth', () {
      expect(GooglePlayGamesService.bestDepthLeaderboardId,
          'CgkI_freefall_best_depth');
    });
  });

  group('submitDepthScore', () {
    test('rounds depth to whole meters and routes to the depth board',
        () async {
      final svc = _RecordingPlayGames(signedIn: true);
      await svc.submitDepthScore(1234.7);
      expect(svc.scoreSubmissions, [
        (
          leaderboardId: GooglePlayGamesService.bestDepthLeaderboardId,
          score: 1235,
        ),
      ]);
    });

    test('ignores zero / negative depths', () async {
      final svc = _RecordingPlayGames(signedIn: true);
      await svc.submitDepthScore(0);
      await svc.submitDepthScore(-50);
      expect(svc.scoreSubmissions, isEmpty);
    });
  });

  group('Score submission honors sign-in state', () {
    test('signed-out player: submissions are silent', () async {
      final svc = _RecordingPlayGames(signedIn: false);
      await svc.submitScore(leaderboardId: 'main', score: 100);
      await svc.submitDepthScore(500);
      expect(svc.scoreSubmissions, isEmpty);
    });

    test('signed-in player: submissions land', () async {
      final svc = _RecordingPlayGames(signedIn: true);
      await svc.submitScore(leaderboardId: 'main', score: 100);
      expect(svc.scoreSubmissions, hasLength(1));
    });

    test('signIn() flips the cached signed-in state', () async {
      final svc = _RecordingPlayGames(signedIn: false);
      expect(await svc.isSignedIn(), isFalse);
      await svc.signIn();
      expect(svc.signInCalls, 1);
      expect(await svc.isSignedIn(), isTrue);
    });
  });

  group('Catalog → Play Games id mapping', () {
    test('every achievement carries a non-null playGamesId', () {
      for (final ach in AchievementManager.catalog) {
        expect(ach.playGamesId, isNotNull,
            reason: '${ach.id} should have a Play Games id');
      }
    });

    test('every Play Games id is unique', () {
      final ids = AchievementManager.catalog
          .map((a) => a.playGamesId!)
          .toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every Play Games id starts with the CgkI_freefall_ prefix',
        () {
      for (final ach in AchievementManager.catalog) {
        expect(ach.playGamesId, startsWith('CgkI_freefall_'),
            reason: '${ach.id} prefix mismatch');
      }
    });
  });

  group('AchievementManager → Play Games sync', () {
    test('an unlock fires unlockAchievement with the mapped id',
        () async {
      final services = _RecordingPlayGames(signedIn: true);
      final mgr = AchievementManager(
        storage: InMemoryLoginStorage(),
        gameServices: services,
      );
      await mgr.load();

      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.killedByLightning));

      // Allow the fire-and-forget unlockAchievement to execute.
      await Future<void>.delayed(Duration.zero);
      expect(services.achievementUnlocks,
          contains('CgkI_freefall_lightning_death'));
    });

    test('only the freshly-unlocked id is mirrored — already-unlocked '
        'rows stay quiet on later events', () async {
      final services = _RecordingPlayGames(signedIn: true);
      final mgr = AchievementManager(
        storage: InMemoryLoginStorage(),
        gameServices: services,
      );
      await mgr.load();

      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.killedByLightning));
      await Future<void>.delayed(Duration.zero);
      services.achievementUnlocks.clear();

      // Same event fires again — unlock is sticky in-app, no
      // duplicate Play Games sync should happen.
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.killedByLightning));
      await Future<void>.delayed(Duration.zero);
      expect(services.achievementUnlocks, isEmpty);
    });

    test('a manager without gameServices skips the mirror cleanly',
        () async {
      final mgr = AchievementManager(
        storage: InMemoryLoginStorage(),
      );
      await mgr.load();
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.killedByLightning));
      // No assertion needed — the test passes if no exception was
      // raised dispatching to a null gameServices reference.
      expect(mgr.checkUnlocked('lightning_death'), isTrue);
    });
  });
}
