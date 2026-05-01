// Phase-6 scoring + combo tests.
//
// ScoreManager is engine-agnostic — no Flame, no Flutter, no platform
// channels. We exercise it directly:
//   * combo multiplier table at every breakpoint,
//   * combo timeout decay + reset on hit,
//   * bonus events (zone, speed gate, gem) with multiplier composition,
//   * depth scoring is delta-based and monotonic,
//   * coin multiplier from combo (5+, 10+),
//   * powerup score multiplier composes with combo,
//   * snapshot reflects the run's tallies.
//
// NearMissDetector and StatsRepository are also exercised here since
// they live in the same Phase-6 surface area.

import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/components/near_miss_detector.dart';
import 'package:freefall/components/obstacles/game_obstacle.dart';
import 'package:freefall/models/collectible.dart';
import 'package:freefall/models/run_stats.dart';
import 'package:freefall/repositories/stats_repository.dart';
import 'package:freefall/systems/powerup_manager.dart';
import 'package:freefall/systems/score_manager.dart';

/// Minimal test obstacle — just exposes a hitbox at a given rect so
/// NearMissDetector can read it without rigging up a Flame component.
class _TestObstacle extends GameObstacle {
  final Rect _hitbox;

  _TestObstacle(String id, this._hitbox)
      : super(
          obstacleId: id,
          position: Vector2(_hitbox.center.dx, _hitbox.center.dy),
          size: Vector2(_hitbox.width, _hitbox.height),
        );

  @override
  Rect get hitbox => _hitbox;

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.damage;
}

void main() {
  group('ScoreManager combo multiplier table', () {
    test('matches the spec at every breakpoint', () {
      final cases = <int, int>{
        0: 1,
        1: 1,
        2: 2,
        3: 3,
        4: 3,
        5: 4,
        6: 4,
        7: 6,
        8: 6,
        9: 6,
        10: 8,
        11: 8,
        14: 8,
        15: 10,
        20: 10,
        100: 10,
      };
      for (final entry in cases.entries) {
        expect(
          ScoreManager.scoreMultiplierForCombo(entry.key),
          entry.value,
          reason: 'combo ${entry.key} should be x${entry.value}',
        );
      }
    });

    test('coin multiplier from combo (5+ = 2x, 10+ = 3x)', () {
      expect(ScoreManager.coinMultiplierForCombo(0), 1);
      expect(ScoreManager.coinMultiplierForCombo(4), 1);
      expect(ScoreManager.coinMultiplierForCombo(5), 2);
      expect(ScoreManager.coinMultiplierForCombo(9), 2);
      expect(ScoreManager.coinMultiplierForCombo(10), 3);
      expect(ScoreManager.coinMultiplierForCombo(99), 3);
    });
  });

  group('ScoreManager depth scoring', () {
    test('adds 1 point per meter at base multipliers', () {
      final sm = ScoreManager();
      sm.onDepthTick(0);
      sm.onDepthTick(50);
      expect(sm.score, 50);
      sm.onDepthTick(125);
      expect(sm.score, 125);
    });

    test('depth score is delta-based and never refunds', () {
      final sm = ScoreManager();
      sm.onDepthTick(100);
      expect(sm.score, 100);
      // Going up doesn't deduct; depth tick is monotonic.
      sm.onDepthTick(50);
      expect(sm.score, 100);
      // Resuming forward only bills the new delta past the prior max.
      sm.onDepthTick(150);
      expect(sm.score, 150);
    });

    test('depth score scales with PowerupManager scoreMultiplier', () {
      final pm = PowerupManager();
      final sm = ScoreManager(powerupManager: pm);

      sm.onDepthTick(50); // +50 (1x)
      pm.activatePowerup(PowerupType.scoreMultiplier);
      sm.onDepthTick(100); // +50 × 2 = +100
      expect(sm.score, 150);
    });

    test('depth scoring stacks with combo score multiplier', () {
      final sm = ScoreManager();
      // Build to combo 5 → 4x score multiplier.
      for (int i = 0; i < 5; i++) {
        sm.onNearMiss();
      }
      // Drop the running score so depth math is easy to reason about.
      sm.reset();
      // Re-build combo 5.
      for (int i = 0; i < 5; i++) {
        sm.onNearMiss();
      }
      // After reset+5 near-misses: score == 50 × 1 + 50 × 2 + 50 × 3 +
      //  50 × 3 + 50 × 4 = 50 + 100 + 150 + 150 + 200 = 650.
      expect(sm.score, 650);
      expect(sm.combo, 5);

      // 1m of depth at combo-5 multiplier = +4 score.
      final before = sm.score;
      sm.onDepthTick(1);
      expect(sm.score - before, 4);
    });
  });

  group('ScoreManager near-miss + combo', () {
    test('first near-miss adds 50pts and bumps combo to 1', () {
      final sm = ScoreManager();
      sm.onNearMiss();
      expect(sm.score, 50);
      expect(sm.combo, 1);
      expect(sm.bestCombo, 1);
      expect(sm.nearMisses, 1);
      expect(sm.comboTimeRemaining, ScoreManager.comboTimeoutSeconds);
    });

    test('combo grows monotonically and tracks bestCombo', () {
      final sm = ScoreManager();
      for (int i = 0; i < 7; i++) {
        sm.onNearMiss();
      }
      expect(sm.combo, 7);
      expect(sm.bestCombo, 7);
    });

    test('combo resets on player hit but bestCombo is preserved', () {
      final sm = ScoreManager();
      sm.onNearMiss();
      sm.onNearMiss();
      sm.onNearMiss();
      expect(sm.combo, 3);
      expect(sm.bestCombo, 3);

      sm.onPlayerHit();
      expect(sm.combo, 0);
      expect(sm.bestCombo, 3);
      expect(sm.comboTimeRemaining, 0);
    });

    test('combo expires after the 5s timeout', () {
      final sm = ScoreManager();
      sm.onNearMiss();
      sm.onNearMiss();
      expect(sm.combo, 2);

      // Tick well past the timeout.
      sm.update(ScoreManager.comboTimeoutSeconds + 0.1);
      expect(sm.combo, 0);
      expect(sm.comboTimeRemaining, 0);
    });

    test('each near-miss refreshes the timeout to a full 5s', () {
      final sm = ScoreManager();
      sm.onNearMiss();
      sm.update(4); // 4s in — almost expired
      sm.onNearMiss();
      expect(
        sm.comboTimeRemaining,
        closeTo(ScoreManager.comboTimeoutSeconds, 1e-9),
      );
    });

    test('onComboChanged fires on every increment', () {
      final fires = <int>[];
      final sm = ScoreManager()..onComboChanged = fires.add;
      sm.onNearMiss();
      sm.onNearMiss();
      sm.onNearMiss();
      expect(fires, [1, 2, 3]);
    });

    test('onComboReset fires once on hit (not on every-frame after)', () {
      int resets = 0;
      final sm = ScoreManager()..onComboReset = () => resets++;
      sm.onNearMiss();
      sm.onPlayerHit();
      expect(resets, 1);
      // Subsequent hits with no combo should not re-fire.
      sm.onPlayerHit();
      expect(resets, 1);
    });

    test('onComboReset fires when the timer expires naturally', () {
      int resets = 0;
      final sm = ScoreManager()..onComboReset = () => resets++;
      sm.onNearMiss();
      sm.update(ScoreManager.comboTimeoutSeconds + 0.1);
      expect(resets, 1);
    });
  });

  group('ScoreManager bonus events', () {
    test('zone completion adds 500pts (× combo multiplier)', () {
      final sm = ScoreManager();
      sm.onZoneComplete();
      expect(sm.score, ScoreManager.zoneCompletionBonus);
    });

    test('speed gate adds 100pts (× combo multiplier)', () {
      final sm = ScoreManager();
      sm.onSpeedGate();
      expect(sm.score, ScoreManager.speedGateBonus);
    });

    test('zone bonus scales with active combo', () {
      final sm = ScoreManager();
      // Reach combo 2 → 2x multiplier.
      sm.onNearMiss();
      sm.onNearMiss();
      final before = sm.score;
      sm.onZoneComplete();
      expect(sm.score - before, ScoreManager.zoneCompletionBonus * 2);
    });

    test('zone/speed-gate do NOT change combo', () {
      final sm = ScoreManager();
      sm.onNearMiss();
      sm.onZoneComplete();
      sm.onSpeedGate();
      expect(sm.combo, 1);
      expect(sm.bestCombo, 1);
    });

    test('gem collection adds gemValue × multipliers and tallies', () {
      final pm = PowerupManager()..activatePowerup(PowerupType.scoreMultiplier);
      final sm = ScoreManager(powerupManager: pm);

      sm.onGemCollected(GemValue.forType(GemType.gold)); // 25 × 2 = 50
      expect(sm.score, 50);
      expect(sm.gemsCollected, 1);
    });
  });

  group('ScoreManager state', () {
    test('reset wipes every counter', () {
      final sm = ScoreManager();
      sm.onNearMiss();
      sm.onNearMiss();
      sm.onZoneComplete();
      sm.onDepthTick(200);
      sm.onCoinCollected(count: 4);
      sm.onGemCollected(5);

      expect(sm.score, greaterThan(0));
      expect(sm.combo, greaterThan(0));
      expect(sm.bestCombo, greaterThan(0));

      sm.reset();
      expect(sm.score, 0);
      expect(sm.combo, 0);
      expect(sm.bestCombo, 0);
      expect(sm.comboTimeRemaining, 0);
      expect(sm.coinsEarned, 0);
      expect(sm.gemsCollected, 0);
      expect(sm.nearMisses, 0);
      expect(sm.maxDepthMeters, 0);
    });

    test('snapshot returns a RunStats with the resolved high-score flag', () {
      final sm = ScoreManager();
      sm.onDepthTick(100);
      sm.onNearMiss();
      sm.onCoinCollected(count: 3);
      sm.onGemCollected(5);
      sm.onPlayerHit();

      final s = sm.snapshot(isNewHighScore: true);
      expect(s.score, sm.score);
      expect(s.depthMeters, sm.maxDepthMeters);
      expect(s.nearMisses, 1);
      expect(s.coinsEarned, 3);
      expect(s.gemsCollected, 1);
      expect(s.bestCombo, 1);
      expect(s.isNewHighScore, isTrue);
    });
  });

  group('NearMissDetector', () {
    test('returns no hits when far from any obstacle', () {
      final det = NearMissDetector();
      const player = Rect.fromLTWH(0, 0, 36, 36);
      final obs = _TestObstacle('o1', const Rect.fromLTWH(500, 500, 50, 50));
      expect(det.detect(player, [obs], 1 / 60), isEmpty);
    });

    test('flags a near miss within the 10px ring (no overlap)', () {
      final det = NearMissDetector();
      const player = Rect.fromLTWH(0, 0, 36, 36);
      // Obstacle 5px right of the player rect — within the inflated ring,
      // not overlapping.
      final obs = _TestObstacle('o1', const Rect.fromLTWH(41, 0, 20, 36));
      final hits = det.detect(player, [obs], 1 / 60);
      expect(hits, hasLength(1));
      expect(hits.first.obstacleId, 'o1');
    });

    test('does NOT flag an actual overlap (that would be a hit)', () {
      final det = NearMissDetector();
      const player = Rect.fromLTWH(0, 0, 36, 36);
      final obs = _TestObstacle('o1', const Rect.fromLTWH(20, 20, 30, 30));
      final hits = det.detect(player, [obs], 1 / 60);
      expect(hits, isEmpty);
    });

    test('respects per-obstacle cooldown', () {
      final det = NearMissDetector();
      const player = Rect.fromLTWH(0, 0, 36, 36);
      final obs = _TestObstacle('o1', const Rect.fromLTWH(41, 0, 20, 36));

      // First detection fires.
      expect(det.detect(player, [obs], 1 / 60), hasLength(1));
      // Second detection same frame's worth — cooldown still in effect.
      expect(det.detect(player, [obs], 1 / 60), isEmpty);
      // After the cooldown, it can fire again.
      expect(
        det.detect(
          player,
          [obs],
          NearMissDetector.sameObstacleCooldown + 0.1,
        ),
        hasLength(1),
      );
    });

    test('reset clears the cooldown table', () {
      final det = NearMissDetector();
      const player = Rect.fromLTWH(0, 0, 36, 36);
      final obs = _TestObstacle('o1', const Rect.fromLTWH(41, 0, 20, 36));
      det.detect(player, [obs], 1 / 60);
      expect(det.cooldowns, hasLength(1));
      det.reset();
      expect(det.cooldowns, isEmpty);
    });
  });

  group('StatsRepository persistence', () {
    test('high score persists and resolves isNewHighScore on next run',
        () async {
      final storage = InMemoryStatsStorage();
      final repo = StatsRepository(storage: storage);

      // Run 1: 1000pts → new high.
      var resolved = await repo.updateAfterRun(
        const RunStats(
          score: 1000,
          depthMeters: 250,
          coinsEarned: 30,
          gemsCollected: 2,
          nearMisses: 5,
          bestCombo: 4,
          isNewHighScore: false, // caller doesn't know yet
        ),
      );
      expect(resolved.isNewHighScore, isTrue);
      expect(await repo.getHighScore(), 1000);

      // Run 2: 800pts → not a new high.
      resolved = await repo.updateAfterRun(
        const RunStats(
          score: 800,
          depthMeters: 200,
          coinsEarned: 10,
          gemsCollected: 1,
          nearMisses: 2,
          bestCombo: 2,
          isNewHighScore: false,
        ),
      );
      expect(resolved.isNewHighScore, isFalse);
      // High score is unchanged.
      expect(await repo.getHighScore(), 1000);

      // Run 3: 1500pts → new high again.
      resolved = await repo.updateAfterRun(
        const RunStats(
          score: 1500,
          depthMeters: 320,
          coinsEarned: 22,
          gemsCollected: 3,
          nearMisses: 8,
          bestCombo: 7,
          isNewHighScore: false,
        ),
      );
      expect(resolved.isNewHighScore, isTrue);
      expect(await repo.getHighScore(), 1500);
    });

    test('lifetime counters accumulate across runs', () async {
      final storage = InMemoryStatsStorage();
      final repo = StatsRepository(storage: storage);

      await repo.updateAfterRun(
        const RunStats(
          score: 100,
          depthMeters: 80,
          coinsEarned: 10,
          gemsCollected: 2,
          nearMisses: 3,
          bestCombo: 2,
          isNewHighScore: false,
        ),
      );
      await repo.updateAfterRun(
        const RunStats(
          score: 200,
          depthMeters: 120,
          coinsEarned: 25,
          gemsCollected: 1,
          nearMisses: 7,
          bestCombo: 5,
          isNewHighScore: false,
        ),
      );
      final snap = await repo.snapshot();
      expect(snap.totalCoins, 35);
      expect(snap.totalGems, 3);
      expect(snap.totalNearMisses, 10);
      expect(snap.totalGamesPlayed, 2);
      expect(snap.highDepthMeters, 120);
    });
  });

  group('RunStats model', () {
    test('copyWith only changes specified fields', () {
      const base = RunStats(
        score: 500,
        depthMeters: 250,
        coinsEarned: 12,
        gemsCollected: 3,
        nearMisses: 8,
        bestCombo: 6,
        isNewHighScore: false,
      );
      final updated = base.copyWith(isNewHighScore: true);
      expect(updated.score, base.score);
      expect(updated.bestCombo, base.bestCombo);
      expect(updated.isNewHighScore, isTrue);
    });

    test('equality holds for matching field values', () {
      const a = RunStats(
        score: 1,
        depthMeters: 2,
        coinsEarned: 3,
        gemsCollected: 4,
        nearMisses: 5,
        bestCombo: 6,
        isNewHighScore: true,
      );
      const b = RunStats(
        score: 1,
        depthMeters: 2,
        coinsEarned: 3,
        gemsCollected: 4,
        nearMisses: 5,
        bestCombo: 6,
        isNewHighScore: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
