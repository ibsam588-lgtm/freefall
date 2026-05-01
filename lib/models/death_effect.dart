// models/death_effect.dart
//
// Cosmetic skin for the death/respawn particle burst. Six tiers,
// default unlocked. Engine-agnostic — PlayerParticleSystem reads the
// id to pick a behavior preset (radial shatter, spiral collapse, etc).

import 'dart:ui';

enum DeathEffectId {
  defaultShatter,
  explosion,
  dissolve,
  glitchOut,
  blackHole,
  confetti,
}

class DeathEffect {
  final DeathEffectId id;
  final String name;
  final int coinCost;

  /// Number of particles in the burst. Bigger numbers feel more
  /// dramatic but cost more frame time on low-end devices — capped
  /// at 120 so the per-frame budget stays under ~2ms.
  final int particleCount;

  /// Primary tint. Some effects (Confetti) ignore this and pick
  /// random hues per particle; the field still has to be defined for
  /// the catalog row.
  final Color tint;

  const DeathEffect({
    required this.id,
    required this.name,
    required this.coinCost,
    required this.particleCount,
    required this.tint,
  });

  static const List<DeathEffect> catalog = [
    DeathEffect(
      id: DeathEffectId.defaultShatter,
      name: 'Default Shatter',
      coinCost: 0,
      particleCount: 60,
      tint: Color(0xFFFFFFFF),
    ),
    DeathEffect(
      id: DeathEffectId.explosion,
      name: 'Explosion',
      coinCost: 500,
      particleCount: 90,
      tint: Color(0xFFFF6A00),
    ),
    DeathEffect(
      id: DeathEffectId.dissolve,
      name: 'Dissolve',
      coinCost: 800,
      particleCount: 80,
      tint: Color(0xFF80DEEA),
    ),
    DeathEffect(
      id: DeathEffectId.glitchOut,
      name: 'Glitch Out',
      coinCost: 1000,
      particleCount: 100,
      tint: Color(0xFFFF00E5),
    ),
    DeathEffect(
      id: DeathEffectId.blackHole,
      name: 'Black Hole',
      coinCost: 1200,
      particleCount: 110,
      tint: Color(0xFF7B1FA2),
    ),
    DeathEffect(
      id: DeathEffectId.confetti,
      name: 'Confetti',
      coinCost: 1500,
      particleCount: 120,
      tint: Color(0xFFFFD600),
    ),
  ];

  static DeathEffect byId(DeathEffectId id) =>
      catalog.firstWhere((e) => e.id == id);

  static DeathEffect get defaultEffect => catalog.first;
}
