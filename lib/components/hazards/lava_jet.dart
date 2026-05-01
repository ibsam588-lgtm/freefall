// components/hazards/lava_jet.dart
//
// Core-zone hazard. A vent that fires a vertical particle cone for 1s
// every 3s. Damages the player only while the jet is firing and only
// inside the cone; the vent base itself is harmless.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../obstacles/game_obstacle.dart';

class LavaJet extends GameObstacle {
  static const double fireDuration = 1.0; // seconds active
  static const double cooldownDuration = 2.0; // seconds idle (3s cycle total)
  static const double coneHeight = 220;
  static const double coneBaseWidth = 70;
  static const double coneTipWidth = 24;

  /// Direction the jet fires: -1 = up, +1 = down. Default is up so the
  /// jet looks like it erupts from the floor.
  final double direction;

  double _phaseT;
  bool _firing = false;

  LavaJet({
    required super.obstacleId,
    required Vector2 worldPosition,
    this.direction = -1,
    double? initialPhase,
    math.Random? rng,
  })  : _phaseT = initialPhase ??
            (rng ?? math.Random()).nextDouble() *
                (fireDuration + cooldownDuration),
        super(
          position: worldPosition,
          size: Vector2(coneBaseWidth, coneHeight),
        ) {
    _firing = _phaseT < fireDuration;
  }

  bool get isFiring => _firing;

  @override
  void update(double dt) {
    super.update(dt);
    _phaseT += dt;
    const cycle = fireDuration + cooldownDuration;
    if (_phaseT >= cycle) _phaseT -= cycle;
    _firing = _phaseT < fireDuration;
  }

  @override
  bool intersects(Rect playerRect) {
    if (!_firing) return false;
    return super.intersects(playerRect);
  }

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.damage;

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    // Vent base at the "near" end of the cone.
    final baseY = direction < 0 ? size.y : 0.0;
    final tipY = direction < 0 ? 0.0 : size.y;

    // Vent block (always visible — telegraphs where the jet will fire).
    final ventRect = Rect.fromCenter(
      center: Offset(cx, baseY + (direction < 0 ? -8 : 8)),
      width: coneBaseWidth * 0.7,
      height: 16,
    );
    canvas.drawRect(ventRect, Paint()..color = const Color(0xFF3A1500));
    canvas.drawRect(
      ventRect,
      Paint()
        ..color = const Color(0xFFFF6A00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (!_firing) return;

    // Active flame cone — concentric layers from outer to inner.
    final fireT = (_phaseT / fireDuration).clamp(0.0, 1.0);
    final flicker = 0.85 + 0.15 * math.sin(_phaseT * 40);
    final layers = [
      [const Color(0xFF8B0000), 1.0, 0.7],
      [const Color(0xFFFF6A00), 0.7, 0.85],
      [const Color(0xFFFFD27F), 0.4, 1.0],
    ];

    for (final layer in layers) {
      final c = layer[0] as Color;
      final widthScale = layer[1] as double;
      final lengthScale = layer[2] as double;
      final base = coneBaseWidth * widthScale;
      final tip = coneTipWidth * widthScale * 0.6;
      final length = coneHeight * lengthScale * flicker;
      final coneTipY = baseY + (tipY - baseY) * (length / coneHeight);

      final path = Path()
        ..moveTo(cx - base / 2, baseY)
        ..lineTo(cx + base / 2, baseY)
        ..lineTo(cx + tip / 2, coneTipY)
        ..lineTo(cx - tip / 2, coneTipY)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = c.withValues(alpha: 0.55 + 0.35 * fireT),
      );
    }
  }
}
