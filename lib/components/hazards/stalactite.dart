// components/hazards/stalactite.dart
//
// Underground hazard. Hangs from above; once the player passes within
// 200px horizontally, the stalactite releases and falls under gravity.
// In flight it's an instant kill — landing on a stalactite head is
// usually how a deep underground run ends.

import 'dart:ui';

import 'package:flame/components.dart';

import '../obstacles/game_obstacle.dart';

class Stalactite extends GameObstacle {
  /// Horizontal distance at which the stalactite triggers and starts to
  /// fall. Exposed as a static constant so the spawner can reason about
  /// safe spacing of triggering corridors.
  static const double triggerHorizontalDistance = 200;

  static const double spikeWidth = 26;
  static const double spikeHeight = 60;
  static const double dropAcceleration = 1400; // px/s²
  static const double maxDropSpeed = 1200; // px/s

  bool _falling = false;
  double _fallVelocity = 0;

  Stalactite({
    required super.obstacleId,
    required Vector2 worldPosition,
  }) : super(
          position: worldPosition,
          size: Vector2(spikeWidth, spikeHeight),
        );

  bool get isFalling => _falling;

  /// Per-frame trigger check. The owning system or manager calls this
  /// with the player's current world position; once triggered the
  /// stalactite begins falling and the call becomes a no-op.
  void considerTrigger(Vector2 playerWorldPos) {
    if (_falling) return;
    final dx = (playerWorldPos.x - position.x).abs();
    if (dx <= triggerHorizontalDistance &&
        playerWorldPos.y < position.y + spikeHeight) {
      _falling = true;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_falling) {
      _fallVelocity =
          (_fallVelocity + dropAcceleration * dt).clamp(0.0, maxDropSpeed);
      position.y += _fallVelocity * dt;
    }
  }

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.kill;

  @override
  void render(Canvas canvas) {
    // Tapered downward — wide at top (where it hangs), narrow point at
    // bottom (the lethal tip).
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.x, 0)
      ..lineTo(size.x * 0.5, size.y)
      ..close();

    final body = Paint()..color = const Color(0xFF6B4423);
    final stroke = Paint()
      ..color = const Color(0xFFFFB347)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, body);
    canvas.drawPath(path, stroke);

    // Subtle highlight stripe so the stalactite reads as 3D rock.
    final highlight = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.18)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.x * 0.3, 4),
      Offset(size.x * 0.45, size.y * 0.85),
      highlight,
    );
  }
}
