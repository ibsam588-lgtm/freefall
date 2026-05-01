// services/iap_service.dart
//
// Phase 12 in-app-purchase facade. Wraps the
// `in_app_purchase` package — listens to its purchase stream,
// translates platform [PurchaseDetails] events into Freefall reward
// credits, and exposes a small API the store screen can call.
//
// Persistent state lives in already-existing repos:
//   * coin balance → CoinRepository.addCoins
//   * no-ads flag → SettingsService.setNoAdsPurchased
//   * skin unlock → StoreRepository owned-set (vip_bundle's golden skin)
//
// IAP testing: the real `InAppPurchase.instance` requires the
// platform plugins, which can't run in unit tests. We expose the
// reward-credit logic via [creditProduct] so tests can verify the
// pure mapping (productId → coin amount, no-ads flag, skin unlock)
// without mocking the platform layer.
//
// On a successful platform purchase, the stream listener routes:
//   * consumables (coin packs) → creditProduct + completePurchase
//   * non-consumables (no_ads, vip_bundle) → creditProduct + completePurchase
//   * pending → ignored (we'll see the resolved status next emission)
//   * error → onPurchaseError callback fires; nothing credited

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/iap_product.dart';
import '../repositories/coin_repository.dart';
import '../repositories/store_repository.dart';
import '../services/settings_service.dart';
import '../store/store_inventory.dart';

/// Outcome of a [creditProduct] call. Returned to the store screen so
/// it can surface a confirmation snackbar describing what landed.
class IapCreditResult {
  /// Coins credited to the player's balance (0 for non-coin products).
  final int coinsCredited;

  /// True iff the no-ads flag was flipped on by this credit.
  final bool noAdsActivated;

  /// True iff a previously-unowned skin was unlocked.
  final bool skinUnlocked;

  const IapCreditResult({
    required this.coinsCredited,
    required this.noAdsActivated,
    required this.skinUnlocked,
  });

  static const IapCreditResult empty = IapCreditResult(
    coinsCredited: 0,
    noAdsActivated: false,
    skinUnlocked: false,
  );

  bool get didAnything =>
      coinsCredited > 0 || noAdsActivated || skinUnlocked;
}

class IapService {
  final CoinRepository coinRepo;
  final StoreRepository storeRepo;
  final SettingsService settings;

  /// Override for tests. When null, the production code calls
  /// [InAppPurchase.instance] lazily on first access — that lazy
  /// gate matters because [InAppPurchase.instance] eagerly registers
  /// the Android billing platform, which throws on a host without a
  /// real BillingClient (e.g. unit tests). Tests that only exercise
  /// [creditProduct] never read [_iap], so they never trigger the
  /// platform registration.
  final InAppPurchase? _iapOverride;
  InAppPurchase get _iap => _iapOverride ?? InAppPurchase.instance;

  /// Fired after every successful platform purchase + credit.
  void Function(IapProduct product, IapCreditResult result)? onPurchase;

  /// Fired for purchase-stream errors (cancel / failure).
  void Function(String message)? onPurchaseError;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  /// Cached product details from the platform store. Empty until
  /// [loadProducts] resolves successfully.
  List<ProductDetails> _platformProducts = const [];
  List<ProductDetails> get platformProducts => _platformProducts;

  IapService({
    required this.coinRepo,
    required this.storeRepo,
    required this.settings,
    InAppPurchase? iap,
  }) : _iapOverride = iap;

  // ---- public API --------------------------------------------------------

  /// Catalog of every Freefall IAP. Static — comes from [IapProduct].
  List<IapProduct> get catalog => IapProduct.catalog;

  /// Subscribe to the platform purchase stream + query product
  /// details. Idempotent — repeated calls re-resolve products but
  /// only attach the listener once.
  Future<void> init() async {
    _purchaseSub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) {
        onPurchaseError?.call(e.toString());
      },
    );
    await loadProducts();
  }

  /// Query the platform for current localized prices/titles. Falls
  /// back to the catalog's display strings when the platform isn't
  /// available (web, headless tests).
  Future<List<ProductDetails>> loadProducts() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        _platformProducts = const [];
        return _platformProducts;
      }
      final response = await _iap.queryProductDetails(IapProduct.catalogIds);
      _platformProducts = response.productDetails;
      if (kDebugMode && response.notFoundIDs.isNotEmpty) {
        debugPrint(
            '[IapService] product ids missing from store: ${response.notFoundIDs}');
      }
      return _platformProducts;
    } catch (e) {
      if (kDebugMode) debugPrint('[IapService] loadProducts skipped: $e');
      _platformProducts = const [];
      return _platformProducts;
    }
  }

  /// Localized price string for [productId], falling back to the
  /// catalog default when the platform hasn't returned details.
  String priceFor(String productId) {
    for (final p in _platformProducts) {
      if (p.id == productId) return p.price;
    }
    final fallback = IapProduct.byId(productId);
    return fallback?.price ?? '';
  }

  /// Trigger the platform purchase flow for [productId]. Returns
  /// false if the catalog doesn't know the id, the store hasn't
  /// loaded, or the platform plugin throws.
  ///
  /// The actual reward credit happens later, via the purchase stream
  /// listener — UI should treat this as fire-and-forget.
  Future<bool> purchase(String productId) async {
    final product = IapProduct.byId(productId);
    if (product == null) return false;
    final platform = _platformProductFor(productId);
    if (platform == null) {
      if (kDebugMode) {
        debugPrint(
            '[IapService] purchase($productId) skipped — product not loaded');
      }
      return false;
    }
    final param = PurchaseParam(productDetails: platform);
    try {
      if (product.isNonConsumable) {
        return await _iap.buyNonConsumable(purchaseParam: param);
      } else {
        return await _iap.buyConsumable(purchaseParam: param);
      }
    } catch (e) {
      onPurchaseError?.call(e.toString());
      return false;
    }
  }

  /// Restore non-consumable purchases (no_ads, vip_bundle). Restored
  /// purchases land on the same purchase stream, so the listener
  /// re-credits them.
  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      onPurchaseError?.call(e.toString());
    }
  }

  /// Tear down the purchase-stream subscription. Idempotent.
  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    _purchaseSub = null;
  }

  // ---- credit logic (unit-testable, no platform IO) ----------------------

  /// Apply the rewards described by [product] to the persistent
  /// stores. Returns a summary of what landed. Called from the
  /// purchase-stream listener and directly from tests.
  Future<IapCreditResult> creditProduct(IapProduct product) async {
    var coins = 0;
    var noAds = false;
    var skin = false;

    if (product.coinReward > 0) {
      await coinRepo.addCoins(product.coinReward);
      coins = product.coinReward;
    }
    if (product.removesAds && !settings.noAdsPurchased) {
      await settings.setNoAdsPurchased(true);
      noAds = true;
    }
    final skinId = product.skinUnlock;
    if (skinId != null) {
      final inventoryId = StoreInventory.skinIdOf(skinId);
      if (!await storeRepo.isOwned(inventoryId)) {
        // The grant-by-id path lives in [StoreRepository]: a true
        // purchase via [purchaseItem] would charge coins, which we
        // don't want for an IAP unlock. We mark ownership directly
        // by passing 0-cost through purchaseItem — but coin spend
        // would still throw if the balance is < 0. Instead use the
        // owned-set primitive via _grantOwnership.
        await _grantOwnership(inventoryId);
        skin = true;
      }
    }
    return IapCreditResult(
      coinsCredited: coins,
      noAdsActivated: noAds,
      skinUnlocked: skin,
    );
  }

  // ---- internals ---------------------------------------------------------

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> updates) async {
    for (final update in updates) {
      switch (update.status) {
        case PurchaseStatus.pending:
          break; // wait for resolution
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          if (update.pendingCompletePurchase) {
            await _safeCompletePurchase(update);
          }
          onPurchaseError?.call(update.error?.message ?? update.status.name);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _resolveAndCredit(update);
          if (update.pendingCompletePurchase) {
            await _safeCompletePurchase(update);
          }
          break;
      }
    }
  }

  Future<void> _resolveAndCredit(PurchaseDetails update) async {
    final product = IapProduct.byId(update.productID);
    if (product == null) {
      if (kDebugMode) {
        debugPrint(
            '[IapService] purchase resolved for unknown id ${update.productID}');
      }
      return;
    }
    final result = await creditProduct(product);
    onPurchase?.call(product, result);
  }

  Future<void> _safeCompletePurchase(PurchaseDetails update) async {
    try {
      await _iap.completePurchase(update);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IapService] completePurchase skipped: $e');
      }
    }
  }

  ProductDetails? _platformProductFor(String id) {
    for (final p in _platformProducts) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Mark [inventoryId] as owned without spending coins. The
  /// [StoreRepository] doesn't expose a public grant-by-id path
  /// (purchases always go through coin-spend), so we re-use the
  /// owned-set encoding via direct storage write.
  Future<void> _grantOwnership(String inventoryId) async {
    final owned = await storeRepo.getOwnedItems();
    if (owned.contains(inventoryId)) return;
    owned.add(inventoryId);
    final raw = owned.join('\x1f');
    await storeRepo.storage.setString(StoreRepository.ownedKey, raw);
  }
}
