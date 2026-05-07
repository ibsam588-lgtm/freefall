// components/obstacles/moving_block.dart
//
// Solid block that patrols horizontally between two endpoints, reversing
// at each end. Patrol speed is randomised at spawn so a column of moving
// blocks doesn't visually beat in lock-step.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../models/zone.dart';
import 'game_obstacle.dart';

class MovingBlock extends GameObstacle {
  static const double minSpeed = 100; // px/s
  static const double maxSpeed = 300; // px/s
  static const double blockWidth = 80;
  static const double blockHeight = 28;
  static const double cornerRadius = 6;

  final Zone zone;
  final double minX;
  final double maxX;
  double _speed; // signed: + moves right, - moves left

  /// Block's center X at the START of the most recent frame. Used by
  /// [intersects] to sweep the block's body across the frame so a fast
  /// patrol (up to 300 px/s, ~10px per 1/30s frame) can't miss a
  /// player whose path the block crossed mid-frame.
  double _prevPositionX = double.nan;

  MovingBlock({
    required super.obstacleId,
    required Vector2 worldPosition,
    required this.zone,
    required this.minX,
    required this.maxX,
    double? initialSpeed,
    math.Random? rng,
  })  : assert(maxX > minX, 'patrol range must be positive'),
        _speed = initialSpeed ??
            (minSpeed +
                    (rng ?? math.Random()).nextDouble() *
                        (maxSpeed - minSpeed)) *
                ((rng ?? math.Random()).nextBool() ? 1 : -1),
        super(
          position: worldPosition,
          size: Vector2(blockWidth, blockHeight),
        );

  /// Current signed velocity along x. Exposed for tests.
  double get speedX => _speed;

  @override
  void update(double dt) {
    super.update(dt);
    if (_prevPositionX.isNaN) _prevPositionX = position.x;
    final priorX = position.x;
    position.x += _speed * dt;
    final halfW = size.x / 2;

    // Bounce off the patrol bounds, accounting for the block's own width
    // so the visible edge stops at the bound (not the center).
    if (position.x - halfW < minX) {
      position.x = minX + halfW;
      _speed = _speed.abs();
    } else if (position.x + halfW > maxX) {
      position.x = maxX - halfW;
      _speed = -_speed.abs();
    }
    _prevPositionX = priorX;
  }

  /// Swept hitbox: union of the block's pre- and post-update AABB so a
  /// fast patrol can't slide past the player between physics steps.
  @override
  bool intersects(Rect playerRect) {
    if (super.intersects(playerRect)) return true;
    if (_prevPositionX.isNaN || _prevPositionX == position.x) return false;
    final halfW = size.x / 2;
    final halfH = size.y / 2;
    final swept = Rect.fromLTRB(
      math.min(position.x, _prevPositionX) - halfW,
      position.y - halfH,
      math.max(position.x, _prevPositionX) + halfW,
      position.y + halfH,
    );
    return swept.overlaps(playerRect);
  }

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.damage;

  @override
  void render(Canvas canvas) {
    final body = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect =
        RRect.fromRectAndRadius(body, const Radius.circular(cornerRadius));
    canvas.drawRRect(rrect, Paint()..color = zone.bottomColor);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = zone.accentColor,
    );

    // Direction-of-travel chevron — small affordance so the player can
    // read which way the block is moving.
    final cx = size.x / 2;
    final cy = size.y / 2;
    final arrow = Path();
    final dir = _speed >= 0 ? 1.0 : -1.0;
    arrow.moveTo(cx - 6 * dir, cy - 5);
    arrow.lineTo(cx + 6 * dir, cy);
    arrow.lineTo(cx - 6 * dir, cy + 5);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = zone.accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
