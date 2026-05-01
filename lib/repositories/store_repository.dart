// repositories/store_repository.dart
//
// Authoritative store state. Tracks:
//   * which items the player owns (set of stable IDs),
//   * which item is equipped per cosmetic slot (skin/trail/shield/death),
//   * upgrade level (0..3) per PowerupUpgrade.
//
// Coin debits go through [CoinRepository.spendCoins] so the secure
// balance stays the only source of truth for currency. The store
// repo never edits the balance directly — it just refuses purchases
// when CoinRepository throws InsufficientCoinsException.
//
// Storage layout: everything lands in SharedPreferences. The owned
// set is serialized as a `\x1f`-separated string (a private ASCII
// delimiter so item IDs never collide). Equipped slots are simple
// strings; upgrade levels are ints keyed `upgrade_lvl:<id>`.
//
// Default-tier items (cost 0) are owned implicitly — the repo
// returns true from [isOwned] without persisting anything.

import '../models/death_effect.dart';
import '../models/player_skin.dart';
import '../models/powerup_upgrade.dart';
import '../models/shield_skin.dart';
import '../models/trail_effect.dart';
import '../store/store_inventory.dart';
import 'coin_repository.dart';
import 'daily_login_repository.dart';

/// Outcome of a purchase. The screen branches on this — celebration
/// on [purchased], snack on [insufficient], no-op on [alreadyOwned]
/// or [unknownItem].
enum PurchaseResult { purchased, insufficient, alreadyOwned, unknownItem }

class StoreRepository {
  // ---- storage keys -------------------------------------------------------

  static const String ownedKey = 'store_owned_items';
  static const String equippedSkinKey = 'equipped_skin';
  static const String equippedTrailKey = 'equipped_trail';
  static const String equippedShieldKey = 'equipped_shield';
  static const String equippedDeathKey = 'equipped_death_effect';
  static const String upgradeLevelPrefix = 'upgrade_lvl:';

  /// Delimiter for the owned set. Unit Separator (0x1f) — never
  /// appears in well-formed item IDs.
  static const String _ownedDelimiter = '\x1f';

  final LoginStorage storage;
  final CoinRepository coinRepo;

  StoreRepository({
    required this.coinRepo,
    LoginStorage? storage,
  }) : storage = storage ?? SharedPreferencesLoginStorage();

  // ---- ownership ----------------------------------------------------------

  /// All explicitly-owned item IDs. Default-tier items are NOT in this
  /// set — [isOwned] resolves them implicitly.
  Future<Set<String>> getOwnedItems() async {
    final raw = await storage.getString(ownedKey);
    if (raw == null || raw.isEmpty) return <String>{};
    return raw.split(_ownedDelimiter).where((s) => s.isNotEmpty).toSet();
  }

  /// True if [itemId] is owned. Default-tier items (cost 0) always
  /// resolve to true — the player doesn't have to "buy" the default
  /// skin on a fresh install.
  Future<bool> isOwned(String itemId) async {
    final item = StoreInventory.itemById(itemId);
    if (item != null && item.isDefaultTier) return true;
    final owned = await getOwnedItems();
    return owned.contains(itemId);
  }

  // ---- purchases ----------------------------------------------------------

  /// Buy [itemId] at [cost]. Throws [InsufficientCoinsException] if the
  /// balance can't cover it. Returns [PurchaseResult] otherwise.
  ///
  /// Idempotent: buying an already-owned item is a no-op (returns
  /// [PurchaseResult.alreadyOwned]). The store screen filters this
  /// out before even calling, but we double-guard so a flaky tap
  /// can't double-charge.
  Future<PurchaseResult> purchaseItem(String itemId, int cost) async {
    final item = StoreInventory.itemById(itemId);
    if (item == null) return PurchaseResult.unknownItem;
    if (await isOwned(itemId)) return PurchaseResult.alreadyOwned;

    // Throws InsufficientCoinsException if the balance is too low.
    await coinRepo.spendCoins(cost);

    final owned = await getOwnedItems();
    owned.add(itemId);
    await _writeOwned(owned);
    return PurchaseResult.purchased;
  }

  /// Equip [itemId]. Caller is responsible for verifying ownership
  /// first; a non-owned ID is rejected here as a defense-in-depth check.
  /// Throws [StateError] for unknown IDs.
  Future<void> equipItem(String itemId) async {
    final item = StoreInventory.itemById(itemId);
    if (item == null) {
      throw StateError('Unknown item id: $itemId');
    }
    if (!await isOwned(itemId)) {
      throw StateError('Cannot equip unowned item: $itemId');
    }
    switch (item.category) {
      case StoreCategory.skins:
        await storage.setString(equippedSkinKey, itemId);
        return;
      case StoreCategory.trails:
        await storage.setString(equippedTrailKey, itemId);
        return;
      case StoreCategory.shields:
        await storage.setString(equippedShieldKey, itemId);
        return;
      case StoreCategory.deathEffects:
        await storage.setString(equippedDeathKey, itemId);
        return;
      case StoreCategory.upgrades:
      case StoreCategory.coinPacks:
        throw StateError('Items in ${item.category.name} are not equippable');
    }
  }

  // ---- equipped slots -----------------------------------------------------

  Future<SkinId> getEquippedSkin() async {
    final raw = await storage.getString(equippedSkinKey);
    return StoreInventory.parseSkinId(raw ?? '') ?? SkinId.defaultOrb;
  }

  Future<TrailId> getEquippedTrail() async {
    final raw = await storage.getString(equippedTrailKey);
    return StoreInventory.parseTrailId(raw ?? '') ?? TrailId.default_;
  }

  Future<ShieldSkinId> getEquippedShield() async {
    final raw = await storage.getString(equippedShieldKey);
    return StoreInventory.parseShieldId(raw ?? '') ??
        ShieldSkinId.defaultBubble;
  }

  Future<DeathEffectId> getEquippedDeathEffect() async {
    final raw = await storage.getString(equippedDeathKey);
    return StoreInventory.parseDeathId(raw ?? '') ??
        DeathEffectId.defaultShatter;
  }

  // ---- upgrades -----------------------------------------------------------

  /// Current level (0..3) for [upgradeId]. 0 means not bought.
  Future<int> getUpgradeLevel(String upgradeId) async {
    return storage.getInt('$upgradeLevelPrefix$upgradeId');
  }

  /// Upgrade level for a [PowerupUpgradeId]. Convenience over the
  /// stringly-typed API above.
  Future<int> getUpgradeLevelById(PowerupUpgradeId id) =>
      getUpgradeLevel(StoreInventory.upgradeIdOf(id));

  /// Bump [upgradeId] up by one level. Throws
  /// [InsufficientCoinsException] when the balance can't cover the
  /// next tier; returns [PurchaseResult.alreadyOwned] when the upgrade
  /// is already maxed.
  ///
  /// Cost is read from the catalog; the store screen does NOT pass it
  /// in (different from cosmetic purchases) because the cost depends
  /// on the current level which the repo owns.
  Future<PurchaseResult> purchaseUpgrade(String upgradeId) async {
    final pid = StoreInventory.parseUpgradeId(upgradeId);
    if (pid == null) return PurchaseResult.unknownItem;
    final upgrade = PowerupUpgrade.byId(pid);
    final current = await getUpgradeLevel(upgradeId);
    if (current >= upgrade.maxLevel) return PurchaseResult.alreadyOwned;

    final cost = upgrade.costForNextLevel(current);
    await coinRepo.spendCoins(cost);

    await storage.setInt('$upgradeLevelPrefix$upgradeId', current + 1);
    return PurchaseResult.purchased;
  }

  // ---- internals ----------------------------------------------------------

  Future<void> _writeOwned(Set<String> owned) async {
    final encoded = owned.join(_ownedDelimiter);
    await storage.setString(ownedKey, encoded);
  }
}
