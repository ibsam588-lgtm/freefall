// Phase-8 store tests.
//
// StoreRepository talks to two storages: CoinRepository (currency,
// secure storage) and LoginStorage (cosmetic ownership + equip + level).
// Both use in-memory fakes so the suite stays fast and deterministic.
//
// Coverage:
//   * cosmetic purchase succeeds when balance is sufficient,
//   * purchase fails with InsufficientCoinsException when broke,
//   * default-tier items resolve as owned without persistence,
//   * already-owned re-purchase short-circuits with no extra spend,
//   * equip refuses unowned items + works for each cosmetic slot,
//   * upgrade level state machine 0→1→2→3 stops at maxed,
//   * upgrade purchase honors cost ladder + balance,
//   * inventory ID round-trip: skinIdOf → parseSkinId etc.

import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/models/death_effect.dart';
import 'package:freefall/models/player_skin.dart';
import 'package:freefall/models/powerup_upgrade.dart';
import 'package:freefall/models/shield_skin.dart';
import 'package:freefall/models/trail_effect.dart';
import 'package:freefall/repositories/coin_repository.dart';
import 'package:freefall/repositories/daily_login_repository.dart';
import 'package:freefall/repositories/store_repository.dart';
import 'package:freefall/store/store_inventory.dart';

({StoreRepository repo, CoinRepository coin, InMemoryLoginStorage storage})
    _build({int seedCoins = 0}) {
  final coinStorage = InMemoryCoinStorage();
  if (seedCoins > 0) {
    coinStorage.seed(CoinRepository.balanceKey, '$seedCoins');
  }
  final coin = CoinRepository(storage: coinStorage);
  final login = InMemoryLoginStorage();
  final repo = StoreRepository(coinRepo: coin, storage: login);
  return (repo: repo, coin: coin, storage: login);
}

void main() {
  group('StoreInventory ID encoding', () {
    test('skinIdOf round-trips through parseSkinId', () {
      for (final id in SkinId.values) {
        final encoded = StoreInventory.skinIdOf(id);
        expect(StoreInventory.parseSkinId(encoded), id);
      }
    });

    test('trailIdOf round-trips through parseTrailId', () {
      for (final id in TrailId.values) {
        final encoded = StoreInventory.trailIdOf(id);
        expect(StoreInventory.parseTrailId(encoded), id);
      }
    });

    test('shieldIdOf round-trips through parseShieldId', () {
      for (final id in ShieldSkinId.values) {
        final encoded = StoreInventory.shieldIdOf(id);
        expect(StoreInventory.parseShieldId(encoded), id);
      }
    });

    test('deathIdOf round-trips through parseDeathId', () {
      for (final id in DeathEffectId.values) {
        final encoded = StoreInventory.deathIdOf(id);
        expect(StoreInventory.parseDeathId(encoded), id);
      }
    });

    test('upgradeIdOf round-trips through parseUpgradeId', () {
      for (final id in PowerupUpgradeId.values) {
        final encoded = StoreInventory.upgradeIdOf(id);
        expect(StoreInventory.parseUpgradeId(encoded), id);
      }
    });

    test('parseX returns null for unrelated prefixes', () {
      expect(StoreInventory.parseSkinId('trail:comet'), isNull);
      expect(StoreInventory.parseTrailId('garbage'), isNull);
    });

    test('every catalog item lands in allItems', () {
      final all = StoreInventory.allItems;
      // 9 skins + 7 trails + 5 shields + 6 deaths + 7 upgrades = 34
      expect(all.length, 9 + 7 + 5 + 6 + 7);
    });
  });

  group('Default-tier ownership', () {
    test('default skin is owned without any persisted state', () async {
      final ctx = _build();
      final id = StoreInventory.skinIdOf(SkinId.defaultOrb);
      expect(await ctx.repo.isOwned(id), isTrue);
      // Not in the explicit owned set.
      final owned = await ctx.repo.getOwnedItems();
      expect(owned, isEmpty);
    });

    test('default trail/shield/death effect all resolve as owned', () async {
      final ctx = _build();
      expect(await ctx.repo.isOwned(StoreInventory.trailIdOf(TrailId.default_)),
          isTrue);
      expect(
          await ctx.repo
              .isOwned(StoreInventory.shieldIdOf(ShieldSkinId.defaultBubble)),
          isTrue);
      expect(
          await ctx.repo
              .isOwned(StoreInventory.deathIdOf(DeathEffectId.defaultShatter)),
          isTrue);
    });
  });

  group('Cosmetic purchase', () {
    test('succeeds when balance is sufficient and persists ownership',
        () async {
      final ctx = _build(seedCoins: 500);
      final id = StoreInventory.skinIdOf(SkinId.fire);

      final result = await ctx.repo.purchaseItem(
          id, PlayerSkin.byId(SkinId.fire).coinCost);
      expect(result, PurchaseResult.purchased);
      expect(await ctx.repo.isOwned(id), isTrue);
      // 500 - 100 (fire skin cost) = 400 remaining.
      expect(await ctx.coin.getBalance(), 400);
    });

    test('throws InsufficientCoinsException when broke', () async {
      final ctx = _build(seedCoins: 50);
      final id = StoreInventory.skinIdOf(SkinId.fire);
      expect(
        () async => ctx.repo.purchaseItem(id, 300),
        throwsA(isA<InsufficientCoinsException>()),
      );
      // Item not added to owned set.
      expect(await ctx.repo.isOwned(id), isFalse);
      // Balance unchanged.
      expect(await ctx.coin.getBalance(), 50);
    });

    test('already-owned re-purchase short-circuits without spending', () async {
      final ctx = _build(seedCoins: 1000);
      final id = StoreInventory.skinIdOf(SkinId.fire);
      await ctx.repo.purchaseItem(id, 300);
      expect(await ctx.coin.getBalance(), 700);

      // Second buy at the same price — should refuse.
      final repeat = await ctx.repo.purchaseItem(id, 300);
      expect(repeat, PurchaseResult.alreadyOwned);
      expect(await ctx.coin.getBalance(), 700);
    });

    test('unknown item id is rejected with PurchaseResult.unknownItem',
        () async {
      final ctx = _build(seedCoins: 1000);
      final result = await ctx.repo.purchaseItem('skin:nonexistent', 100);
      expect(result, PurchaseResult.unknownItem);
      expect(await ctx.coin.getBalance(), 1000);
    });
  });

  group('Equip', () {
    test('updates the persisted equipped slot for each cosmetic category',
        () async {
      final ctx = _build(seedCoins: 10000);

      // Buy + equip a fire skin.
      final fireId = StoreInventory.skinIdOf(SkinId.fire);
      await ctx.repo.purchaseItem(fireId, 300);
      await ctx.repo.equipItem(fireId);
      expect(await ctx.repo.getEquippedSkin(), SkinId.fire);

      // Buy + equip a comet trail.
      final cometId = StoreInventory.trailIdOf(TrailId.comet);
      await ctx.repo.purchaseItem(cometId, 300);
      await ctx.repo.equipItem(cometId);
      expect(await ctx.repo.getEquippedTrail(), TrailId.comet);

      // Buy + equip a hex shield.
      final hexId = StoreInventory.shieldIdOf(ShieldSkinId.hex);
      await ctx.repo.purchaseItem(hexId, 400);
      await ctx.repo.equipItem(hexId);
      expect(await ctx.repo.getEquippedShield(), ShieldSkinId.hex);

      // Buy + equip a confetti death effect.
      final confettiId = StoreInventory.deathIdOf(DeathEffectId.confetti);
      await ctx.repo.purchaseItem(confettiId, 1500);
      await ctx.repo.equipItem(confettiId);
      expect(await ctx.repo.getEquippedDeathEffect(), DeathEffectId.confetti);
    });

    test('default values returned when nothing has been equipped', () async {
      final ctx = _build();
      expect(await ctx.repo.getEquippedSkin(), SkinId.defaultOrb);
      expect(await ctx.repo.getEquippedTrail(), TrailId.default_);
      expect(await ctx.repo.getEquippedShield(), ShieldSkinId.defaultBubble);
      expect(
          await ctx.repo.getEquippedDeathEffect(), DeathEffectId.defaultShatter);
    });

    test('equipping a default-tier item works without prior purchase',
        () async {
      final ctx = _build();
      // Default skin is implicitly owned — equip should succeed.
      await ctx.repo.equipItem(StoreInventory.skinIdOf(SkinId.defaultOrb));
      expect(await ctx.repo.getEquippedSkin(), SkinId.defaultOrb);
    });

    test('equipping an unowned item throws StateError', () async {
      final ctx = _build(seedCoins: 0);
      // Fire isn't owned and isn't default-tier.
      expect(
        () async =>
            ctx.repo.equipItem(StoreInventory.skinIdOf(SkinId.fire)),
        throwsA(isA<StateError>()),
      );
    });

    test('upgrade items cannot be equipped', () async {
      final ctx = _build(seedCoins: 5000);
      final upgradeId =
          StoreInventory.upgradeIdOf(PowerupUpgradeId.magnetRange);
      // Buying an upgrade adds nothing to the owned cosmetic set, so
      // equip should report unowned (StateError) regardless.
      await ctx.repo.purchaseUpgrade(upgradeId);
      expect(
        () async => ctx.repo.equipItem(upgradeId),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Upgrade purchases', () {
    test('starts at level 0 for every upgrade', () async {
      final ctx = _build();
      for (final u in PowerupUpgrade.catalog) {
        expect(await ctx.repo.getUpgradeLevelById(u.id), 0,
            reason: '${u.id} should start at level 0');
      }
    });

    test('progresses 0→1→2→3 then refuses further purchases', () async {
      final ctx = _build(seedCoins: 100000);
      final id = StoreInventory.upgradeIdOf(PowerupUpgradeId.magnetRange);
      final upgrade = PowerupUpgrade.byId(PowerupUpgradeId.magnetRange);

      // Drive through every level.
      for (int lvl = 1; lvl <= upgrade.maxLevel; lvl++) {
        final result = await ctx.repo.purchaseUpgrade(id);
        expect(result, PurchaseResult.purchased,
            reason: 'Level $lvl purchase should succeed');
        expect(await ctx.repo.getUpgradeLevel(id), lvl);
      }
      // Maxed — next call short-circuits.
      final after = await ctx.repo.purchaseUpgrade(id);
      expect(after, PurchaseResult.alreadyOwned);
      expect(await ctx.repo.getUpgradeLevel(id), upgrade.maxLevel);
    });

    test('debits the level-specific cost from the coin balance', () async {
      final ctx = _build(seedCoins: 5000);
      final id = StoreInventory.upgradeIdOf(PowerupUpgradeId.magnetRange);
      final upgrade = PowerupUpgrade.byId(PowerupUpgradeId.magnetRange);
      // Costs: 200, 500, 1000.
      await ctx.repo.purchaseUpgrade(id);
      expect(await ctx.coin.getBalance(), 5000 - upgrade.costPerLevel[0]);
      await ctx.repo.purchaseUpgrade(id);
      expect(
          await ctx.coin.getBalance(),
          5000 - upgrade.costPerLevel[0] - upgrade.costPerLevel[1]);
      await ctx.repo.purchaseUpgrade(id);
      expect(
          await ctx.coin.getBalance(),
          5000 -
              upgrade.costPerLevel[0] -
              upgrade.costPerLevel[1] -
              upgrade.costPerLevel[2]);
    });

    test('throws InsufficientCoinsException when broke mid-ladder', () async {
      final ctx = _build(seedCoins: 250);
      final id = StoreInventory.upgradeIdOf(PowerupUpgradeId.magnetRange);

      // Level 1 (200 coins) lands; Level 2 (500 coins) is too expensive.
      await ctx.repo.purchaseUpgrade(id);
      expect(await ctx.repo.getUpgradeLevel(id), 1);
      expect(
        () async => ctx.repo.purchaseUpgrade(id),
        throwsA(isA<InsufficientCoinsException>()),
      );
      // Level still 1.
      expect(await ctx.repo.getUpgradeLevel(id), 1);
    });

    test('unknown upgrade id is rejected', () async {
      final ctx = _build();
      final result =
          await ctx.repo.purchaseUpgrade('upgrade:notRealAtAll');
      expect(result, PurchaseResult.unknownItem);
    });
  });

  group('PowerupUpgrade table', () {
    test('every upgrade has matching cost + value array lengths', () {
      for (final u in PowerupUpgrade.catalog) {
        expect(u.costPerLevel, hasLength(u.maxLevel),
            reason: '${u.id} cost array length should match maxLevel');
        expect(u.valuePerLevel, hasLength(u.maxLevel + 1),
            reason: '${u.id} value array should have maxLevel + 1 entries');
      }
    });

    test('valueAtLevel clamps out-of-range inputs', () {
      final u = PowerupUpgrade.byId(PowerupUpgradeId.magnetRange);
      expect(u.valueAtLevel(-5), u.valuePerLevel.first);
      expect(u.valueAtLevel(99), u.valuePerLevel.last);
    });

    test('costForNextLevel returns 0 at max', () {
      final u = PowerupUpgrade.byId(PowerupUpgradeId.magnetRange);
      expect(u.costForNextLevel(u.maxLevel), 0);
    });
  });
}
