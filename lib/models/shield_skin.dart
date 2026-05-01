// models/shield_skin.dart
//
// Cosmetic skin for the i-frame shield bubble. Five tiers, default
// unlocked. Pure data — Player's render layer reads [ShieldSkinId] to
// pick a paint routine. Stored selection lives in StoreRepository.

import 'dart:ui';

enum ShieldSkinId { defaultBubble, hex, ring, flame, matrix }

class ShieldSkin {
  final ShieldSkinId id;
  final String name;
  final int coinCost;

  /// Primary tint applied to the bubble fill / pulse.
  final Color primaryColor;

  /// Stroke color for the outer ring + accent details.
  final Color accentColor;

  const ShieldSkin({
    required this.id,
    required this.name,
    required this.coinCost,
    required this.primaryColor,
    required this.accentColor,
  });

  static const List<ShieldSkin> catalog = [
    ShieldSkin(
      id: ShieldSkinId.defaultBubble,
      name: 'Default Bubble',
      coinCost: 0,
      primaryColor: Color(0xFF80DEEA),
      accentColor: Color(0xFF40E0D0),
    ),
    ShieldSkin(
      id: ShieldSkinId.hex,
      name: 'Hex',
      coinCost: 400,
      primaryColor: Color(0xFF82B1FF),
      accentColor: Color(0xFF448AFF),
    ),
    ShieldSkin(
      id: ShieldSkinId.ring,
      name: 'Ring',
      coinCost: 600,
      primaryColor: Color(0xFFFFD180),
      accentColor: Color(0xFFFF9100),
    ),
    ShieldSkin(
      id: ShieldSkinId.flame,
      name: 'Flame',
      coinCost: 800,
      primaryColor: Color(0xFFFF8A65),
      accentColor: Color(0xFFFF3D00),
    ),
    ShieldSkin(
      id: ShieldSkinId.matrix,
      name: 'Matrix',
      coinCost: 1000,
      primaryColor: Color(0xFF69F0AE),
      accentColor: Color(0xFF00E676),
    ),
  ];

  static ShieldSkin byId(ShieldSkinId id) =>
      catalog.firstWhere((s) => s.id == id);

  static ShieldSkin get defaultSkin => catalog.first;
}
