// Phase-5 powerup manager tests.
//
// PowerupManager is the timer-driven state machine for active
// powerups. We exercise:
//   * activation/expiry timing for every powerup type that uses a timer,
//   * shield consume-on-hit semantics (no timer),
//   * extraLife instant-grant routes through the onExtraLife hook,
//   * magnet radius / speed / score / coin multipliers gate on activation,
//   * re-pickup extends instead of stomping shorter remaining time.

import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/models/collectible.dart';
import 'package:freefall/systems/powerup_manager.dart';

void main() {
  group('PowerupManager timers', () {
    test('magnet activates and decays over its full duration', () {
      final pm = PowerupManager();
      expect(pm.isActive(PowerupType.magnet), isFalse);
      expect(pm.magnetRadius, 0);

      pm.activatePowerup(PowerupType.magnet);
      expect(pm.isActive(PowerupType.magnet), isTrue);
      expect(pm.magnetRadius, PowerupManager.magnetActiveRadius);
      expect(pm.remaining(PowerupType.magnet),
          closeTo(PowerupDuration.magnetSeconds, 1e-9));

      // Tick to half — still active, radius unchanged.
      pm.update(PowerupDuration.magnetSeconds / 2);
      expect(pm.isActive(PowerupType.magnet), isTrue);
      expect(pm.magnetRadius, PowerupManager.magnetActiveRadius);

      // Tick past expiry — radius collapses.
      pm.update(PowerupDuration.magnetSeconds);
      expect(pm.isActive(PowerupType.magnet), isFalse);
      expect(pm.magnetRadius, 0);
    });

    test('slowMo speed multiplier flips with activation/expiry', () {
      final pm = PowerupManager();
      expect(pm.speedMultiplier, 1.0);

      pm.activatePowerup(PowerupType.slowMo);
      expect(pm.speedMultiplier, PowerupManager.slowMoScalar);
      expect(pm.isActive(PowerupType.slowMo), isTrue);

      pm.update(PowerupDuration.slowMoSeconds + 0.1);
      expect(pm.isActive(PowerupType.slowMo), isFalse);
      expect(pm.speedMultiplier, 1.0);
    });

    test('score and coin multipliers stack independently', () {
      final pm = PowerupManager();
      pm.activatePowerup(PowerupType.scoreMultiplier);
      pm.activatePowerup(PowerupType.coinMultiplier);

      expect(pm.scoreMultiplier, PowerupManager.scoreActiveMultiplier);
      expect(pm.coinMultiplier, PowerupManager.coinActiveMultiplier);
      expect(pm.activeCount, 2);

      // Expire score first.
      pm.update(PowerupDuration.scoreMultiplierSeconds + 0.1);
      expect(pm.isActive(PowerupType.scoreMultiplier), isFalse);
      expect(pm.scoreMultiplier, 1.0);
      // Coin multiplier expires on the same step (same duration).
      expect(pm.isActive(PowerupType.coinMultiplier), isFalse);
      expect(pm.coinMultiplier, 1.0);
    });

    test('re-activating extends rather than shortens remaining time', () {
      final pm = PowerupManager();
      pm.activatePowerup(PowerupType.magnet);
      // Burn most of the duration.
      pm.update(PowerupDuration.magnetSeconds - 1);
      expect(pm.remaining(PowerupType.magnet), closeTo(1.0, 1e-9));

      // Pick up a fresh one — remaining should jump back to the full
      // magnet duration, not stay at 1s.
      pm.activatePowerup(PowerupType.magnet);
      expect(pm.remaining(PowerupType.magnet),
          closeTo(PowerupDuration.magnetSeconds, 1e-9));
    });

    test('shield stays active until consumed (no timer expiry)', () {
      final pm = PowerupManager();
      pm.activatePowerup(PowerupType.shield);
      expect(pm.isActive(PowerupType.shield), isTrue);

      // 60 seconds of ticks shouldn't expire it.
      for (int i = 0; i < 3600; i++) {
        pm.update(1 / 60);
      }
      expect(pm.isActive(PowerupType.shield), isTrue);

      // consumeShield returns true and clears it.
      expect(pm.consumeShield(), isTrue);
      expect(pm.isActive(PowerupType.shield), isFalse);
      // Second consume returns false (nothing left).
      expect(pm.consumeShield(), isFalse);
    });
  });

  group('PowerupManager extraLife', () {
    test('fires onExtraLife and never enters the active map', () {
      int calls = 0;
      final pm = PowerupManager()..onExtraLife = () => calls++;

      pm.activatePowerup(PowerupType.extraLife);
      expect(calls, 1);
      expect(pm.isActive(PowerupType.extraLife), isFalse);
      expect(pm.activeCount, 0);
    });

    test('multiple pickups stack additively', () {
      int calls = 0;
      final pm = PowerupManager()..onExtraLife = () => calls++;
      pm.activatePowerup(PowerupType.extraLife);
      pm.activatePowerup(PowerupType.extraLife);
      pm.activatePowerup(PowerupType.extraLife);
      expect(calls, 3);
    });
  });

  group('PowerupManager state', () {
    test('clear wipes all active timers', () {
      final pm = PowerupManager();
      pm.activatePowerup(PowerupType.magnet);
      pm.activatePowerup(PowerupType.slowMo);
      pm.activatePowerup(PowerupType.shield);
      expect(pm.activeCount, 3);

      pm.clear();
      expect(pm.activeCount, 0);
      expect(pm.isActive(PowerupType.shield), isFalse);
      expect(pm.magnetRadius, 0);
      expect(pm.speedMultiplier, 1.0);
    });

    test('update with no active powerups is a cheap no-op', () {
      final pm = PowerupManager();
      // Should not throw or mutate anything.
      for (int i = 0; i < 10; i++) {
        pm.update(1 / 60);
      }
      expect(pm.activeCount, 0);
    });
  });

  group('Coin/Gem value lookups', () {
    test('coin values match the spec', () {
      expect(CoinValue.forType(CoinType.bronze), 1);
      expect(CoinValue.forType(CoinType.silver), 5);
      expect(CoinValue.forType(CoinType.gold), 25);
      expect(CoinValue.forType(CoinType.diamond), 100);
    });

    test('gem values match the spec', () {
      expect(GemValue.forType(GemType.bronze), 1);
      expect(GemValue.forType(GemType.silver), 5);
      expect(GemValue.forType(GemType.gold), 25);
    });

    test('every CoinType resolves to a positive value', () {
      for (final t in CoinType.values) {
        expect(CoinValue.forType(t), greaterThan(0),
            reason: 'CoinType $t should have a positive value');
      }
    });

    test('every GemType resolves to a positive value', () {
      for (final t in GemType.values) {
        expect(GemValue.forType(t), greaterThan(0),
            reason: 'GemType $t should have a positive value');
      }
    });
  });

  group('PowerupDuration table', () {
    test('every powerup has a non-negative duration', () {
      for (final t in PowerupType.values) {
        final d = PowerupDuration.forType(t);
        expect(d, greaterThanOrEqualTo(0));
      }
    });

    test('extraLife is instant (0 duration)', () {
      expect(PowerupDuration.forType(PowerupType.extraLife), 0);
    });

    test('shield has infinite duration (consume-on-hit)', () {
      expect(PowerupDuration.forType(PowerupType.shield), double.infinity);
    });

    test('timer-based effects have finite, spec-matching durations', () {
      expect(PowerupDuration.forType(PowerupType.magnet), 10);
      expect(PowerupDuration.forType(PowerupType.slowMo), 5);
      expect(PowerupDuration.forType(PowerupType.scoreMultiplier), 15);
      expect(PowerupDuration.forType(PowerupType.coinMultiplier), 15);
    });
  });
}
