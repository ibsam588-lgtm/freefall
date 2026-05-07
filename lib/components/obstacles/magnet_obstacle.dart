// components/obstacles/magnet_obstacle.dart
//
// Pulls the player toward its center within a [pullRadius] sphere.
// The actual force is applied externally — this component just exposes
// [pullForceOn] so the magnet's contribution is composable with the
// player's existing horizontal control. The center remains a damaging
// hit if the player gets all the way in.
//
// We don't write directly to the player here because Player owns its own
// velocity; coupling them would make tests harder. The owner (game host
// or a future dedicated MagnetSystem) iterates ObstacleManager and adds
// the returned force.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../models/zone.dart';
import 'game_obstacle.dart';

class MagnetObstacle extends GameObstacle {
  /// Distance at which the magnet starts pulling the player. Falls off
  /// linearly to zero at the edge.
  static const double pullRadius = 150;

  /// Pull force at the center of the field (px/s²-ish; tune against
  /// player horizontal control). Falls off linearly with distance.
  static const double maxPullForce = 800;

  /// Visible radius of the magnet body.
  static const double bodyRadius = 16;

  final Zone zone;
  double _pulse = 0;

  MagnetObstacle({
    required super.obstacleId,
    required Vector2 worldPosition,
    required this.zone,
  }) : super(
          position: worldPosition,
          size: Vector2.all(bodyRadius * 2),
        );

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt;
  }

  /// World-space force vector to apply to a body at [worldPos]. Zero
  /// outside [pullRadius]. Caller is responsible for accumulating this
  /// across all magnets and integrating it into the player's velocity.
  Vector2 pullForceOn(Vector2 worldPos) {
    final delta = position - worldPos;
    final dist = delta.length;
    if (dist < 0.001 || dist > pullRadius) return Vector2.zero();
    // 1 at center, 0 at edge — quick linear falloff.
    final strength = (1 - dist / pullRadius).clamp(0.0, 1.0);
    return delta.normalized() * (maxPullForce * strength);
  }

  /// Circle-vs-AABB distance test. Only the inner core damages on
  /// contact — the pull field itself isn't a hit. The previous
  /// rect-vs-rect check was identical to the parent AABB (size ==
  /// 2*bodyRadius), so the "tighter" comment was a lie; this one is
  /// genuinely tighter at the diagonal corners.
  @override
  bool intersects(Rect playerRect) {
    final closestX = position.x.clamp(playerRect.left, playerRect.right);
    final closestY = position.y.clamp(playerRect.top, playerRect.bottom);
    final dx = position.x - closestX;
    final dy = position.y - closestY;
    return dx * dx + dy * dy <= bodyRadius * bodyRadius;
  }

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.damage;

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Field telegraph: faint pulsing ring at pullRadius so the player
    // can read where the magnet's reach begins.
    final pulseT = (math.sin(_pulse * 4) * 0.5 + 0.5);
    final fieldPaint = Paint()
      ..color = zone.accentColor.withValues(alpha: 0.10 + 0.10 * pulseT)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), pullRadius, fieldPaint);

    // Core body: a U-shaped magnet rendered as two stubby rectangles.
    final bodyPaint = Paint()..color = zone.bottomColor;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = zone.accentColor;
    final left = Rect.fromLTWH(cx - bodyRadius, cy - bodyRadius,
        bodyRadius * 0.8, bodyRadius * 1.5);
    final right = Rect.fromLTWH(cx + bodyRadius * 0.2, cy - bodyRadius,
        bodyRadius * 0.8, bodyRadius * 1.5);
    final base = Rect.fromLTWH(cx - bodyRadius, cy + bodyRadius * 0.5,
        bodyRadius * 2, bodyRadius * 0.5);

    canvas.drawRect(left, bodyPaint);
    canvas.drawRect(right, bodyPaint);
    canvas.drawRect(base, bodyPaint);
    canvas.drawRect(left, stroke);
    canvas.drawRect(right, stroke);
    canvas.drawRect(base, stroke);
  }
}
