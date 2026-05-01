// Phase-15 store + IAP edge cases.
//
// store_repository_test covers the canonical purchase + equip flow.
// iap_service_test covers the IapProduct catalog. This file fills
// the corners called out in the Phase-15 spec:
//   * the VIP bundle's IAP credit grants the golden skin (we already
//     test this in iap_service_test, but include it here so the
//     store-edge surface is consolidated),
//   * equip refuses an unowned non-default skin with StateError,
//   * bumping an upgrade past level 3 returns alreadyOwned (no
//     extra spend, no level overflow),
//   * default-tier items resolve as owned without any persisted
//     state — even on a fresh install.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freefall/models/death_effect.dart';
import 'package:freefall/models/iap_product.dart';
import 'package:freefall/models/player_skin.dart';
import 'package:freefall/models/powerup_upgrade.dart';
import 'package:freefall/models/shield_skin.dart';
import 'package:freefall/models/trail_effect.dart';
import 'package:freefall/repositories/coin_repository.dart';
import 'package:freefall/repositories/daily_login_repository.dart';
import 'package:freefall/repositories/store_repository.dart';
import 'package:freefall/services/iap_service.dart';
import 'package:freefall/services/settings_service.dart';
import 'package:freefall/store/store_inventory.dart';

class _Harness {
  final StoreRepository storeRepo;
  final CoinRepository coinRepo;
  final SettingsService settings;
  final IapService iap;
  _Harness({
    required this.storeRepo,
    required this.coinRepo,
    required this.settings,
    required this.iap,
  });
}

Future<_Harness> _harness({int seedCoins = 0}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsService();
  await settings.load();

  final coinStorage = InMemoryCoinStorage();
  if (seedCoins > 0) {
    coinStorage.seed(CoinRepository.balanceKey, '$seedCoins');
  }
  final coinRepo = CoinRepository(storage: coinStorage);
  final storeRepo = StoreRepository(
    coinRepo: coinRepo,
    storage: InMemoryLoginStorage(),
  );
  final iap = IapService(
    coinRepo: coinRepo,
    storeRepo: storeRepo,
    settings: settings,
  );
  return _Harness(
    storeRepo: storeRepo,
    coinRepo: coinRepo,
    settings: settings,
    iap: iap,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VIP bundle grants golden skin', () {
    test('creditProduct(vip_bundle) marks the golden skin owned',
        () async {
      final h = await _harness();
      expect(
        await h.storeRepo
            .isOwned(StoreInventory.skinIdOf(SkinId.golden)),
        isFalse,
        reason: 'fresh install — golden skin is locked',
      );

      await h.iap.creditProduct(IapProduct.byId('vip_bundle')!);
      expect(
        await h.storeRepo
            .isOwned(StoreInventory.skinIdOf(SkinId.golden)),
        isTrue,
        reason: 'VIP bundle should grant the golden skin',
      );
    });

    test('VIP bundle credit also flips the no-ads flag and grants '
        '20k coins', () async {
      final h = await _harness();
      await h.iap.creditProduct(IapProduct.byId('vip_bundle')!);
      expect(h.settings.noAdsPurchased, isTrue);
      expect(await h.coinRepo.getBalance(), 20000);
    });
  });

  group('Equipping unowned items', () {
    test('equipItem on an unowned non-default skin throws StateError',
        () async {
      final h = await _harness();
      // Fire skin is paid (cost > 0) and not yet owned.
      final fireSkinId = StoreInventory.skinIdOf(SkinId.fire);
      expect(await h.storeRepo.isOwned(fireSkinId), isFalse);
      expect(
        () => h.storeRepo.equipItem(fireSkinId),
        throwsA(isA<StateError>()),
      );
    });

    test('equipItem on a fully unknown id throws StateError', () async {
      final h = await _harness();
      expect(
        () => h.storeRepo.equipItem('skin:not_a_real_skin'),
        throwsA(isA<StateError>()),
      );
    });

    test('equipItem on a default-tier skin works without any prior '
        'purchase', () async {
      final h = await _harness();
      final defaultSkin = StoreInventory.skinIdOf(SkinId.defaultOrb);
      expect(await h.storeRepo.isOwned(defaultSkin), isTrue);
      // Should NOT throw.
      await h.storeRepo.equipItem(defaultSkin);
      expect(await h.storeRepo.getEquippedSkin(), SkinId.defaultOrb);
    });
  });

  group('Upgrade level cap', () {
    test('upgrades stop at maxLevel (3) and refuse further purchases',
        () async {
      final magnet = PowerupUpgrade.byId(PowerupUpgradeId.magnetRange);
      final maxCost = magnet.costPerLevel
          .fold<int>(0, (acc, cost) => acc + cost);
      // Seed enough coins to cover all three levels — and then some.
      final h = await _harness(seedCoins: maxCost * 2);

      final upgradeId =
          StoreInventory.upgradeIdOf(PowerupUpgradeId.magnetRange);

      // Three successful purchases — 0 → 1 → 2 → 3.
      for (var i = 0; i < magnet.maxLevel; i++) {
        final result = await h.storeRepo.purchaseUpgrade(upgradeId);
        expect(result, PurchaseResult.purchased,
            reason: 'level ${i + 1} should succeed');
      }
      expect(await h.storeRepo.getUpgradeLevel(upgradeId), 3);

      // Fourth attempt — should report alreadyOwned, not purchased.
      final overflow = await h.storeRepo.purchaseUpgrade(upgradeId);
      expect(overflow, PurchaseResult.alreadyOwned);
      expect(await h.storeRepo.getUpgradeLevel(upgradeId), 3,
          reason: 'level should not overflow past the cap');
    });

    test('PowerupUpgrade.costForNextLevel returns 0 once maxed', () {
      final magnet = PowerupUpgrade.byId(PowerupUpgradeId.magnetRange);
      expect(magnet.costForNextLevel(magnet.maxLevel), 0);
      expect(magnet.costForNextLevel(magnet.maxLevel + 1), 0);
    });
  });

  group('Default-tier items are owned implicitly', () {
    test('default skin / trail / shield / death effect resolve as '
        'owned without any persisted state', () async {
      final h = await _harness();
      expect(
        await h.storeRepo
            .isOwned(StoreInventory.skinIdOf(SkinId.defaultOrb)),
        isTrue,
      );
      expect(
        await h.storeRepo
            .isOwned(StoreInventory.trailIdOf(TrailId.default_)),
        isTrue,
      );
      expect(
        await h.storeRepo
            .isOwned(StoreInventory.shieldIdOf(ShieldSkinId.defaultBubble)),
        isTrue,
      );
      expect(
        await h.storeRepo.isOwned(
            StoreInventory.deathIdOf(DeathEffectId.defaultShatter)),
        isTrue,
      );
    });

    test('default items don\'t live in the explicit owned set', () async {
      final h = await _harness();
      final ownedSet = await h.storeRepo.getOwnedItems();
      expect(ownedSet, isEmpty,
          reason: 'default-tier items are owned implicitly via the '
              'isDefaultTier check, not via persistence');
    });

    test('a default item is equipped on a fresh install (zero-config)',
        () async {
      final h = await _harness();
      expect(await h.storeRepo.getEquippedSkin(), SkinId.defaultOrb);
      expect(await h.storeRepo.getEquippedTrail(), TrailId.default_);
      expect(await h.storeRepo.getEquippedShield(),
          ShieldSkinId.defaultBubble);
      expect(await h.storeRepo.getEquippedDeathEffect(),
          DeathEffectId.defaultShatter);
    });
  });
}
