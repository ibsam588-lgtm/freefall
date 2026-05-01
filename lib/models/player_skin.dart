// models/player_skin.dart
//
// Cosmetic skin definitions for the player orb. A skin bundles three
// colors — primary (orb body), glow (halo + zone-tint blend target),
// and trail (motion trail base) — plus a coin price for the store.
//
// Skins are pure data; rendering is owned by Player and PlayerTrail.
// IDs are stable across releases so save files keep working.

import 'dart:ui';

/// Stable identifier for a skin. `void_` is suffixed because `void` is
/// a reserved keyword in Dart; the public-facing name is "Void".
enum SkinId { defaultOrb, fire, ice, electric, shadow, rainbow, neon, void_, golden }

class PlayerSkin {
  final SkinId id;
  final String name;
  final Color primaryColor;
  final Color glowColor;
  final Color trailColor;

  /// Coin price in the store. 0 means unlocked by default.
  final int coinCost;

  const PlayerSkin({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.glowColor,
    required this.trailColor,
    required this.coinCost,
  });

  /// Canonical skin catalog. Order matches store presentation order
  /// (cheapest first within tiers, default always first).
  static const List<PlayerSkin> catalog = [
    PlayerSkin(
      id: SkinId.defaultOrb,
      name: 'Default',
      primaryColor: Color(0xFFFFFFFF),
      glowColor: Color(0xFFFFFFFF),
      trailColor: Color(0xFFFFFFFF),
      coinCost: 0,
    ),
    PlayerSkin(
      id: SkinId.fire,
      name: 'Fire',
      primaryColor: Color(0xFFFF6A00),
      glowColor: Color(0xFFFFB347),
      trailColor: Color(0xFFFF3D00),
      coinCost: 300,
    ),
    PlayerSkin(
      id: SkinId.ice,
      name: 'Ice',
      primaryColor: Color(0xFFB3E5FC),
      glowColor: Color(0xFF40E0D0),
      trailColor: Color(0xFF80DEEA),
      coinCost: 300,
    ),
    PlayerSkin(
      id: SkinId.electric,
      name: 'Electric',
      primaryColor: Color(0xFFFFFF66),
      glowColor: Color(0xFFFFEB3B),
      trailColor: Color(0xFF82B1FF),
      coinCost: 500,
    ),
    PlayerSkin(
      id: SkinId.shadow,
      name: 'Shadow',
      primaryColor: Color(0xFF2A2A3A),
      glowColor: Color(0xFF6A1B9A),
      trailColor: Color(0xFF4A148C),
      coinCost: 800,
    ),
    PlayerSkin(
      id: SkinId.rainbow,
      name: 'Rainbow',
      primaryColor: Color(0xFFFF4081),
      glowColor: Color(0xFFE040FB),
      trailColor: Color(0xFF40C4FF),
      coinCost: 1500,
    ),
    PlayerSkin(
      id: SkinId.neon,
      name: 'Neon',
      primaryColor: Color(0xFF39FF14),
      glowColor: Color(0xFFCCFF00),
      trailColor: Color(0xFFFF00E5),
      coinCost: 1500,
    ),
    PlayerSkin(
      id: SkinId.void_,
      name: 'Void',
      primaryColor: Color(0xFF0A0A14),
      glowColor: Color(0xFF7B1FA2),
      trailColor: Color(0xFF311B92),
      coinCost: 3000,
    ),
    PlayerSkin(
      id: SkinId.golden,
      name: 'Golden',
      primaryColor: Color(0xFFFFD700),
      glowColor: Color(0xFFFFC107),
      trailColor: Color(0xFFFFAB00),
      coinCost: 5000,
    ),
  ];

  static PlayerSkin byId(SkinId id) =>
      catalog.firstWhere((s) => s.id == id);

  static PlayerSkin get defaultSkin => catalog.first;
}
