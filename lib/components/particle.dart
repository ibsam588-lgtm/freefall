// components/particle.dart
//
// Lightweight, pool-friendly particle. Owned by ParticleSystem (or
// individual components like Player's death burst). One Particle per
// visible spark/dust mote; render is whatever the owner wants.

import 'dart:ui';

import 'package:flame/components.dart';

class Particle {
  final Vector2 position = Vector2.zero();
  final Vector2 velocity = Vector2.zero();

  /// Seconds remaining before the particle should be released.
  double life = 0;

  /// Initial life — lets the renderer fade based on life/maxLife.
  double maxLife = 1;

  /// Tint applied at full life.
  Color color = const Color(0xFFFFFFFF);

  /// Render radius in world pixels.
  double radius = 2;

  Particle();

  bool get isAlive => life > 0;

  /// Returns 0..1, 1 == just spawned.
  double get lifeFraction => maxLife <= 0 ? 0 : (life / maxLife).clamp(0, 1);

  void reset() {
    position.setZero();
    velocity.setZero();
    life = 0;
    maxLife = 1;
    color = const Color(0xFFFFFFFF);
    radius = 2;
  }
}
