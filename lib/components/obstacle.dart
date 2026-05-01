// components/obstacle.dart
//
// Phase 1 minimal data carrier — just enough for ObstaclePool to
// instantiate and reset instances. Phase 2 will turn this into a
// PositionComponent with sprite/render logic.

import 'package:flame/components.dart';

class Obstacle {
  /// Unique id used as the CollisionSystem key.
  String id = '';

  /// World-space position of the obstacle's origin.
  final Vector2 position = Vector2.zero();

  /// Axis-aligned size in world pixels.
  final Vector2 size = Vector2.zero();

  /// Whether this obstacle is currently active in the world.
  bool active = false;

  /// Optional kind discriminator (will be enum-ified in Phase 2).
  int kind = 0;

  Obstacle();

  /// Reset to a clean state — called by ObstaclePool.acquire().
  void reset() {
    id = '';
    position.setZero();
    size.setZero();
    active = false;
    kind = 0;
  }
}
