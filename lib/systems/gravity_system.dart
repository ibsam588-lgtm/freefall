// systems/gravity_system.dart
//
// Physics constants and the per-frame velocity transform used by every
// gravity-affected entity in Freefall (the player, falling debris,
// particle effects).
//
// GravitySystem is intentionally stateless: callers pass in their own
// velocity vector and get an updated copy back. This keeps gravity a
// pure function and avoids a god-object that knows about every entity.

import 'dart:math' as math;

import 'package:flame/components.dart';

import 'system_base.dart';

class GravitySystem implements GameSystem {
  /// Downward acceleration (positive y is down in Flame's screen space).
  static const double gravity = 500; // px/s^2 — reduced 37.5% for floatier feel

  /// Hard cap on |velocity.y| — past this we stop accelerating.
  /// WHY: without a cap, long falls accumulate to absurd speeds and
  /// blow past collision swept-volumes between frames.
  static const double terminalVelocity = 840; // px/s

  /// Per-frame proportional drag. Applied as v -= v * dragCoefficient.
  /// Affects both axes — sideways tilt also damps over time, which
  /// makes the orb feel weighty rather than twitchy.
  static const double dragCoefficient = 0.02;

  /// Returns a new velocity with gravity, drag, and terminal-velocity
  /// clamping applied. Does not mutate [velocity].
  Vector2 applyGravity(Vector2 velocity, double dt) {
    final v = velocity.clone();

    // Integrate gravity into vertical component.
    v.y += gravity * dt;

    // Continuous-decay drag, framerate-independent. The previous
    // formulation `v -= v * dragCoefficient` ignored dt — it dropped
    // 2% per frame regardless of frame length, so a 30Hz frame applied
    // half the per-second drag of a 60Hz frame. That made the player
    // accelerate FASTER on slower devices, exactly when the engine
    // could least afford the extra fall speed (more tunneling through
    // thin obstacles).
    //
    // dragCoefficient is preserved as the "fraction lost per 60Hz
    // frame" the constants were authored against; converted to a
    // continuous decay rate it's `dragCoefficient * 60` per second.
    final factor = math.exp(-dragCoefficient * 60.0 * dt);
    v.x *= factor;
    v.y *= factor;

    // Clamp vertical speed only — sideways speed is bounded by player
    // input range, so doesn't need a separate cap.
    if (v.y > terminalVelocity) v.y = terminalVelocity;
    if (v.y < -terminalVelocity) v.y = -terminalVelocity;

    return v;
  }

  @override
  void update(double dt) {
    // No body registry yet — Phase 2 will iterate registered Rigidbody
    // entities here. For now, owners (Player, particles) call
    // applyGravity() directly during their own update.
  }
}
