// components/obstacles/static_platform.dart
//
// The simplest obstacle: a horizontal rectangular bar the player has to
// dodge around. Width is randomised at spawn within [minWidth..maxWidth]
// so the play column never reads as a uniform grid.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../models/zone.dart';
import 'game_obstacle.dart';

class StaticPlatform extends GameObstacle {
  static const double minWidth = 80;
  static const double maxWidth = 180;
  static const double barHeight = 20;
  static const double cornerRadius = 6;

  /// Zone whose accent color tints the bar. Stored rather than re-resolved
  /// each frame because the obstacle's zone is fixed at spawn time.
  final Zone zone;

  StaticPlatform({
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

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.damage;

  @override
  void render(Canvas canvas) {
    final body = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect =
        RRect.fromRectAndRadius(body, const Radius.circular(cornerRadius));

    // Solid fill in the zone's bottom (deepest) tone, capped on top with
    // the brighter accent — gives the bar visual weight without art assets.
    canvas.drawRRect(rrect, Paint()..color = zone.bottomColor);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = zone.accentColor,
    );
  }
}
