// models/zone.dart
//
// Zone data model — a zone is a 1000m vertical band with its own visual
// identity (gradient, particle effects, ambient hazards). Five zones
// stack head-to-tail for a 5000m cycle, after which depth wraps back
// to the Stratosphere with a difficulty bump.
//
// Zone is a pure data type: no behavior, no Flame deps. ZoneManager owns
// the depth → zone mapping; ZoneBackground reads colors off Zone for
// rendering. Keeping it engine-agnostic makes test setup trivial.

import 'dart:ui';

enum ZoneType { stratosphere, city, underground, deepOcean, core }

class Zone {
  final ZoneType type;
  final String name;

  /// Gradient endpoint at the top of the zone (shallower depth).
  final Color topColor;

  /// Gradient endpoint at the bottom of the zone (deeper depth).
  final Color bottomColor;

  /// Accent color used for the zone-name flash glow and any zone-tinted
  /// UI elements. Picked to read as legible white text wash over the
  /// zone's bottom color.
  final Color accentColor;

  /// Shallow edge of this zone, in meters of depth.
  final double startDepth;

  /// Deep edge of this zone, in meters of depth. [endDepth] - [startDepth]
  /// is always [Zone.depthSpan] for the canonical 5-zone cycle.
  final double endDepth;

  const Zone({
    required this.type,
    required this.name,
    required this.topColor,
    required this.bottomColor,
    required this.accentColor,
    required this.startDepth,
    required this.endDepth,
  });

  /// Every zone is exactly this many meters deep. Phase-2 keeps this
  /// uniform so depth → zone is O(1) integer division.
  static const double depthSpan = 1000;

  /// Length of the gradient blend at the deep edge of every zone.
  /// During this slice we lerp into the *next* zone's gradient so the
  /// camera never crosses a hard color seam.
  static const double transitionDepth = 200;

  /// Total depth of one Zone cycle. After this, depth wraps and the
  /// difficulty multiplier ticks up.
  static const double cycleDepth = 5 * depthSpan;

  /// The canonical 5-zone cycle. Zones are listed in descend order —
  /// index 0 is the shallowest (Stratosphere), index 4 is the deepest
  /// (Core). After Core, ZoneManager wraps back to index 0.
  static const List<Zone> defaultCycle = [
    Zone(
      type: ZoneType.stratosphere,
      name: 'Stratosphere',
      topColor: Color(0xFF87CEEB),
      bottomColor: Color(0xFF4169E1),
      accentColor: Color(0xFFB3E0FF),
      startDepth: 0,
      endDepth: 1000,
    ),
    Zone(
      type: ZoneType.city,
      name: 'City',
      topColor: Color(0xFF1A1A2E),
      bottomColor: Color(0xFF0D0D1A),
      accentColor: Color(0xFFFF3DCB),
      startDepth: 1000,
      endDepth: 2000,
    ),
    Zone(
      type: ZoneType.underground,
      name: 'Underground',
      topColor: Color(0xFF8B4513),
      bottomColor: Color(0xFF3D1F00),
      accentColor: Color(0xFFFFB347),
      startDepth: 2000,
      endDepth: 3000,
    ),
    Zone(
      type: ZoneType.deepOcean,
      name: 'Deep Ocean',
      topColor: Color(0xFF003366),
      bottomColor: Color(0xFF001133),
      accentColor: Color(0xFF40E0D0),
      startDepth: 3000,
      endDepth: 4000,
    ),
    Zone(
      type: ZoneType.core,
      name: 'Core',
      topColor: Color(0xFF8B0000),
      bottomColor: Color(0xFF4A0000),
      accentColor: Color(0xFFFF6A00),
      startDepth: 4000,
      endDepth: 5000,
    ),
  ];
}
