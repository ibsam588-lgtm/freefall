// Phase-5 collectible manager + repository tests.
//
// CollectibleManager is engine-light: it works without Flame mounted,
// so tests can construct collectibles directly and drive the pickup
// pipeline through the runPickupPass / pruneOffscreen entrypoints.
//
// CoinRepository is async + storage-backed; we use the in-memory
// fake to keep tests fast and deterministic.

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/components/collectibles/coin.dart';
import 'package:freefall/components/collectibles/gem.dart';
import 'package:freefall/components/collectibles/powerup_item.dart';
import 'package:freefall/models/collectible.dart';
import 'package:freefall/repositories/coin_repository.dart';
import 'package:freefall/systems/collectible_manager.dart';
import 'package:freefall/systems/powerup_manager.dart';

Coin _coin({CoinType type = CoinType.bronze, double x = 0, double y = 0}) {
  return Coin(
    collectibleId: 'coin-${type.name}-$x-$y',
    coinType: type,
    worldPosition: Vector2(x, y),
    phaseOffset: 0,
  );
}

Gem _gem({GemType type = GemType.bronze, double x = 0, double y = 0}) {
  return Gem(
    collectibleId: 'gem-${type.name}-$x-$y',
    gemType: type,
    worldPosition: Vector2(x, y),
  );
}

PowerupItem _powerup({required PowerupType type, double x = 0, double y = 0}) {
  return PowerupItem(
    collectibleId: 'pu-${type.name}-$x-$y',
    powerupType: type,
    worldPosition: Vector2(x, y),
  );
}

void main() {
  group('CollectibleManager pickup', () {
    test('coin within pickup radius is collected and removed', () {
      final cm = CollectibleManager();
      final coin = _coin(x: 100, y: 100);
      cm.addCoin(coin);

      // Player too far — no pickup.
      cm.runPickupPass(Vector2(500, 500), 1 / 60);
      expect(cm.activeCoins, hasLength(1));

      // Player on top of the coin — pickup fires.
      Coin? collected;
      cm.onCoinCollected = (c) => collected = c;
      cm.runPickupPass(Vector2(100, 100), 1 / 60);
      expect(cm.activeCoins, isEmpty);
      expect(collected, same(coin));
      expect(coin.collected, isTrue);
    });

    test('gem pickup fires its callback and persists with score multiplier', () {
      final pm = PowerupManager();
      final cm = CollectibleManager()..powerupManager = pm;
      final gem = _gem(type: GemType.gold, x: 50, y: 50);
      cm.addGem(gem);

      Gem? collected;
      cm.onGemCollected = (g) => collected = g;

      cm.runPickupPass(Vector2(50, 50), 1 / 60);
      expect(collected, same(gem));
      expect(cm.activeGems, isEmpty);
      // Verify the floating-text effect was queued.
      expect(cm.activeCollectionFx, hasLength(1));
    });

    test('powerup pickup activates the powerup via PowerupManager', () {
      final pm = PowerupManager();
      final cm = CollectibleManager()..powerupManager = pm;
      final pu = _powerup(type: PowerupType.magnet, x: 0, y: 0);
      cm.addPowerup(pu);

      cm.runPickupPass(Vector2(0, 0), 1 / 60);
      expect(cm.activePowerups, isEmpty);
      expect(pm.isActive(PowerupType.magnet), isTrue);
      expect(pm.magnetRadius, PowerupManager.magnetActiveRadius);
    });

    test('extraLife powerup pickup grants exactly one life', () {
      final pm = PowerupManager();
      int lives = 0;
      pm.onExtraLife = () => lives++;
      final cm = CollectibleManager()..powerupManager = pm;
      cm.addPowerup(_powerup(type: PowerupType.extraLife, x: 0, y: 0));

      cm.runPickupPass(Vector2(0, 0), 1 / 60);
      expect(lives, 1);
      // extraLife is instant; no entry persists.
      expect(pm.isActive(PowerupType.extraLife), isFalse);
    });
  });

  group('CollectibleManager magnet', () {
    test('magnet pulls collectibles toward player when active', () {
      final pm = PowerupManager()..activatePowerup(PowerupType.magnet);
      final cm = CollectibleManager()..powerupManager = pm;
      // Place a coin 150px away — inside the 200px magnet radius.
      final coin = _coin(x: 150, y: 0);
      cm.addCoin(coin);

      final beforeX = coin.position.x;
      cm.runPickupPass(Vector2(0, 0), 1 / 60);
      // The coin should have moved closer to the player.
      expect(coin.position.x, lessThan(beforeX));
    });

    test('no magnet pull when powerup inactive', () {
      final pm = PowerupManager(); // not activated
      final cm = CollectibleManager()..powerupManager = pm;
      final coin = _coin(x: 150, y: 0);
      cm.addCoin(coin);

      cm.runPickupPass(Vector2(0, 0), 1 / 60);
      expect(coin.position.x, 150); // unchanged
    });

    test('magnet does not pull collectibles outside its radius', () {
      final pm = PowerupManager()..activatePowerup(PowerupType.magnet);
      final cm = CollectibleManager()..powerupManager = pm;
      // 300px away — outside the 200px magnet radius.
      final coin = _coin(x: 300, y: 0);
      cm.addCoin(coin);

      cm.runPickupPass(Vector2(0, 0), 1 / 60);
      expect(coin.position.x, 300);
    });

    test('magnet radius drops when powerup expires mid-frame', () {
      final pm = PowerupManager()..activatePowerup(PowerupType.magnet);
      final cm = CollectibleManager()..powerupManager = pm;
      final coin = _coin(x: 150, y: 0);
      cm.addCoin(coin);

      // Burn the entire magnet duration in one tick.
      pm.update(PowerupDuration.magnetSeconds + 0.1);
      expect(pm.magnetRadius, 0);

      // Now the pickup pass shouldn't pull.
      cm.runPickupPass(Vector2(0, 0), 1 / 60);
      expect(coin.position.x, 150);
    });
  });

  group('CollectibleManager pruning', () {
    test('off-screen coins/gems/powerups are pruned', () {
      int detached = 0;
      final cm = CollectibleManager(onDetach: (_) => detached++);
      cm.addCoin(_coin(x: 100, y: -1000));
      cm.addGem(_gem(x: 100, y: -1000));
      cm.addPowerup(_powerup(type: PowerupType.shield, x: 100, y: -1000));
      expect(cm.activeCount, 3);

      // Player viewport top at y=0 — the items at y=-1000 are well above.
      cm.pruneOffscreen(0);
      expect(cm.activeCount, 0);
      expect(detached, 3);
    });

    test('on-screen items are NOT pruned', () {
      final cm = CollectibleManager();
      cm.addCoin(_coin(x: 0, y: 100));
      cm.addCoin(_coin(x: 0, y: 200));

      cm.pruneOffscreen(0);
      expect(cm.activeCoins, hasLength(2));
    });
  });

  group('CollectibleManager fx', () {
    test('floating-text effects expire after their lifetime', () {
      final cm = CollectibleManager();
      cm.addCoin(_coin(x: 0, y: 0));
      cm.runPickupPass(Vector2(0, 0), 1 / 60);
      expect(cm.activeCollectionFx, hasLength(1));

      // Tick past the FX duration.
      cm.update(CollectibleManager.collectionFxDuration + 0.1);
      expect(cm.activeCollectionFx, isEmpty);
    });
  });

  group('Coin component', () {
    test('value is the CoinValue table for its tier', () {
      expect(_coin(type: CoinType.bronze).value, 1);
      expect(_coin(type: CoinType.silver).value, 5);
      expect(_coin(type: CoinType.gold).value, 25);
      expect(_coin(type: CoinType.diamond).value, 100);
    });

    test('size scales with tier', () {
      expect(Coin.radiusFor(CoinType.bronze), lessThan(Coin.radiusFor(CoinType.silver)));
      expect(Coin.radiusFor(CoinType.silver), lessThan(Coin.radiusFor(CoinType.gold)));
      expect(Coin.radiusFor(CoinType.gold), lessThan(Coin.radiusFor(CoinType.diamond)));
    });

    test('pulse scale stays in 0.9..1.1 range', () {
      final c = _coin();
      // Sample the wave at many phases to confirm bounds.
      for (int i = 0; i < 100; i++) {
        c.update(1 / 60);
        expect(c.pulseScale, inInclusiveRange(0.85, 1.15));
      }
    });
  });

  group('Gem component', () {
    test('value matches GemValue table', () {
      expect(_gem(type: GemType.bronze).value, 1);
      expect(_gem(type: GemType.silver).value, 5);
      expect(_gem(type: GemType.gold).value, 25);
    });
  });

  group('PowerupItem bounce', () {
    test('bounceOffset oscillates within its amplitude bounds', () {
      final p = _powerup(type: PowerupType.shield);
      double minOffset = 0;
      double maxOffset = 0;
      for (int i = 0; i < 200; i++) {
        p.update(1 / 60);
        if (p.bounceOffset < minOffset) minOffset = p.bounceOffset;
        if (p.bounceOffset > maxOffset) maxOffset = p.bounceOffset;
      }
      expect(maxOffset, lessThanOrEqualTo(PowerupItem.bounceAmplitude));
      expect(minOffset, greaterThanOrEqualTo(-PowerupItem.bounceAmplitude));
      expect(maxOffset - minOffset, greaterThan(0));
    });
  });

  group('CoinRepository persistence', () {
    test('balance persists across reads via mock storage', () async {
      final storage = InMemoryCoinStorage();
      final repo = CoinRepository(storage: storage);
      expect(await repo.getBalance(), 0);

      await repo.addCoins(50);
      expect(await repo.getBalance(), 50);
      expect(await repo.getLifetimeEarned(), 50);

      // Re-read via a *new* repo on the same storage — the value should
      // still be there.
      final repo2 = CoinRepository(storage: storage);
      expect(await repo2.getBalance(), 50);
    });

    test('addCoins ignores zero/negative amounts', () async {
      final storage = InMemoryCoinStorage();
      final repo = CoinRepository(storage: storage);
      await repo.addCoins(10);
      await repo.addCoins(0);
      await repo.addCoins(-5);
      expect(await repo.getBalance(), 10);
      expect(await repo.getLifetimeEarned(), 10);
    });

    test('spendCoins decrements and throws on insufficient', () async {
      final storage = InMemoryCoinStorage();
      final repo = CoinRepository(storage: storage);
      await repo.addCoins(100);

      final left = await repo.spendCoins(40);
      expect(left, 60);
      expect(await repo.getBalance(), 60);

      // Lifetime earned is unchanged by spending.
      expect(await repo.getLifetimeEarned(), 100);

      // Overspend throws.
      expect(
        () async => repo.spendCoins(999),
        throwsA(isA<InsufficientCoinsException>()),
      );
      // Balance unchanged after the failed spend.
      expect(await repo.getBalance(), 60);
    });

    test('lifetime is monotonic — never decreases on spend', () async {
      final storage = InMemoryCoinStorage();
      final repo = CoinRepository(storage: storage);
      await repo.addCoins(200);
      await repo.spendCoins(150);
      expect(await repo.getLifetimeEarned(), 200);
    });

    test('malformed storage values fall back to 0', () async {
      final storage = InMemoryCoinStorage()
        ..seed(CoinRepository.balanceKey, 'NaN')
        ..seed(CoinRepository.lifetimeKey, 'banana');
      final repo = CoinRepository(storage: storage);
      expect(await repo.getBalance(), 0);
      expect(await repo.getLifetimeEarned(), 0);
    });
  });
}
