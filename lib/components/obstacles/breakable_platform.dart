// components/obstacles/breakable_platform.dart
//
// Looks like a static platform but starts a 0.5s crumble timer the first
// time the player touches it, then disappears. The first contact still
// damages the player; subsequent frames during the crumble animation
// return [ObstacleHitEffect.none] so we don't double-charge.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../models/zone.dart';
import 'game_obstacle.dart';

class BreakablePlatform extends GameObstacle {
  static const double minWidth = 80;
  static const double maxWidth = 160;
  static const double barHeight = 20;
  static const double cornerRadius = 6;

  /// Time from first contact to the platform fully crumbling away.
  static const double crumbleDuration = 0.5; // seconds

  final Zone zone;
  bool _triggered = false;
  double _crumbleProgress = 0; // 0 = intact, 1 = gone
  bool _consumed = false;

  BreakablePlatform({
    required super.obstacleId,
    required Vector2 worldPosition,
    required this.zone,
    double? width,
    math.Random? rng,
  }) : super(
          position: worldPosition,
          size: Vector2(
            width ??
                (minWidth +
                    (rng ?? math.Random()).nextDouble() * (maxWidth - minWidth)),
            barHeight,
          ),
        );

  /// 0..1 crumble fraction. Public so the manager can decide when to
  /// remove the component (after the crumble completes).
  double get crumbleProgress => _crumbleProgress;

  /// True once the platform has fully crumbled and contributes nothing.
  bool get isGone => _crumbleProgress >= 1.0;

  @override
  void update(double dt) {
    super.update(dt);
    if (_triggered && _crumbleProgress < 1.0) {
      _crumbleProgress =
          (_crumbleProgress + dt / crumbleDuration).clamp(0.0, 1.0);
    }
  }

  @override
  ObstacleHitEffect onPlayerHit() {
    if (_consumed || isGone) return ObstacleHitEffect.none;
    _consumed = true;
    _triggered = true;
    return ObstacleHitEffect.damage;
  }

  @override
  bool intersects(Rect playerRect) {
    // Once the player has triggered this platform, treat it as
    // pass-through for the rest of the crumble animation. The platform
    // is visually fading out and `onPlayerHit` returns `none` anyway
    // — keeping it solid for collision queries causes the obstacle
    // pipeline to keep flagging it as a hit each frame, which:
    //   1. visually reads as the player "stuck" inside a half-faded
    //      platform without taking damage,
    //   2. blocks the per-frame "single hit" early-out from advancing
    //      to a real hazard the same frame would otherwise hit.
    if (_consumed || isGone) return false;
    return super.intersects(playerRect);
  }

  @override
  void render(Canvas canvas) {
    if (isGone) return;
    final body = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect =
        RRect.fromRectAndRadius(body, const Radius.circular(cornerRadius));

    // Fade out + crack overlay as the platform crumbles.
    final alpha = (1.0 - _crumbleProgress).clamp(0.0, 1.0);
    canvas.drawRRect(
      rrect,
      Paint()..color = zone.bottomColor.withValues(alpha: alpha),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = zone.accentColor.withValues(alpha: alpha),
    );

    if (_triggered) {
      // Subtle hatched cracks growing with crumbleProgress.
      final crackPaint = Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.4 * alpha)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      const n = 4;
      for (int i = 1; i <= n; i++) {
        final t = i / (n + 1);
        final yOffset = (i.isOdd ? 1 : -1) * 4 * _crumbleProgress;
        canvas.drawLine(
          Offset(t * size.x, 0),
          Offset(t * size.x + yOffset, size.y),
          crackPaint,
        );
      }
    }
  }
}
