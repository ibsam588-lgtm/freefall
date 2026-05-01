// Phase-15 score / combo edge cases.
//
// score_manager_test covers happy-path scoring + combo. This file
// fills in the corners:
//   * collecting a 0-value gem / coin doesn't push the score
//     negative — score should never decrease,
//   * rapid back-to-back near-misses keep refreshing the combo
//     timer to its full 5s — the timer never compounds or saturates,
//   * the host owns the "near-miss not while invincible" rule (it
//     decides whether to call onNearMiss). This file documents the
//     contract: every onNearMiss CALL bumps the combo, so the host
//     must gate the call when the player has i-frames.
//   * onZoneComplete fires once per call — the host gates it to
//     once per zone via ZoneManager.onZoneEnter. This file
//     documents the contract: each ScoreManager.onZoneComplete
//     awards exactly the bonus once.

import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/systems/score_manager.dart';

void main() {
  group('Score never decreases', () {
    test('gem with 0 value adds 0 score (and bumps the gem tally)', () {
      final sm = ScoreManager();
      final before = sm.score;
      sm.onGemCollected(0);
      expect(sm.score, before);
      expect(sm.gemsCollected, 1);
    });

    test('depth tick going BACKWARD does not refund score', () {
      final sm = ScoreManager();
      sm.onDepthTick(100); // earn 100pts at 1pt/m
      final earned = sm.score;
      expect(earned, 100);
      // Depth ticks are monotonic — going back doesn't refund.
      sm.onDepthTick(50);
      expect(sm.score, earned);
    });

    test('coin pickup never moves the score (currency only)', () {
      final sm = ScoreManager();
      final before = sm.score;
      sm.onCoinCollected(count: 5);
      expect(sm.score, before);
      expect(sm.coinsEarned, 5);
    });
  });

  group('Combo timer refresh on rapid near-misses', () {
    test('a fresh near-miss resets the timer to the full 5s', () {
      final sm = ScoreManager();
      sm.onNearMiss();
      expect(sm.comboTimeRemaining,
          ScoreManager.comboTimeoutSeconds);

      // Drain 3s of the 5s window.
      sm.update(3.0);
      expect(sm.comboTimeRemaining, closeTo(2.0, 1e-9));

      // Another near-miss with 2s remaining — timer must snap back
      // to a full 5s, never extend past it.
      sm.onNearMiss();
      expect(sm.comboTimeRemaining,
          ScoreManager.comboTimeoutSeconds);
    });

    test('combo holds across 4 chained near-misses with sub-5s gaps',
        () {
      final sm = ScoreManager();
      for (var i = 0; i < 4; i++) {
        sm.onNearMiss();
        sm.update(1.0); // 1s between each — well under 5s window
      }
      expect(sm.combo, 4);
    });

    test('combo collapses on hit and resets the timer', () {
      final sm = ScoreManager();
      sm.onNearMiss();
      sm.onNearMiss();
      sm.onNearMiss();
      expect(sm.combo, 3);
      sm.onPlayerHit();
      expect(sm.combo, 0);
      expect(sm.comboTimeRemaining, 0);
    });
  });

  group('Near-miss invincibility contract', () {
    test('every onNearMiss call increments combo — invincibility is '
        'a host-side filter, not a manager-side guard', () {
      final sm = ScoreManager();
      // Two calls in quick succession.
      sm.onNearMiss();
      sm.onNearMiss();
      expect(sm.combo, 2,
          reason: 'manager itself does not check invincibility — the '
              'host (FreefallGame.update) is responsible for skipping '
              'the call when i-frames are active');
    });
  });

  group('Zone completion bonus', () {
    test('each onZoneComplete call awards the bonus exactly once', () {
      final sm = ScoreManager();
      final before = sm.score;
      sm.onZoneComplete();
      expect(sm.score - before, ScoreManager.zoneCompletionBonus);
    });

    test('multiple onZoneComplete calls each award the bonus '
        '(host gates dedup via ZoneManager.onZoneEnter)', () {
      final sm = ScoreManager();
      sm.onZoneComplete();
      sm.onZoneComplete();
      sm.onZoneComplete();
      expect(sm.score, ScoreManager.zoneCompletionBonus * 3);
    });

    test('zone bonus does not change combo state', () {
      final sm = ScoreManager();
      sm.onZoneComplete();
      expect(sm.combo, 0);
      expect(sm.bestCombo, 0);
    });

    test('zone bonus scales with active combo', () {
      final sm = ScoreManager();
      // Push combo to 3 (3x multiplier).
      sm.onNearMiss();
      sm.onNearMiss();
      sm.onNearMiss();
      final before = sm.score;
      sm.onZoneComplete();
      // 500 * 3x combo = 1500.
      expect(sm.score - before,
          ScoreManager.zoneCompletionBonus * 3);
    });
  });

  group('Speed gate bonus', () {
    test('each speed gate awards the flat bonus and does not touch '
        'combo', () {
      final sm = ScoreManager();
      sm.onSpeedGate();
      expect(sm.score, ScoreManager.speedGateBonus);
      expect(sm.combo, 0);
    });
  });
}
