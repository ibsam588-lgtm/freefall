// models/iap_product.dart
//
// Phase 12 IAP catalog row. Pure data — no in_app_purchase imports —
// so the catalog can be exercised by tests without platform plugins.
//
// Six products: four coin packs (consumable), one no-ads unlock
// (non-consumable), and one VIP bundle (non-consumable). Per-product
// rewards live on the row so the credit logic is a single switch on
// the row, not a string-matched if/else inside [IapService].

import 'player_skin.dart';

class IapProduct {
  /// Stable platform identifier (Apple App Store / Google Play
  /// Console). Renaming this is a breaking change — existing receipts
  /// reference the old id.
  final String id;

  /// Player-facing title. Drives the store cell label.
  final String title;

  /// One-line marketing copy.
  final String description;

  /// Display price string. Falls back to this when the platform's
  /// localized [ProductDetails.price] hasn't loaded yet.
  final String price;

  /// Currency credited on a successful purchase. 0 for non-coin
  /// products (no_ads).
  final int coinReward;

  /// True for products that flip the no-ads flag in [SettingsService].
  final bool removesAds;

  /// Skin id unlocked on purchase. Null for products without a
  /// cosmetic component. The caller credits ownership via
  /// [StoreRepository] when this is set.
  final SkinId? skinUnlock;

  /// True for one-time non-consumable products. False for coin packs
  /// (which are consumed once delivered so the player can buy them
  /// again). Drives [IapService] between [InAppPurchase.buyConsumable]
  /// and [InAppPurchase.buyNonConsumable].
  final bool isNonConsumable;

  const IapProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.coinReward = 0,
    this.removesAds = false,
    this.skinUnlock,
    this.isNonConsumable = false,
  });

  // ---- product ids ---------------------------------------------------------

  static const String coinsStarterId = 'coins_starter';
  static const String coinsValueId = 'coins_value';
  static const String coinsMegaId = 'coins_mega';
  static const String coinsUltimateId = 'coins_ultimate';
  static const String noAdsId = 'no_ads';
  static const String vipBundleId = 'vip_bundle';

  /// Phase-12 ships exactly six products. Order matches store
  /// presentation (cheapest first; flagship VIP last).
  static const List<IapProduct> catalog = <IapProduct>[
    IapProduct(
      id: coinsStarterId,
      title: 'Starter Pack',
      description: '500 coins to kickstart your skin collection.',
      price: '\$0.99',
      coinReward: 500,
    ),
    IapProduct(
      id: coinsValueId,
      title: 'Value Pack',
      description: '2,000 coins — a dependable refill.',
      price: '\$2.99',
      coinReward: 2000,
    ),
    IapProduct(
      id: coinsMegaId,
      title: 'Mega Pack',
      description: '5,000 coins. Best per-coin rate without going VIP.',
      price: '\$4.99',
      coinReward: 5000,
    ),
    IapProduct(
      id: coinsUltimateId,
      title: 'Ultimate Pack',
      description: '12,000 coins. Buy out half the cosmetic catalog.',
      price: '\$9.99',
      coinReward: 12000,
    ),
    IapProduct(
      id: noAdsId,
      title: 'No Ads',
      description: 'Permanently disables interstitial ads.',
      price: '\$2.99',
      removesAds: true,
      isNonConsumable: true,
    ),
    IapProduct(
      id: vipBundleId,
      title: 'VIP Bundle',
      description: '20,000 coins, no ads forever, and the Golden skin.',
      price: '\$14.99',
      coinReward: 20000,
      removesAds: true,
      skinUnlock: SkinId.golden,
      isNonConsumable: true,
    ),
  ];

  /// Look up by platform id. Returns null for unknown ids — a stale
  /// receipt or a removed-in-a-future-release product should fall
  /// through gracefully (caller logs and skips the credit step).
  static IapProduct? byId(String id) {
    for (final p in catalog) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Set of every catalog id — what [IapService] passes to
  /// [InAppPurchase.queryProductDetails]. Built once at class init,
  /// not allocated per call.
  static final Set<String> catalogIds = {
    for (final p in catalog) p.id,
  };

  @override
  bool operator ==(Object other) =>
      other is IapProduct &&
      other.id == id &&
      other.coinReward == coinReward &&
      other.removesAds == removesAds &&
      other.skinUnlock == skinUnlock &&
      other.isNonConsumable == isNonConsumable;

  @override
  int get hashCode =>
      Object.hash(id, coinReward, removesAds, skinUnlock, isNonConsumable);

  @override
  String toString() => 'IapProduct(id=$id, coins=$coinReward, '
      'removesAds=$removesAds, skin=$skinUnlock)';
}
