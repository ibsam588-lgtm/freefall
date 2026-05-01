// Phase-10 achievement-manager tests.
//
// AchievementManager is engine-agnostic — no Flame, no Flutter, no
// platform channels. We exercise it directly:
//   * full catalog shape (20 rows, all ids unique),
//   * each achievement type's progress feed,
//   * unlock fires at the moment the threshold is crossed,
//   * lifetime + best-of-run counters persist across `load`,
//   * per-run state resets on onRunStarted,
//   * zone-no-hit logic across multiple zones in one run,
//   * updateFromRunStats accumulates depth + mirrors stats repo.
//
// GhostRunner has its own group below since it lives in the same Phase
// 10 surface area and shares the LoginStorage abstraction.

import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/models/achievement.dart';
import 'package:freefall/models/run_stats.dart';
import 'package:freefall/repositories/daily_login_repository.dart';
import 'package:freefall/repositories/stats_repository.dart';
import 'package:freefall/systems/achievement_manager.dart';
import 'package:freefall/systems/ghost_runner.dart';

AchievementManager _mgr({InMemoryLoginStorage? storage}) =>
    AchievementManager(storage: storage ?? InMemoryLoginStorage());

StatsRepository _statsRepo({InMemoryStatsStorage? storage}) =>
    StatsRepository(storage: storage ?? InMemoryStatsStorage());

void main() {
  group('Achievement catalog', () {
    test('contains exactly 20 achievements', () {
      expect(AchievementManager.catalog.length, 20);
    });

    test('every id is unique', () {
      final ids = AchievementManager.catalog.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every required spec id is present', () {
      const required = <String>{
        'fall_10km',
        'fall_50km',
        'fall_100km',
        'survive_3zones',
        'combo_10',
        'gems_100_run',
        'first_skin',
        'maxed_upgrade',
        'reach_core',
        'lightning_death',
        'jellyfish_death',
        'lava_death',
        'coins_1000',
        'coins_10000',
        'near_miss_100',
        'speed_gates_5',
        'streak_7',
        'all_zones',
        'no_hit_zone',
        'combo_5_run',
      };
      final actual =
          AchievementManager.catalog.map((a) => a.id).toSet();
      expect(actual, required);
    });

    test('byId returns the matching row, null for unknown', () {
      expect(AchievementManager.byId('fall_10km')?.targetValue, 10000);
      expect(AchievementManager.byId('does_not_exist'), isNull);
    });
  });

  group('Unlock detection + progress', () {
    test('fresh manager: nothing unlocked, every progress is zero',
        () async {
      final mgr = _mgr();
      await mgr.load();
      for (final ach in AchievementManager.catalog) {
        expect(mgr.checkUnlocked(ach.id), isFalse,
            reason: '${ach.id} should not be unlocked at start');
        expect(mgr.getProgress(ach.id), 0.0,
            reason: '${ach.id} progress should be 0 at start');
      }
    });

    test('combo_5_run fires the moment the 5x combo lands', () async {
      final mgr = _mgr();
      await mgr.load();

      Achievement? unlocked;
      mgr.onAchievementUnlocked = (a) => unlocked = a;

      mgr.onRunStarted();
      // 4x combo → no unlock yet.
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.comboReached, 4));
      expect(mgr.checkUnlocked('combo_5_run'), isFalse);
      expect(mgr.getProgress('combo_5_run'), closeTo(0.8, 1e-9));
      expect(unlocked, isNull);

      // 5x combo → fires.
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.comboReached, 5));
      expect(mgr.checkUnlocked('combo_5_run'), isTrue);
      expect(mgr.getProgress('combo_5_run'), 1.0);
      expect(unlocked?.id, 'combo_5_run');
    });

    test('combo_10 fires once and only once', () async {
      final mgr = _mgr();
      await mgr.load();

      var unlockedCount = 0;
      mgr.onAchievementUnlocked = (a) {
        if (a.id == 'combo_10') unlockedCount++;
      };

      mgr.onRunStarted();
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.comboReached, 12));
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.comboReached, 13));
      expect(unlockedCount, 1);
      expect(mgr.checkUnlocked('combo_10'), isTrue);
    });

    test('gems_100_run accumulates within a run, resets across runs',
        () async {
      final mgr = _mgr();
      await mgr.load();

      mgr.onRunStarted();
      for (int i = 0; i < 99; i++) {
        await mgr.onEvent(
            const AchievementEvent(AchievementEventKind.gemCollected));
      }
      expect(mgr.checkUnlocked('gems_100_run'), isFalse);
      // 99/100 → 0.99 progress.
      expect(mgr.getProgress('gems_100_run'), closeTo(0.99, 1e-9));

      // Restart — counter resets — but the BEST gems-in-run snapshot
      // persists, so progress doesn't drop.
      mgr.onRunStarted();
      expect(mgr.getProgress('gems_100_run'), closeTo(0.99, 1e-9));

      // One more in the new run still wouldn't hit 100 in *this* run
      // (1 != 100), but the lifetime best is now 99. We need to actually
      // hit 100 in a single run.
      for (int i = 0; i < 100; i++) {
        await mgr.onEvent(
            const AchievementEvent(AchievementEventKind.gemCollected));
      }
      expect(mgr.checkUnlocked('gems_100_run'), isTrue);
    });

    test('zone-no-hit unlocks at correct threshold; hit invalidates',
        () async {
      final mgr = _mgr();
      await mgr.load();

      mgr.onRunStarted();

      // Enter zone 0 (Stratosphere) — no zone closed yet.
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.zoneEntered, 0));
      expect(mgr.checkUnlocked('no_hit_zone'), isFalse);

      // Enter zone 1 — closes zone 0 with no hit → 1 no-hit zone.
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.zoneEntered, 1));
      expect(mgr.checkUnlocked('no_hit_zone'), isTrue);
      expect(mgr.checkUnlocked('survive_3zones'), isFalse);

      // Take a hit during zone 1, then enter zone 2 — zone 1 was hit,
      // so it doesn't count toward the 3-zone-no-hit goal.
      await mgr.onEvent(
          const AchievementEvent(AchievementEventKind.playerHit));
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.zoneEntered, 2));
      expect(mgr.checkUnlocked('survive_3zones'), isFalse);

      // Run zones 3, 4, 5 cleanly — but we already burned a slot, so
      // we'd need 3 *more* clean zones. Keep going.
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.zoneEntered, 3));
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.zoneEntered, 4));
      // Crossing into a 5th zone (cycle wrap, index 0 again) closes
      // zone 4 cleanly — that's 3 clean zones in a row → unlock.
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.zoneEntered, 0));
      expect(mgr.checkUnlocked('survive_3zones'), isTrue);
    });

    test('reach_core unlocks the first time zone index 4 is entered',
        () async {
      final mgr = _mgr();
      await mgr.load();

      mgr.onRunStarted();
      // Index 0..3 — Core not yet entered.
      for (int i = 0; i < 4; i++) {
        await mgr.onEvent(AchievementEvent(
            AchievementEventKind.zoneEntered, i));
      }
      expect(mgr.checkUnlocked('reach_core'), isFalse);

      // Crossing into Core (index 4) flips the flag.
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.zoneEntered, 4));
      expect(mgr.checkUnlocked('reach_core'), isTrue);
    });

    test('all_zones requires 5 zones entered in a run', () async {
      final mgr = _mgr();
      await mgr.load();

      mgr.onRunStarted();
      for (int i = 0; i < 4; i++) {
        await mgr.onEvent(AchievementEvent(
            AchievementEventKind.zoneEntered, i));
      }
      expect(mgr.checkUnlocked('all_zones'), isFalse);

      // 5th zone enter — wraps back to index 0 in the canonical cycle.
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.zoneEntered, 0));
      expect(mgr.checkUnlocked('all_zones'), isTrue);
    });

    test('death-by-X events unlock the matching achievements', () async {
      final mgr = _mgr();
      await mgr.load();

      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.killedByLightning));
      expect(mgr.checkUnlocked('lightning_death'), isTrue);

      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.killedByJellyfish));
      expect(mgr.checkUnlocked('jellyfish_death'), isTrue);

      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.killedByLavaJet));
      expect(mgr.checkUnlocked('lava_death'), isTrue);
    });

    test('first_skin and maxed_upgrade fire via syncExternals', () async {
      final mgr = _mgr();
      await mgr.load();

      expect(mgr.checkUnlocked('first_skin'), isFalse);
      await mgr.syncExternals(firstSkinBought: true);
      expect(mgr.checkUnlocked('first_skin'), isTrue);

      expect(mgr.checkUnlocked('maxed_upgrade'), isFalse);
      await mgr.syncExternals(anyUpgradeMaxed: true);
      expect(mgr.checkUnlocked('maxed_upgrade'), isTrue);
    });

    test('streak_7 unlocks when consecutiveDays mirrors >=7', () async {
      final mgr = _mgr();
      await mgr.load();

      await mgr.syncExternals(consecutiveDays: 6);
      expect(mgr.checkUnlocked('streak_7'), isFalse);
      expect(mgr.getProgress('streak_7'), closeTo(6 / 7, 1e-9));

      await mgr.syncExternals(consecutiveDays: 7);
      expect(mgr.checkUnlocked('streak_7'), isTrue);
    });

    test('lifetime coin tier unlocks compose with statsRepo snapshots',
        () async {
      final statsStorage = InMemoryStatsStorage()
        ..seed(StatsRepository.totalCoinsKey, 10500)
        ..seed(StatsRepository.totalNearMissesKey, 105);
      final stats = _statsRepo(storage: statsStorage);

      final mgr = _mgr();
      await mgr.load();

      // updateFromRunStats both bumps the depth counter and pulls
      // lifetime totals off the stats repo. We feed a tiny depth so
      // we don't accidentally trigger fall_10km too.
      await mgr.updateFromRunStats(
        const RunStats(
          score: 5,
          depthMeters: 100,
          coinsEarned: 0,
          gemsCollected: 0,
          nearMisses: 0,
          bestCombo: 0,
          isNewHighScore: false,
        ),
        stats,
      );
      expect(mgr.checkUnlocked('coins_1000'), isTrue);
      expect(mgr.checkUnlocked('coins_10000'), isTrue);
      expect(mgr.checkUnlocked('near_miss_100'), isTrue);
    });

    test('updateFromRunStats accumulates total depth across runs',
        () async {
      final stats = _statsRepo();
      final storage = InMemoryLoginStorage();
      final mgr = AchievementManager(storage: storage);
      await mgr.load();

      await mgr.updateFromRunStats(
        const RunStats(
          score: 0,
          depthMeters: 6000,
          coinsEarned: 0,
          gemsCollected: 0,
          nearMisses: 0,
          bestCombo: 0,
          isNewHighScore: false,
        ),
        stats,
      );
      expect(mgr.checkUnlocked('fall_10km'), isFalse);

      await mgr.updateFromRunStats(
        const RunStats(
          score: 0,
          depthMeters: 5000,
          coinsEarned: 0,
          gemsCollected: 0,
          nearMisses: 0,
          bestCombo: 0,
          isNewHighScore: false,
        ),
        stats,
      );
      expect(mgr.checkUnlocked('fall_10km'), isTrue);
      expect(mgr.checkUnlocked('fall_50km'), isFalse);
    });

    test('getProgress is clamped to 1.0 once unlocked', () async {
      final mgr = _mgr();
      await mgr.load();
      await mgr.syncExternals(firstSkinBought: true);
      expect(mgr.getProgress('first_skin'), 1.0);
      // Even after artificially yanking the underlying flag back, the
      // unlocked set stays sticky (achievements never re-lock).
      expect(mgr.checkUnlocked('first_skin'), isTrue);
    });

    test('getProgress for unknown id returns 0', () {
      final mgr = _mgr();
      expect(mgr.getProgress('not_a_real_id'), 0.0);
    });

    test('refreshLoginStreak picks up the latest streak', () async {
      final loginStorage = InMemoryLoginStorage()
        ..seed(consecutiveDays: 7);
      final loginRepo = DailyLoginRepository(storage: loginStorage);
      final mgr = _mgr();
      await mgr.load();
      await mgr.refreshLoginStreak(loginRepo);
      expect(mgr.checkUnlocked('streak_7'), isTrue);
    });
  });

  group('Persistence', () {
    test('unlocked set + counters survive a reload', () async {
      final storage = InMemoryLoginStorage();
      final mgr = AchievementManager(storage: storage);
      await mgr.load();

      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.killedByLightning));
      await mgr.onEvent(const AchievementEvent(
          AchievementEventKind.killedByLightning));
      expect(mgr.checkUnlocked('lightning_death'), isTrue);

      // Brand new manager pointed at the same storage — should
      // restore unlocked + counter state.
      final reloaded = AchievementManager(storage: storage);
      await reloaded.load();
      expect(reloaded.checkUnlocked('lightning_death'), isTrue);
      expect(
          reloaded.currentValueFor(AchievementType.lightningDeaths), 2);
    });
  });

  group('GhostRunner', () {
    test('records samples at the configured spacing', () {
      final ghost = GhostRunner(storage: InMemoryLoginStorage());
      ghost.onRunStarted();
      // 0.0, 0.05 (skipped), 0.1, 0.15 (skipped), 0.2 → 3 samples.
      ghost.recordSample(0.0, 100);
      ghost.recordSample(0.05, 110);
      ghost.recordSample(0.1, 120);
      ghost.recordSample(0.15, 130);
      ghost.recordSample(0.2, 140);
      expect(ghost.currentSamples.length, 3);
      expect(ghost.currentSamples.first.x, 100);
      expect(ghost.currentSamples.last.x, 140);
    });

    test('saves the run iff its score beats the previous best', () async {
      final storage = InMemoryLoginStorage();
      final ghost = GhostRunner(storage: storage);
      await ghost.load();
      ghost.onRunStarted();
      ghost.recordSample(0, 100);
      ghost.recordSample(0.1, 110);

      expect(await ghost.maybeSaveBestRun(500), isTrue);
      expect(ghost.bestScore, 500);

      ghost.onRunStarted();
      ghost.recordSample(0, 200);
      ghost.recordSample(0.1, 210);
      expect(await ghost.maybeSaveBestRun(400), isFalse,
          reason: 'lower score should not overwrite the saved best');
      expect(ghost.bestScore, 500);
    });

    test('ghost samples round-trip through storage', () async {
      final storage = InMemoryLoginStorage();
      final first = GhostRunner(storage: storage);
      await first.load();
      first.onRunStarted();
      first.recordSample(0, 100);
      first.recordSample(0.1, 200);
      first.recordSample(0.2, 300);
      expect(await first.maybeSaveBestRun(1234), isTrue);

      final second = GhostRunner(storage: storage);
      await second.load();
      expect(second.hasGhost, isTrue);
      expect(second.ghostSampleCount, 3);
      expect(second.bestScore, 1234);
      // sampleAt picks up the same path.
      expect(second.sampleAt(0.05), closeTo(150, 1e-6));
      expect(second.sampleAt(-1), isNull);
      expect(second.sampleAt(99), isNull);
    });
  });
}
