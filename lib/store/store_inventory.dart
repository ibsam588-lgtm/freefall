// store/store_inventory.dart
//
// Single registry of every purchasable item the store can show. Each
// catalog (skins/trails/shields/death-effects/upgrades) lives in its
// own model file; this file just knits them together with stable
// string IDs so a single Set<String> in StoreRepository can track
// "what's owned" across all categories.
//
// ID scheme:
//   skin:<SkinId.name>            e.g. skin:fire
//   trail:<TrailId.name>          e.g. trail:helix
//   shield:<ShieldSkinId.name>    e.g. shield:hex
//   death:<DeathEffectId.name>    e.g. death:explosion
//   upgrade:<PowerupUpgradeId.name>  e.g. upgrade:magnetRange
//
// Default-tier items (cost 0) are treated as owned implicitly —
// StoreRepository.isOwned() returns true for them without any
// persisted state. This keeps the "first run" experience clean (the
// default skin, default trail, etc. just work).

import '../models/death_effect.dart';
import '../models/player_skin.dart';
import '../models/powerup_upgrade.dart';
import '../models/shield_skin.dart';
import '../models/trail_effect.dart';

/// Coarse category grouping for the store's tab bar.
enum StoreCategory {
  skins,
  trails,
  shields,
  deathEffects,
  upgrades,
  coinPacks,
}

/// One unit a player can buy. Cosmetic items map 1-1 from a model row;
/// upgrades are represented as a single entry whose level state lives
/// in StoreRepository.
class StoreItem {
  final String id;
  final String name;
  final int coinCost;
  final StoreCategory category;

  /// Optional sub-category descriptor that store cells can render —
  /// e.g. "Skin", "Trail", "Lvl 2".
  final String tag;

  const StoreItem({
    required this.id,
    required this.name,
    required this.coinCost,
    required this.category,
    this.tag = '',
  });

  /// True for default-tier items (cost 0). They never appear in the
  /// purchased-set; isOwned returns true for them regardless.
  bool get isDefaultTier => coinCost == 0;
}

class StoreInventory {
  // ---- ID prefixes (public so tests / callers don't drift) ----------------

  static const String skinPrefix = 'skin:';
  static const String trailPrefix = 'trail:';
  static const String shieldPrefix = 'shield:';
  static const String deathPrefix = 'death:';
  static const String upgradePrefix = 'upgrade:';

  // ---- ID builders --------------------------------------------------------

  static String skinIdOf(SkinId id) => '$skinPrefix${id.name}';
  static String trailIdOf(TrailId id) => '$trailPrefix${id.name}';
  static String shieldIdOf(ShieldSkinId id) => '$shieldPrefix${id.name}';
  static String deathIdOf(DeathEffectId id) => '$deathPrefix${id.name}';
  static String upgradeIdOf(PowerupUpgradeId id) =>
      '$upgradePrefix${id.name}';

  // ---- ID parsers — useful for the store screen to render category cells.

  static SkinId? parseSkinId(String id) =>
      _parse(id, skinPrefix, SkinId.values);
  static TrailId? parseTrailId(String id) =>
      _parse(id, trailPrefix, TrailId.values);
  static ShieldSkinId? parseShieldId(String id) =>
      _parse(id, shieldPrefix, ShieldSkinId.values);
  static DeathEffectId? parseDeathId(String id) =>
      _parse(id, deathPrefix, DeathEffectId.values);
  static PowerupUpgradeId? parseUpgradeId(String id) =>
      _parse(id, upgradePrefix, PowerupUpgradeId.values);

  static T? _parse<T extends Enum>(String id, String prefix, List<T> values) {
    if (!id.startsWith(prefix)) return null;
    final name = id.substring(prefix.length);
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  // ---- Catalogs flattened to StoreItem lists ------------------------------

  static List<StoreItem> get skinItems => [
        for (final s in PlayerSkin.catalog)
          StoreItem(
            id: skinIdOf(s.id),
            name: s.name,
            coinCost: s.coinCost,
            category: StoreCategory.skins,
            tag: 'Skin',
          ),
      ];

  static List<StoreItem> get trailItems => [
        for (final t in TrailEffect.catalog)
          StoreItem(
            id: trailIdOf(t.id),
            name: t.name,
            coinCost: t.coinCost,
            category: StoreCategory.trails,
            tag: 'Trail',
          ),
      ];

  static List<StoreItem> get shieldItems => [
        for (final s in ShieldSkin.catalog)
          StoreItem(
            id: shieldIdOf(s.id),
            name: s.name,
            coinCost: s.coinCost,
            category: StoreCategory.shields,
            tag: 'Shield',
          ),
      ];

  static List<StoreItem> get deathEffectItems => [
        for (final d in DeathEffect.catalog)
          StoreItem(
            id: deathIdOf(d.id),
            name: d.name,
            coinCost: d.coinCost,
            category: StoreCategory.deathEffects,
            tag: 'Death FX',
          ),
      ];

  /// Upgrade store row — one per [PowerupUpgrade]. Cost is the
  /// *next-level* price, but the screen still has to compute that
  /// from the current saved level. We export the level-1 cost here
  /// as a sane default ([coinCost] just gates the "Buy" button when
  /// the screen has no live level info).
  static List<StoreItem> get upgradeItems => [
        for (final u in PowerupUpgrade.catalog)
          StoreItem(
            id: upgradeIdOf(u.id),
            name: u.name,
            coinCost: u.costPerLevel.first,
            category: StoreCategory.upgrades,
            tag: 'Upgrade',
          ),
      ];

  /// All purchasable items, in store presentation order. Coin-pack
  /// IAP entries are intentionally NOT included — they live in the
  /// store_screen as stub buttons (Phase 12 wires the real IAP).
  static List<StoreItem> get allItems => [
        ...skinItems,
        ...trailItems,
        ...shieldItems,
        ...deathEffectItems,
        ...upgradeItems,
      ];

  /// Pull every entry whose [StoreItem.category] matches [c].
  static List<StoreItem> itemsForCategory(StoreCategory c) {
    switch (c) {
      case StoreCategory.skins:
        return skinItems;
      case StoreCategory.trails:
        return trailItems;
      case StoreCategory.shields:
        return shieldItems;
      case StoreCategory.deathEffects:
        return deathEffectItems;
      case StoreCategory.upgrades:
        return upgradeItems;
      case StoreCategory.coinPacks:
        return const [];
    }
  }

  /// Look up by stable id. Returns null for unknown ids — a bad save
  /// or a removed-in-a-future-release id should fall through gracefully.
  static StoreItem? itemById(String id) {
    for (final i in allItems) {
      if (i.id == id) return i;
    }
    return null;
  }
}
