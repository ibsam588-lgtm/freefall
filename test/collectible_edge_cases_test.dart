// Phase-15 collectible + powerup edge cases.
//
// collectible_manager_test covers the happy path of the magnet pull
// + pickup pipeline. This file fills in the corners:
//   * a coin sitting just outside the magnet radius is NOT pulled,
//     while one just inside IS pulled,
//   * the score-manager's combo coin multiplier (5x → 2x coins,
//     10x → 3x) and the powerup coin multiplier (2x while active)
//     compose multiplicatively, NOT addititvely,
//   * extraLife denied when the player is already at maxLives + the
//     absolute cap (4) — never pushes lives past the ceiling,
//   * every powerup type that lands as a timed effect has a
//     non-zero duration (extraLife is the documented exception
//     because it's instant).

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/components/collectibles/coin.dart';
import 'package:freefall/components/collectibles/gem.dart';
import 'package:freefall/components/collectibles/powerup_item.dart';
import 'package:freefall/models/collectible.dart';
import 'package:freefall/systems/collectible_manager.dart';
import 'package:freefall/systems/powerup_manager.dart';
import 'package:freefall/systems/score_manager.dart';

void main() {
  group('Magnet powerup radius edge', () {
    test('coin just inside the magnet radius is pulled toward player',
        () {
      final powerup = PowerupManager()
        ..activatePowerup(PowerupType.magnet);
      final mgr = CollectibleManager()..powerupManager = powerup;

      const insideRadius = PowerupManager.magnetActiveRadius - 5;
      final coin = Coin(
        collectibleId: 'c',
        coinType: CoinType.bronze,
        worldPosition: Vector2(insideRadius, 0),
      );
      mgr.addCoin(coin);

      // Run a 0.1s magnet step. Coin should move closer to (0,0).
      mgr.runPickupPass(Vector2.zero(), 0.1);
      expect(coin.position.x, lessThan(insideRadius),
          reason: 'inside-radius coin should be pulled left');
    });

    test('coin just outside the magnet radius is NOT pulled', () {
      final powerup = PowerupManager()
        ..activatePowerup(PowerupType.magnet);
      final mgr = CollectibleManager()..powerupManager = powerup;

      const outsideRadius = PowerupManager.magnetActiveRadius + 5;
      final coin = Coin(
        collectibleId: 'c',
        coinType: CoinType.bronze,
        worldPosition: Vector2(outsideRadius, 0),
      );
      mgr.addCoin(coin);

      mgr.runPickupPass(Vector2.zero(), 0.1);
      expect(coin.position.x, outsideRadius,
          reason: 'outside-radius coin should be untouched');
    });

    test('the magnet pulls gems and powerups too — not just coins', () {
      final powerup = PowerupManager()
        ..activatePowerup(PowerupType.magnet);
      final mgr = CollectibleManager()..powerupManager = powerup;

      const insideRadius = PowerupManager.magnetActiveRadius - 5;
      final gem = Gem(
        collectibleId: 'g',
        gemType: GemType.bronze,
        worldPosition: Vector2(insideRadius, 0),
      );
      final pup = PowerupItem(
        collectibleId: 'p',
        powerupType: PowerupType.shield,
        worldPosition: Vector2(0, insideRadius),
      );
      mgr.addGem(gem);
      mgr.addPowerup(pup);

      mgr.runPickupPass(Vector2.zero(), 0.1);
      expect(gem.position.x, lessThan(insideRadius));
      expect(pup.position.y, lessThan(insideRadius));
    });
  });

  group('Combo + powerup multiplier composition', () {
    test('5x combo = 2x coin multiplier', () {
      expect(ScoreManager.coinMultiplierForCombo(5), 2);
      expect(ScoreManager.coinMultiplierForCombo(9), 2);
    });

    test('10x combo = 3x coin multiplier', () {
      expect(ScoreManager.coinMultiplierForCombo(10), 3);
      expect(ScoreManager.coinMultiplierForCombo(15), 3);
    });

    test('combo + coin-multiplier powerup compose multiplicatively',
        () {
      // The host applies them as combo × powerup. With combo at 5
      // (2x) and the coinMultiplier powerup active (2x), the effective
      // multiplier is 4x, not 3x (additive).
      final pm = PowerupManager()
        ..activatePowerup(PowerupType.coinMultiplier);
      final sm = ScoreManager(powerupManager: pm);
      // Push combo to 5x.
      for (var i = 0; i < 5; i++) {
        sm.onNearMiss();
      }
      expect(sm.currentCoinMultiplier, 2,
          reason: 'combo side reports 2x');
      expect(pm.coinMultiplier, 2.0,
          reason: 'powerup side reports 2x');
      // Composition: 2 × 2 = 4 (the host calls
      // `pm.coinMultiplier * sm.currentCoinMultiplier`).
      final composed = pm.coinMultiplier * sm.currentCoinMultiplier;
      expect(composed, 4.0);
    });
  });

  group('extraLife caps at the absolute ceiling', () {
    test('granting extraLife once raises lives past start max, '
        'capping at absoluteMaxLives', () {
      var lives = 3;
      var maxLives = 3;
      final pm = PowerupManager()
        ..onExtraLife = () {
          // Mirror Player.gainLife: bump lives, push the cap if
          // already at max, but never past 4.
          if (lives < maxLives) {
            lives++;
          } else if (maxLives < 4) {
            maxLives++;
            lives = maxLives;
          }
        };

      pm.activatePowerup(PowerupType.extraLife);
      expect(lives, 4);
      expect(maxLives, 4);
    });

    test('repeated extraLife pickups never push past 4', () {
      var lives = 4;
      var maxLives = 4;
      final pm = PowerupManager()
        ..onExtraLife = () {
          if (lives < maxLives) {
            lives++;
          } else if (maxLives < 4) {
            maxLives++;
            lives = maxLives;
          }
        };
      pm.activatePowerup(PowerupType.extraLife);
      pm.activatePowerup(PowerupType.extraLife);
      pm.activatePowerup(PowerupType.extraLife);
      expect(lives, 4);
      expect(maxLives, 4);
    });
  });

  group('Powerup duration table', () {
    test('every timed powerup has a non-zero duration; extraLife is '
        'the documented exception', () {
      for (final t in PowerupType.values) {
        final d = PowerupDuration.forType(t);
        if (t == PowerupType.extraLife) {
          expect(d, 0.0,
              reason: 'extraLife is instant — duration is 0 by spec');
        } else {
          expect(d, greaterThan(0.0),
              reason: '${t.name} should have a positive duration');
        }
      }
    });

    test('shield duration is +inf (consumed on hit, not on a timer)',
        () {
      expect(PowerupDuration.forType(PowerupType.shield),
          double.infinity);
    });
  });
}
