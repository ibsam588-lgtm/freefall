// components/hazards/jellyfish.dart
//
// Deep-Ocean hazard. Drifts horizontally on a sine wave; on contact,
// stuns the player for 0.5s instead of dealing damage. Stun is
// non-cumulative — a second touch during the same encounter is a no-op.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../obstacles/game_obstacle.dart';

class Jellyfish extends GameObstacle {
  static const double bodyRadius = 22;
  static const double driftAmplitude = 60; // pixels left/right of anchor
  static const double driftFrequency = 0.6; // Hz

  /// World-X around which the jellyfish oscillates. Stored separately
  /// from [position] because position itself is the live drift output.
  final double anchorX;

  /// Cooldown so a single touch can't keep stunning forever.
  static const double rearmCooldown = 0.6;
  double _rearmT = 0;
  double _t;

  Jellyfish({
    required super.obstacleId,
    required Vector2 worldPosition,
    double? phase,
    math.Random? rng,
  })  : anchorX = worldPosition.x,
        _t = phase ?? (rng ?? math.Random()).nextDouble() * math.pi * 2,
        super(
          position: worldPosition,
          size: Vector2.all(bodyRadius * 2),
        );

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final wave = math.sin(_t * driftFrequency * math.pi * 2);
    position.x = anchorX + driftAmplitude * wave;
    if (_rearmT > 0) _rearmT -= dt;
  }

  /// Circle-vs-AABB distance test. The old rect-vs-rect check overlapped
  /// at the AABB's diagonal corners, ~6px past the visible bell edge.
  @override
  bool intersects(Rect playerRect) {
    final closestX = position.x.clamp(playerRect.left, playerRect.right);
    final closestY = position.y.clamp(playerRect.top, playerRect.bottom);
    final dx = position.x - closestX;
    final dy = position.y - closestY;
    return dx * dx + dy * dy <= bodyRadius * bodyRadius;
  }

  @override
  ObstacleHitEffect onPlayerHit() {
    if (_rearmT > 0) return ObstacleHitEffect.none;
    _rearmT = rearmCooldown;
    return ObstacleHitEffect.stun;
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Bell — translucent dome.
    final bell = Paint()
      ..color = const Color(0xFF40E0D0).withValues(alpha: 0.55);
    final bellStroke = Paint()
      ..color = const Color(0xFFB3FFF5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final bellRect = Rect.fromCenter(
      center: Offset(cx, cy - bodyRadius * 0.2),
      width: bodyRadius * 2,
      height: bodyRadius * 1.4,
    );
    canvas.drawArc(bellRect, math.pi, math.pi, true, bell);
    canvas.drawArc(bellRect, math.pi, math.pi, false, bellStroke);

    // Tentacles — wavy lines beneath the bell.
    final tentaclePaint = Paint()
      ..color = const Color(0xFF40E0D0).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (int i = 0; i < 5; i++) {
      final tx = cx - bodyRadius + (i + 0.5) * (bodyRadius * 2 / 5);
      final p = Path()..moveTo(tx, cy);
      for (int s = 1; s <= 4; s++) {
        final ty = cy + s * 6;
        final wobble = math.sin(_t * 4 + i + s) * 3;
        p.lineTo(tx + wobble, ty);
      }
      canvas.drawPath(p, tentaclePaint);
    }
  }
}
