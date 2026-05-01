// components/hazards/lightning_bolt.dart
//
// Stratosphere hazard. A vertical bolt that flashes for 0.3s, sleeps
// for 2s, then flashes again. Only lethal during the active flash —
// most contacts pass through harmless. Instant kill (bypasses lives).

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../obstacles/game_obstacle.dart';

class LightningBolt extends GameObstacle {
  static const double flashDuration = 0.3; // seconds
  static const double cooldownDuration = 2.0; // seconds
  static const double boltHeight = 220;
  static const double boltWidth = 36;

  /// Active phase = flashing & lethal. Inactive = invisible & passable.
  bool _active = false;
  double _phaseT = 0;

  /// Random initial offset so a row of bolts doesn't strobe in lockstep.
  LightningBolt({
    required super.obstacleId,
    required Vector2 worldPosition,
    double? initialPhase,
    math.Random? rng,
  }) : super(
          position: worldPosition,
          size: Vector2(boltWidth, boltHeight),
        ) {
    _phaseT = initialPhase ??
        (rng ?? math.Random()).nextDouble() *
            (flashDuration + cooldownDuration);
    _active = _phaseT < flashDuration;
  }

  bool get isActive => _active;

  @override
  void update(double dt) {
    super.update(dt);
    _phaseT += dt;
    const cycle = flashDuration + cooldownDuration;
    if (_phaseT >= cycle) _phaseT -= cycle;
    _active = _phaseT < flashDuration;
  }

  @override
  bool intersects(Rect playerRect) {
    if (!_active) return false;
    return super.intersects(playerRect);
  }

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.kill;

  @override
  void render(Canvas canvas) {
    if (!_active) {
      // Telegraph the bolt's location with a thin standby glyph so the
      // player can plan around it during cooldown.
      final telegraph = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(size.x / 2, 0),
        Offset(size.x / 2, size.y),
        telegraph,
      );
      return;
    }

    // Active: zig-zag bolt path with hot core + cool halo.
    final core = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final halo = Paint()
      ..color = const Color(0xFFB3E0FF).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final path = Path();
    final cx = size.x / 2;
    const segments = 6;
    final segH = size.y / segments;
    path.moveTo(cx, 0);
    for (int i = 1; i <= segments; i++) {
      final dx = (i.isOdd ? 1 : -1) * size.x * 0.35;
      path.lineTo(cx + dx, i * segH);
    }
    canvas.drawPath(path, halo);
    canvas.drawPath(path, core);
  }
}
