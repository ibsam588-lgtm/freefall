// components/collectibles/gem.dart
//
// Visual gem Flame component. Three tiers (bronze/silver/gold) drawn as
// a rotating diamond polygon (rotated square with stretched vertical
// axis). Gems glow brighter than coins to telegraph their higher value
// and rarer spawn rate.
//
// Like Coin, the world scrolls past the gem; movement during magnet
// pickup is mutated externally on [position].

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/collectible.dart';

class Gem extends PositionComponent {
  /// Full rotations per second.
  static const double rotationHz = 0.4;

  /// Visual half-extent (vertical axis is 1.4× this for a tall diamond).
  static const double halfWidth = 9;

  /// Per-tier color palette.
  static Color colorFor(GemType t) => switch (t) {
        GemType.bronze => const Color(0xFFFF8C00), // dark-orange
        GemType.silver => const Color(0xFF87CEFA), // light-blue
        GemType.gold => const Color(0xFFFFEA00), // bright-yellow
      };

  GemType gemType;
  final String collectibleId;
  final String collectSound;
  bool collected = false;

  double _angle = 0;

  Gem({
    required this.collectibleId,
    required this.gemType,
    required Vector2 worldPosition,
    double? initialAngle,
  })  : collectSound = 'gem_${gemType.name}',
        super(
          position: worldPosition,
          // Bounding box is the AABB of the diamond's circumscribing rect.
          size: Vector2(halfWidth * 2, halfWidth * 2 * 1.4),
          anchor: Anchor.center,
        ) {
    _angle = initialAngle ?? 0;
  }

  /// Currency value (also serves as score increment).
  int get value => GemValue.forType(gemType);

  @override
  void update(double dt) {
    super.update(dt);
    _angle += rotationHz * math.pi * 2 * dt;
  }

  @override
  void render(Canvas canvas) {
    if (collected) return;

    final cx = size.x / 2;
    final cy = size.y / 2;
    final center = Offset(cx, cy);
    final color = colorFor(gemType);

    // Outer glow — bigger and brighter than coins to reinforce gem's
    // higher value rarity.
    const glowR = halfWidth * 3.2;
    final glowRect = Rect.fromCircle(center: center, radius: glowR);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.7),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(glowRect);
    canvas.drawCircle(center, glowR, glowPaint);

    // Diamond polygon: 4 vertices rotated by [_angle]. Vertical axis is
    // taller than horizontal so the shape reads as a cut gem, not a square.
    const hw = halfWidth;
    const hh = halfWidth * 1.4;
    final cosA = math.cos(_angle);
    final sinA = math.sin(_angle);
    Offset rot(double x, double y) =>
        Offset(center.dx + x * cosA - y * sinA, center.dy + x * sinA + y * cosA);

    final path = Path()
      ..moveTo(rot(0, -hh).dx, rot(0, -hh).dy)
      ..lineTo(rot(hw, 0).dx, rot(hw, 0).dy)
      ..lineTo(rot(0, hh).dx, rot(0, hh).dy)
      ..lineTo(rot(-hw, 0).dx, rot(-hw, 0).dy)
      ..close();

    // Gradient body — bright top, deeper bottom for faceted look.
    final bodyRect =
        Rect.fromLTRB(center.dx - hw, center.dy - hh, center.dx + hw, center.dy + hh);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.9),
            color,
          ],
        ).createShader(bodyRect),
    );

    // Sharp facet outline.
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}
