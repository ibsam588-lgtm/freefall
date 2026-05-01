// components/player.dart
//
// The player avatar — a glowing orb that falls under gravity, tilts
// left/right under accelerometer (or touch fallback), and leaves a
// motion trail and wind streaks scaled to its vertical speed.
//
// Lives & i-frames: the player has 3 lives. After taking a hit they
// flash and are invulnerable for [invincibilityDuration] seconds. When
// lives hit 0 we emit a 30-particle death burst; the host scene calls
// respawn() to reassemble the orb at the spawn point.

import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../systems/gravity_system.dart';

class Player extends PositionComponent {
  /// Visible orb radius in world pixels.
  static const double radius = 18;

  /// How aggressively device tilt converts to horizontal velocity.
  /// Tuned so a comfortable ~30° tilt produces near-max horizontal speed.
  static const double tiltSensitivity = 600; // px/s per (m/s^2)

  /// Maximum horizontal speed produced by tilt or touch.
  static const double maxHorizontalSpeed = 600;

  static const int maxLives = 3;
  static const double invincibilityDuration = 2.0; // seconds

  /// Number of trailing positions retained for the motion trail.
  static const int trailLength = 15;

  /// Number of vertical wind streaks drawn above the orb.
  static const int windLineCount = 5;

  /// Gravity utility — injected so tests can swap it.
  final GravitySystem gravity;

  /// Where respawn() puts the player back.
  final Vector2 startPosition;

  /// Current world-space velocity. Public so tests can inspect it.
  final Vector2 velocity = Vector2.zero();

  /// Glow tint. Will be driven by zone in Phase 3 (e.g. cyan for ice,
  /// orange for fire). Kept mutable so the scene can crossfade it.
  Color glowColor = Colors.white;

  // Last raw accelerometer reading on the X axis (in m/s^2).
  // WHY: cached so render can also peek at it for subtle squash effects.
  double _accelX = 0;
  bool _hasAccel = false;

  // Touch-fallback input range: -1 (full left) .. 1 (full right).
  double _touchInput = 0;

  int _lives = maxLives;
  double _invincibleTimer = 0;
  // Phase counter for invincibility flash and shield pulse.
  double _flashPhase = 0;

  // Recent positions for the motion trail (oldest first).
  final List<Vector2> _trail = [];

  // Active death burst particles. Owned by Player because the burst is
  // tightly coupled to the player's transform; ambient particles live
  // in ParticleSystem instead.
  final List<_DeathParticle> _deathParticles = [];

  StreamSubscription<AccelerometerEvent>? _accelSub;

  Player({
    required this.gravity,
    required this.startPosition,
  }) : super(
          position: startPosition.clone(),
          size: Vector2.all(radius * 2),
          anchor: Anchor.center,
        );

  int get lives => _lives;
  bool get isAlive => _lives > 0;
  bool get isInvincible => _invincibleTimer > 0;
  bool get hasAccelerometer => _hasAccel;
  int get activeParticleCount => _deathParticles.length;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _subscribeAccelerometer();
  }

  @override
  void onRemove() {
    _accelSub?.cancel();
    _accelSub = null;
    super.onRemove();
  }

  void _subscribeAccelerometer() {
    try {
      _accelSub = accelerometerEventStream().listen(
        (event) {
          // WHY invert: in portrait, tilting the device's right edge down
          // produces a positive event.x, but the player should slide right
          // (positive screen x), so we invert to match the user's intent.
          _accelX = -event.x;
          _hasAccel = true;
        },
        onError: (_) {
          _hasAccel = false;
        },
        cancelOnError: false,
      );
    } catch (_) {
      // Some platforms / test contexts don't have a sensor backend at all.
      _hasAccel = false;
    }
  }

  /// Touch-zone input: -1 (left), 0 (none), 1 (right). Applied only when
  /// no accelerometer reading is available.
  void setTouchInput(double horizontal) {
    _touchInput = horizontal.clamp(-1.0, 1.0);
  }

  /// Apply a hit. Returns true if it actually landed (not i-framed/dead).
  bool hit() {
    if (!isAlive || isInvincible) return false;
    _lives--;
    if (_lives <= 0) {
      _emitDeathParticles();
      velocity.setZero();
    } else {
      _invincibleTimer = invincibilityDuration;
    }
    return true;
  }

  /// Re-assemble at the spawn point with full lives if dead, or just
  /// reset position+velocity+i-frames if still alive (used for revive).
  void respawn() {
    position.setFrom(startPosition);
    velocity.setZero();
    _trail.clear();
    _invincibleTimer = invincibilityDuration;
    if (_lives <= 0) {
      _lives = maxLives;
      _deathParticles.clear();
    }
  }

  void _emitDeathParticles() {
    final rng = math.Random();
    for (int i = 0; i < 30; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 100 + rng.nextDouble() * 220;
      _deathParticles.add(_DeathParticle(
        position: position.clone(),
        velocity: Vector2(math.cos(angle), math.sin(angle)) * speed,
        life: 0.8 + rng.nextDouble() * 0.5,
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _stepPhysics(dt);
    _stepTrail();
    _stepInvincibility(dt);
    _stepDeathParticles(dt);
  }

  void _stepPhysics(double dt) {
    if (!isAlive) return;

    // Horizontal: prefer accelerometer when it's reporting; otherwise
    // touch zones. Convert raw input to a target velocity and snap to it
    // — there's no horizontal inertia, the orb feels twitchy if there is.
    final hInput = _hasAccel ? (_accelX * tiltSensitivity) : (_touchInput * maxHorizontalSpeed);
    velocity.x = hInput.clamp(-maxHorizontalSpeed, maxHorizontalSpeed);

    // Vertical: gravity + drag + terminal velocity, courtesy GravitySystem.
    final newVel = gravity.applyGravity(velocity, dt);
    velocity.setFrom(newVel);

    position.add(velocity * dt);
  }

  void _stepTrail() {
    _trail.add(position.clone());
    if (_trail.length > trailLength) {
      _trail.removeAt(0);
    }
  }

  void _stepInvincibility(double dt) {
    if (_invincibleTimer > 0) {
      _invincibleTimer = (_invincibleTimer - dt).clamp(0.0, invincibilityDuration);
    }
    _flashPhase += dt * 12; // ~6 flashes/sec when shield active
  }

  void _stepDeathParticles(double dt) {
    for (final p in _deathParticles) {
      // Reuse the same gravity so death debris follows the world's physics.
      final v = gravity.applyGravity(p.velocity, dt);
      p.velocity.setFrom(v);
      p.position.add(p.velocity * dt);
      p.life -= dt;
    }
    _deathParticles.removeWhere((p) => p.life <= 0);
  }

  @override
  void render(Canvas canvas) {
    // PositionComponent renders in its own local space — anchor=center
    // means (size/2, size/2) is the orb's center.
    final cx = size.x / 2;
    final cy = size.y / 2;
    final center = Offset(cx, cy);

    _renderWindLines(canvas, center);
    _renderTrail(canvas, center);
    _renderOrb(canvas, center);
    _renderShield(canvas, center);
    _renderDeathParticles(canvas, center);
  }

  void _renderWindLines(Canvas canvas, Offset center) {
    final speedMag = velocity.y.abs();
    if (speedMag < 50) return;

    // Both alpha and length scale with vertical speed up to terminal.
    final alpha = (speedMag / GravitySystem.terminalVelocity).clamp(0.0, 0.6);
    final lineLen = (speedMag / 800.0 * 36.0).clamp(8.0, 56.0);
    final paint = Paint()
      ..color = glowColor.withValues(alpha: alpha)
      ..strokeWidth = 1.4;

    for (int i = 0; i < windLineCount; i++) {
      // Spread the streaks horizontally across the orb's width.
      final dx = (i - (windLineCount - 1) / 2) * 6.0;
      final topY = center.dy - radius - 6 - lineLen;
      canvas.drawLine(
        Offset(center.dx + dx, topY),
        Offset(center.dx + dx, topY + lineLen),
        paint,
      );
    }
  }

  void _renderTrail(Canvas canvas, Offset center) {
    if (_trail.isEmpty) return;
    for (int i = 0; i < _trail.length; i++) {
      final t = (i + 1) / _trail.length; // 0..1, 1 == newest
      // _trail entries are world-space; convert to local relative to player.
      final delta = _trail[i] - position;
      final p = Offset(center.dx + delta.x, center.dy + delta.y);
      final paint = Paint()
        ..color = glowColor.withValues(alpha: 0.04 + t * 0.18)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, radius * (0.35 + 0.45 * t), paint);
    }
  }

  void _renderOrb(Canvas canvas, Offset center) {
    // Skip drawing on alternating frames during i-frames for the flash.
    if (isInvincible && _flashPhase.floor() % 2 == 0) return;

    // Outer halo — soft falloff radial gradient.
    final haloRect = Rect.fromCircle(center: center, radius: radius * 2.2);
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          glowColor.withValues(alpha: 0.65),
          glowColor.withValues(alpha: 0.0),
        ],
      ).createShader(haloRect);
    canvas.drawCircle(center, radius * 2.2, haloPaint);

    // Body — bright white core fading to glowColor at the rim.
    final bodyRect = Rect.fromCircle(center: center, radius: radius);
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, glowColor],
        stops: const [0.15, 1.0],
      ).createShader(bodyRect);
    canvas.drawCircle(center, radius, bodyPaint);
  }

  void _renderShield(Canvas canvas, Offset center) {
    if (!isInvincible) return;
    // Sin-driven pulse so the shield breathes.
    final pulse = 0.55 + 0.45 * math.sin(_flashPhase * math.pi);
    final shieldPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.32 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius * 1.55, shieldPaint);
  }

  void _renderDeathParticles(Canvas canvas, Offset center) {
    if (_deathParticles.isEmpty) return;
    for (final p in _deathParticles) {
      final delta = p.position - position;
      final off = Offset(center.dx + delta.x, center.dy + delta.y);
      final alpha = p.life.clamp(0.0, 1.0);
      // Particles shrink as they fade, so they read as embers.
      canvas.drawCircle(
        off,
        2 + (1 - alpha) * 1.5,
        Paint()..color = glowColor.withValues(alpha: alpha),
      );
    }
  }
}

/// Internal — death burst particle. Not pooled because it lives < 1.5s
/// and only fires once per death; pooling would be premature here.
class _DeathParticle {
  final Vector2 position;
  final Vector2 velocity;
  double life;

  _DeathParticle({
    required this.position,
    required this.velocity,
    required this.life,
  });
}
