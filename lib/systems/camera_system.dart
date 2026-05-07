// systems/camera_system.dart
//
// Auto-scrolling camera that drives the falling sensation. The camera
// always moves down at a baseline speed that ramps up with depth, and
// the player must keep up or get pinned against the top kill plane.
//
// Note: this class owns the *logical* scroll state (how far the world
// has shifted, current speed). Wiring those values into Flame's
// CameraComponent happens in FreefallGame.update() — keeping this class
// engine-agnostic makes it trivial to unit test.

import 'package:flame/components.dart';

import 'system_base.dart';
import 'zone_manager.dart';

class CameraSystem implements GameSystem {
  /// Initial scroll speed at depth 0.
  static const double baseSpeed = 200; // px/s

  /// Speed gained each time the player descends another [_distancePerStep].
  static const double speedIncrement = 10; // px/s

  /// Hard ceiling on scroll speed — past this the game stops getting harder
  /// from camera speed alone (Phase 2 will introduce other difficulty knobs).
  static const double maxSpeed = 800; // px/s

  /// 1 meter == 10 px. Tuned so the 414x896 viewport reads as ~90m tall.
  static const double pixelsPerMeter = 10;

  /// Speed steps occur every 500m of depth.
  /// WHY stored in pixels: keeps the inner-loop arithmetic in one unit.
  static const double _distancePerStep = 500 * pixelsPerMeter;

  double _currentSpeed = baseSpeed;
  double _scrolledPixels = 0;

  // Active speed-gate boost. Adds [_boostAmount] to the depth-driven
  // base speed for [_boostRemaining] seconds. Stacking calls extends
  // the timer rather than summing amounts (one boost active at a time).
  double _boostAmount = 0;
  double _boostRemaining = 0;

  /// Position of the player in world coordinates. The owner sets this each
  /// frame; CameraSystem uses it for any future "look-ahead" behavior and
  /// exposes it for follow logic.
  Vector2 playerWorldPosition = Vector2.zero();

  /// Optional ZoneManager pumped each fixed step with the current depth.
  /// Phase 2: keeping zone state in lockstep with camera scroll without
  /// adding ZoneManager to the GameSystem registry (it isn't dt-driven).
  ZoneManager? zoneManager;

  double get currentSpeed => _currentSpeed;
  double get scrolledPixels => _scrolledPixels;

  /// How deep the player has fallen, in meters. The HUD reads this.
  double get currentDepthMeters => _scrolledPixels / pixelsPerMeter;

  /// Seconds remaining on the current speed-gate boost. 0 when no boost
  /// is active. Exposed for tests and HUD diagnostics.
  double get boostRemaining => _boostRemaining;

  /// Speed bonus currently being applied on top of the depth-driven
  /// base speed (px/s). 0 when no boost is active.
  double get boostAmount => _boostRemaining > 0 ? _boostAmount : 0;

  /// Apply a temporary speed bonus on top of the depth-driven base
  /// speed. Re-calling resets the timer (no stacking) — a player who
  /// hits two gates back-to-back gets the longer total boost, not a
  /// doubled amount.
  void applySpeedBoost(double amount, double duration) {
    _boostAmount = amount;
    _boostRemaining = duration;
  }

  @override
  void update(double dt) {
    _scrolledPixels += _currentSpeed * dt;

    if (_boostRemaining > 0) {
      _boostRemaining -= dt;
      if (_boostRemaining <= 0) {
        _boostRemaining = 0;
        _boostAmount = 0;
      }
    }

    // Speed = base + 10 * floor(depth / 500m) + active boost, capped at maxSpeed.
    final steps = (_scrolledPixels / _distancePerStep).floor();
    final base = baseSpeed + steps * speedIncrement;
    final target = base + (_boostRemaining > 0 ? _boostAmount : 0);
    _currentSpeed = target > maxSpeed ? maxSpeed : target;

    zoneManager?.update(currentDepthMeters);
  }

  /// Reset for a new run.
  void reset() {
    _currentSpeed = baseSpeed;
    _scrolledPixels = 0;
    _boostAmount = 0;
    _boostRemaining = 0;
    playerWorldPosition.setZero();
    zoneManager?.reset();
  }
}
