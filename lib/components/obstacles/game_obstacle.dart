// components/obstacles/game_obstacle.dart
//
// Base class shared by every spawnable obstacle and zone hazard. Subclasses
// own their visuals and per-frame behavior; the base supplies a stable id,
// an axis-aligned hitbox in world space, and a hit-effect taxonomy that the
// collision pipeline reads to decide what the contact actually does to the
// player (damage / kill / stun / boost).
//
// We deliberately don't pool these as Flame components — pooling complicates
// removeFromParent / re-attach for short-lived obstacles, and the spawn rate
// (~1.5–4/s) is well below GC-pressure thresholds. The Phase-1 ObstaclePool
// exists for the simple data-carrier Obstacle used by the legacy spatial
// grid; ObstacleManager owns this richer component lifecycle directly.

import 'dart:ui';

import 'package:flame/components.dart';

/// What happens when the player collides with an obstacle. The collision
/// pipeline maps these to concrete player-state changes.
enum ObstacleHitEffect {
  /// One-life damage (subject to i-frames). Most obstacles return this.
  damage,

  /// Bypasses lives and kills outright (lightning, stalactite).
  kill,

  /// Briefly disables player input (jellyfish).
  stun,

  /// Awards points + temporarily speeds up the camera (speed gate).
  boost,

  /// No effect — the obstacle has already been triggered/consumed and
  /// further contacts shouldn't fire again.
  none,
}

abstract class GameObstacle extends PositionComponent {
  /// Stable id used by the collision system as a dedup key. The spawner
  /// allocates one per spawn; tests can pass a deterministic value.
  final String obstacleId;

  GameObstacle({
    required this.obstacleId,
    super.position,
    super.size,
    super.anchor = Anchor.center,
  });

  /// World-space bounding box. Default is the AABB derived from
  /// [position] + [size]; subclasses with non-rectangular hitboxes
  /// (e.g. GapWall) override [intersects] to do a tighter test.
  Rect get hitbox {
    final tl = position - Vector2(size.x / 2, size.y / 2);
    return Rect.fromLTWH(tl.x, tl.y, size.x, size.y);
  }

  /// Tighter test the collision system actually consults. The default
  /// just falls back to the bounding-box overlap; override when the
  /// obstacle has internal gaps or non-rect geometry.
  bool intersects(Rect playerRect) => hitbox.overlaps(playerRect);

  /// Top edge of this obstacle in world Y. Used by ObstacleManager to
  /// decide when an obstacle has scrolled out of frame.
  double get topY => position.y - size.y / 2;

  /// Bottom edge of this obstacle in world Y.
  double get bottomY => position.y + size.y / 2;

  /// Called once per contact, *after* the collision system has decided
  /// the player and this obstacle overlap. Subclasses use this to mutate
  /// their own state (start a crumble timer, mark a gate as consumed)
  /// and to declare what the contact does to the player. Repeated calls
  /// from successive frames are fine — return [ObstacleHitEffect.none]
  /// once the effect should not re-fire.
  ObstacleHitEffect onPlayerHit();
}
