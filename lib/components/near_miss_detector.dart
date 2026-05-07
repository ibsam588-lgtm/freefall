// components/near_miss_detector.dart
//
// Detects "close shave" near-miss events between the player and the
// active obstacle set. Each frame the host calls [detect] with the
// player's hitbox + the live obstacle list; the detector returns the
// obstacles that triggered a fresh near-miss this frame, applying a
// per-obstacle cooldown so a single obstacle doesn't fire repeatedly
// while the player is still inside the proximity ring.
//
// Geometry: a near-miss is "obstacle's hitbox is within 10px of the
// player AABB but doesn't actually overlap it" — overlap would be a
// damaging hit, not a near miss.
//
// Despite living under components/ the detector isn't a Flame
// component (no render, no parent). It's a plain helper class so unit
// tests can drive it without booting the engine. Lives here so the
// import path matches the rest of the player-facing visuals it spawns
// (FloatingText, CombDisplay).

import 'dart:ui';

import 'obstacles/game_obstacle.dart';

class NearMissDetector {
  /// Distance, in pixels, the player AABB must be inflated by for a
  /// non-overlapping obstacle to count as a near-miss.
  static const double nearMissRadius = 10;

  /// After a near-miss against a given obstacle, ignore it for this
  /// many seconds. Stops a moving block from spamming events while
  /// the player tracks alongside it.
  static const double sameObstacleCooldown = 0.5;

  // Per-obstacle remaining cooldown, keyed by obstacleId.
  final Map<String, double> _cooldowns = {};

  /// Read-only view of the current cooldown table — useful for tests
  /// and HUD diagnostics.
  Map<String, double> get cooldowns => Map.unmodifiable(_cooldowns);

  /// Wipe state for a new run.
  void reset() => _cooldowns.clear();

  /// Tick down all in-flight cooldowns and return the obstacles whose
  /// hitboxes are within [nearMissRadius] of [playerRect] without
  /// actually overlapping it.
  ///
  /// The detector mutates its own cooldown map in-place: each returned
  /// obstacle gets a fresh [sameObstacleCooldown] entry, and any entry
  /// that drains to zero is removed.
  List<GameObstacle> detect(
    Rect playerRect,
    List<GameObstacle> obstacles,
    double dt,
  ) {
    _tickCooldowns(dt);

    final inflated = playerRect.inflate(nearMissRadius);
    final hits = <GameObstacle>[];
    for (final o in obstacles) {
      if (_cooldowns.containsKey(o.obstacleId)) continue;
      // Use the obstacle's own [intersects] for both predicates so that
      // tightly-shaped hazards (rotating arms, gap-wall halves, jellies,
      // bolt zigzags, etc.) score near-miss against the same geometry
      // they damage against. Using the loose AABB here over-fires
      // near-miss on obstacles whose tight test would have rejected.
      //   a) inflated player rect overlaps obstacle (within 10px), AND
      //   b) raw player rect does NOT overlap obstacle (else: a hit).
      if (!o.intersects(inflated)) continue;
      if (o.intersects(playerRect)) continue;
      hits.add(o);
      _cooldowns[o.obstacleId] = sameObstacleCooldown;
    }
    return hits;
  }

  void _tickCooldowns(double dt) {
    if (_cooldowns.isEmpty) return;
    final expired = <String>[];
    _cooldowns.updateAll((id, remaining) {
      final next = remaining - dt;
      if (next <= 0) expired.add(id);
      return next;
    });
    for (final id in expired) {
      _cooldowns.remove(id);
    }
  }
}
