// Phase-12 IAP service + product catalog tests.
//
// We can't drive the real `in_app_purchase` plugin from a unit test
// (it requires a host platform with billing client). Instead we
// exercise the pure reward-credit logic via [IapService.creditProduct]
// — that's the only path where the platform → Freefall translation
// happens, so it's the only path we need to assert on.
//
// What we verify:
//   * the catalog ships exactly the six products spec'd in Phase 12,
//   * each product id maps to the right coin reward,
//   * coin packs credit coins through CoinRepository,
//   * `no_ads` flips the SettingsService flag,
//   * `vip_bundle` credits 20k coins + flips no-ads + unlocks the
//     golden skin,
//   * a second creditProduct(no_ads) call doesn't double-flip the
//     flag (idempotent on the no-ads side).
//
// CoinRepository / StoreRepository use their existing in-memory
// fakes — same pattern as the Phase-7 / Phase-8 test suites.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freefall/models/iap_product.dart';
import 'package:freefall/models/player_skin.dart';
import 'package:freefall/repositories/coin_repository.dart';
import 'package:freefall/repositories/daily_login_repository.dart';
import 'package:freefall/repositories/store_repository.dart';
import 'package:freefall/services/iap_service.dart';
import 'package:freefall/services/settings_service.dart';
import 'package:freefall/store/store_inventory.dart';

class _Setup {
  final IapService iap;
  final CoinRepository coinRepo;
  final StoreRepository storeRepo;
  final SettingsService settings;
  _Setup(this.iap, this.coinRepo, this.storeRepo, this.settings);
}

Future<_Setup> _setup({int initialBalance = 0}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsService();
  await settings.load();

  final coinStorage = InMemoryCoinStorage();
  if (initialBalance > 0) {
    coinStorage.seed(CoinRepository.balanceKey, '$initialBalance');
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
  return _Setup(iap, coinRepo, storeRepo, settings);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IapProduct catalog', () {
    test('contains exactly six products', () {
      expect(IapProduct.catalog.length, 6);
    });

    test('every required spec id is present', () {
      const required = <String>{
        'coins_starter',
        'coins_value',
        'coins_mega',
        'coins_ultimate',
        'no_ads',
        'vip_bundle',
      };
      final actual = IapProduct.catalog.map((p) => p.id).toSet();
      expect(actual, required);
    });

    test('coin rewards match the spec table', () {
      const expected = <String, int>{
        'coins_starter': 500,
        'coins_value': 2000,
        'coins_mega': 5000,
        'coins_ultimate': 12000,
        'no_ads': 0,
        'vip_bundle': 20000,
      };
      for (final entry in expected.entries) {
        expect(IapProduct.byId(entry.key)?.coinReward, entry.value,
            reason: '${entry.key} should award ${entry.value} coins');
      }
    });

    test('non-consumables are flagged correctly', () {
      expect(IapProduct.byId('no_ads')?.isNonConsumable, isTrue);
      expect(IapProduct.byId('vip_bundle')?.isNonConsumable, isTrue);
      expect(IapProduct.byId('coins_starter')?.isNonConsumable, isFalse);
      expect(IapProduct.byId('coins_value')?.isNonConsumable, isFalse);
      expect(IapProduct.byId('coins_mega')?.isNonConsumable, isFalse);
      expect(IapProduct.byId('coins_ultimate')?.isNonConsumable, isFalse);
    });

    test('no_ads has removesAds flag, no skin, no coins', () {
      final p = IapProduct.byId('no_ads')!;
      expect(p.removesAds, isTrue);
      expect(p.skinUnlock, isNull);
      expect(p.coinReward, 0);
    });

    test('vip_bundle bundles coins + ads + skin', () {
      final p = IapProduct.byId('vip_bundle')!;
      expect(p.coinReward, 20000);
      expect(p.removesAds, isTrue);
      expect(p.skinUnlock, SkinId.golden);
      expect(p.isNonConsumable, isTrue);
    });

    test('byId returns null for unknown ids', () {
      expect(IapProduct.byId('not_a_real_product'), isNull);
    });

    test('catalogIds matches catalog', () {
      expect(IapProduct.catalogIds.length, IapProduct.catalog.length);
      expect(IapProduct.catalogIds,
          IapProduct.catalog.map((p) => p.id).toSet());
    });
  });

  group('creditProduct (pure reward logic)', () {
    test('coins_starter credits +500 coins', () async {
      final s = await _setup();
      final result = await s.iap
          .creditProduct(IapProduct.byId('coins_starter')!);
      expect(result.coinsCredited, 500);
      expect(result.noAdsActivated, isFalse);
      expect(result.skinUnlocked, isFalse);
      expect(await s.coinRepo.getBalance(), 500);
    });

    test('coins_value credits +2000', () async {
      final s = await _setup();
      await s.iap.creditProduct(IapProduct.byId('coins_value')!);
      expect(await s.coinRepo.getBalance(), 2000);
    });

    test('coins_mega credits +5000', () async {
      final s = await _setup();
      await s.iap.creditProduct(IapProduct.byId('coins_mega')!);
      expect(await s.coinRepo.getBalance(), 5000);
    });

    test('coins_ultimate credits +12000', () async {
      final s = await _setup();
      await s.iap.creditProduct(IapProduct.byId('coins_ultimate')!);
      expect(await s.coinRepo.getBalance(), 12000);
    });

    test('no_ads flips the SettingsService flag', () async {
      final s = await _setup();
      expect(s.settings.noAdsPurchased, isFalse);
      final result =
          await s.iap.creditProduct(IapProduct.byId('no_ads')!);
      expect(result.noAdsActivated, isTrue);
      expect(s.settings.noAdsPurchased, isTrue);
      expect(result.coinsCredited, 0);
    });

    test('no_ads is idempotent — second credit does NOT report a flip',
        () async {
      final s = await _setup();
      await s.iap.creditProduct(IapProduct.byId('no_ads')!);
      final result =
          await s.iap.creditProduct(IapProduct.byId('no_ads')!);
      expect(result.noAdsActivated, isFalse,
          reason: 'flag was already true from the first credit');
      expect(s.settings.noAdsPurchased, isTrue);
    });

    test('vip_bundle credits coins, flips ads, and unlocks the skin',
        () async {
      final s = await _setup();
      final result =
          await s.iap.creditProduct(IapProduct.byId('vip_bundle')!);
      expect(result.coinsCredited, 20000);
      expect(result.noAdsActivated, isTrue);
      expect(result.skinUnlocked, isTrue);

      expect(await s.coinRepo.getBalance(), 20000);
      expect(s.settings.noAdsPurchased, isTrue);
      expect(
          await s.storeRepo
              .isOwned(StoreInventory.skinIdOf(SkinId.golden)),
          isTrue);
    });

    test('vip_bundle skin unlock is idempotent', () async {
      final s = await _setup();
      await s.iap.creditProduct(IapProduct.byId('vip_bundle')!);
      final result =
          await s.iap.creditProduct(IapProduct.byId('vip_bundle')!);
      expect(result.skinUnlocked, isFalse,
          reason: 'skin was already owned from the first credit');
      // Coin balance keeps stacking — coin packs are consumable, the
      // skin/no-ads pieces are not. This matches platform behavior:
      // a real restore won't double-credit consumables.
      expect(await s.coinRepo.getBalance(), 40000);
    });

    test('IapCreditResult.didAnything is false for an empty result',
        () {
      expect(IapCreditResult.empty.didAnything, isFalse);
      expect(
        const IapCreditResult(
          coinsCredited: 0,
          noAdsActivated: false,
          skinUnlocked: false,
        ).didAnything,
        isFalse,
      );
    });

    test('IapCreditResult.didAnything is true when anything fires',
        () {
      expect(
        const IapCreditResult(
          coinsCredited: 100,
          noAdsActivated: false,
          skinUnlocked: false,
        ).didAnything,
        isTrue,
      );
      expect(
        const IapCreditResult(
          coinsCredited: 0,
          noAdsActivated: true,
          skinUnlocked: false,
        ).didAnything,
        isTrue,
      );
    });
  });

  group('priceFor / fallbacks', () {
    test('priceFor an uncached id falls back to the catalog string',
        () async {
      final s = await _setup();
      expect(s.iap.priceFor('coins_starter'), '\$0.99');
      expect(s.iap.priceFor('vip_bundle'), '\$14.99');
    });

    test('priceFor an unknown id returns empty', () async {
      final s = await _setup();
      expect(s.iap.priceFor('does_not_exist'), '');
    });
  });

  group('catalog wiring', () {
    test('IapService.catalog mirrors IapProduct.catalog', () async {
      final s = await _setup();
      expect(s.iap.catalog, IapProduct.catalog);
    });
  });
}
