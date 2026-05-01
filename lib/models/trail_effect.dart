// models/trail_effect.dart
//
// Cosmetic trail definitions for the player. The TrailEffect is pure
// data — the visual is rendered by PlayerTrail, which switches on
// [TrailId] to pick a draw routine.

/// Stable identifier for a trail. `default_` and `void` collide with
/// reserved Dart names, so we suffix `default_` and avoid `void` here.
enum TrailId { default_, comet, helix, sparkle, glitch, ghost, warp }

class TrailEffect {
  final TrailId id;
  final String name;

  /// Coin price in the store. 0 means unlocked by default.
  final int coinCost;

  /// Number of trail samples to retain. Trails with longer tails read
  /// better at high fall speeds; sparse trails (sparkle, ghost) keep
  /// counts low so each element can be sized larger without overdraw.
  final int sampleCount;

  /// Suggested base alpha at the head of the trail. Per-effect, since a
  /// faint ghost wants ~0.25 while a hot comet wants near-opaque.
  final double headAlpha;

  /// Whether this effect uses an animated phase (e.g. sparkle rotation,
  /// glitch flicker, helix sine wave). Renderer reads this to decide
  /// whether to advance an internal clock.
  final bool animated;

  const TrailEffect({
    required this.id,
    required this.name,
    required this.coinCost,
    required this.sampleCount,
    required this.headAlpha,
    required this.animated,
  });

  static const List<TrailEffect> catalog = [
    TrailEffect(
      id: TrailId.default_,
      name: 'Default',
      coinCost: 0,
      sampleCount: 15,
      headAlpha: 0.6,
      animated: false,
    ),
    TrailEffect(
      id: TrailId.comet,
      name: 'Comet',
      coinCost: 300,
      sampleCount: 20,
      headAlpha: 0.85,
      animated: false,
    ),
    TrailEffect(
      id: TrailId.helix,
      name: 'Helix',
      coinCost: 500,
      sampleCount: 24,
      headAlpha: 0.7,
      animated: true,
    ),
    TrailEffect(
      id: TrailId.sparkle,
      name: 'Sparkle',
      coinCost: 800,
      sampleCount: 10,
      headAlpha: 0.9,
      animated: true,
    ),
    TrailEffect(
      id: TrailId.glitch,
      name: 'Glitch',
      coinCost: 1000,
      sampleCount: 14,
      headAlpha: 0.7,
      animated: true,
    ),
    TrailEffect(
      id: TrailId.ghost,
      name: 'Ghost',
      coinCost: 1000,
      sampleCount: 12,
      headAlpha: 0.4,
      animated: false,
    ),
    TrailEffect(
      id: TrailId.warp,
      name: 'Warp',
      coinCost: 1500,
      sampleCount: 18,
      headAlpha: 0.75,
      animated: false,
    ),
  ];

  static TrailEffect byId(TrailId id) =>
      catalog.firstWhere((t) => t.id == id);

  static TrailEffect get defaultTrail => catalog.first;
}
