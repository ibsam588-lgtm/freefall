// components/particle_system.dart
//
// Dedicated particle component for player death + respawn effects.
// Pulls from the Phase-1 ParticlePool so the 60-particle burst doesn't
// allocate per death. Death = explode outward from origin; respawn =
// converge inward from scattered positions to a target.
//
// This is a Flame Component (renderable), distinct from
// systems/particle_system.dart which is the fixed-step game-loop hook
// for ambient effects.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../components/particle.dart';
import '../systems/object_pool.dart';

/// What the particles are currently doing. Idle == nothing to draw.
enum ParticleMode { idle, death, respawn }

class PlayerParticleSystem extends Component {
  /// Pool size budget — Phase 4 spec calls for 60 particles.
  static const int particleCount = 60;

  /// Death particles fly outward at this speed range (px/s).
  static const double deathMinSpeed = 100;
  static const double deathMaxSpeed = 320;

  /// Particles fade fully within this many seconds.
  static const double deathLifetime = 1.5;

  /// Respawn duration — particles converge over this many seconds.
  static const double respawnDuration = 0.6;

  /// Drag applied each second to death-particle velocity (linear decel).
  /// 1.5 means after a second velocity is multiplied by ~0.22.
  static const double deathDrag = 1.5;

  final ParticlePool _pool;
  final List<Particle> _active = [];

  // Target the respawn particles converge to. Lives in world coords.
  final Vector2 _respawnTarget = Vector2.zero();
  double _respawnElapsed = 0;

  // Per-particle initial position cache for the respawn lerp. Parallel
  // to _active so the lerp doesn't need to read it from velocity.
  final List<Vector2> _respawnStarts = [];

  ParticleMode _mode = ParticleMode.idle;
  final math.Random _rng = math.Random();

  PlayerParticleSystem({ParticlePool? pool})
      : _pool = pool ?? ParticlePool(initialSize: particleCount);

  ParticleMode get mode => _mode;
  int get activeCount => _active.length;

  /// Burst outward from [origin], tinted by [color]. Replaces any
  /// in-flight effect (death overrides respawn — death is the more
  /// dramatic event and shouldn't be visually interrupted).
  void triggerDeath(Vector2 origin, Color color) {
    _releaseAll();
    _mode = ParticleMode.death;

    for (int i = 0; i < particleCount; i++) {
      final p = _pool.acquire();
      final angle = _rng.nextDouble() * math.pi * 2;
      final speed = deathMinSpeed +
          _rng.nextDouble() * (deathMaxSpeed - deathMinSpeed);
      p.position.setFrom(origin);
      p.velocity.setValues(
          math.cos(angle) * speed, math.sin(angle) * speed);
      p.color = color;
      p.radius = 1.5 + _rng.nextDouble() * 2.0;
      p.maxLife = deathLifetime;
      p.life = deathLifetime;
      _active.add(p);
    }
  }

  /// Particles converge to [target] from scattered start positions and
  /// then release back to the pool when within reach.
  void triggerRespawn(Vector2 target, Color color) {
    _releaseAll();
    _mode = ParticleMode.respawn;
    _respawnTarget.setFrom(target);
    _respawnElapsed = 0;
    _respawnStarts.clear();

    for (int i = 0; i < particleCount; i++) {
      final p = _pool.acquire();
      final angle = _rng.nextDouble() * math.pi * 2;
      // Scatter on a ring 80–160 px out from the target.
      final dist = 80 + _rng.nextDouble() * 80.0;
      p.position.setValues(target.x + math.cos(angle) * dist,
          target.y + math.sin(angle) * dist);
      p.velocity.setZero();
      p.color = color;
      p.radius = 1.5 + _rng.nextDouble() * 2.0;
      p.maxLife = respawnDuration;
      p.life = respawnDuration;
      _active.add(p);
      _respawnStarts.add(p.position.clone());
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    switch (_mode) {
      case ParticleMode.idle:
        return;
      case ParticleMode.death:
        _updateDeath(dt);
        break;
      case ParticleMode.respawn:
        _updateRespawn(dt);
        break;
    }
  }

  void _updateDeath(double dt) {
    for (final p in _active) {
      // Linear drag — friendlier to pool reuse than gravity here.
      final decel = (1 - deathDrag * dt).clamp(0.0, 1.0);
      p.velocity.scale(decel);
      p.position.add(p.velocity * dt);
      p.life -= dt;
    }
    // Reap dead ones; if all gone we go idle.
    _active.removeWhere((p) {
      if (p.life <= 0) {
        _pool.release(p);
        return true;
      }
      return false;
    });
    if (_active.isEmpty) _mode = ParticleMode.idle;
  }

  void _updateRespawn(double dt) {
    _respawnElapsed += dt;
    final t = (_respawnElapsed / respawnDuration).clamp(0.0, 1.0);
    // Ease-in cubic — particles accelerate toward the target.
    final eased = t * t * t;
    for (int i = 0; i < _active.length; i++) {
      final p = _active[i];
      final start = _respawnStarts[i];
      p.position.setValues(
        start.x + (_respawnTarget.x - start.x) * eased,
        start.y + (_respawnTarget.y - start.y) * eased,
      );
      p.life = respawnDuration - _respawnElapsed;
    }
    if (t >= 1.0) {
      _releaseAll();
      _mode = ParticleMode.idle;
    }
  }

  void _releaseAll() {
    for (final p in _active) {
      _pool.release(p);
    }
    _active.clear();
    _respawnStarts.clear();
  }

  @override
  void render(Canvas canvas) {
    if (_mode == ParticleMode.idle) return;
    for (final p in _active) {
      final frac = p.lifeFraction;
      // Death particles shrink as they fade; respawn particles grow
      // brighter as they near the target. Same code path either way:
      // alpha = lifeFraction * mode-specific scale.
      final a = (frac * 0.95).clamp(0.0, 1.0);
      final paint = Paint()..color = p.color.withValues(alpha: a);
      canvas.drawCircle(Offset(p.position.x, p.position.y), p.radius, paint);
    }
  }
}
