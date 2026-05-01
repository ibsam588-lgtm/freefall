// components/obstacles/gap_wall.dart
//
// Horizontal "wall with a hole" — two solid bars that span the play column
// with a navigable gap between them. The gap width is sourced from the
// DifficultyScaler so the opening tightens with depth, but is hard-floored
// at 60px so the player can always physically fit through.
//
// Custom hitbox: the AABB of the whole wall is huge (full play width),
// which is useless for the spatial grid. We override [intersects] to test
// the player against the two solid wall rects only, leaving the gap
// transparent to collisions.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../models/zone.dart';
import 'game_obstacle.dart';

class GapWall extends GameObstacle {
  /// Hard floor on the gap width regardless of what DifficultyScaler says,
  /// because the player orb is 36px across and we need a finger-friendly
  /// margin on either side.
  static const double minGapWidth = 60;

  static const double wallHeight = 24;
  static const double cornerRadius = 6;

  /// The full play-column width the wall spans. Spawner passes the game's
  /// logical width; tests can override.
  final double playWidth;

  /// Center-x of the gap, in world coords (0..playWidth).
  final double gapCenterX;

  /// Final, clamped gap width.
  final double gapWidth;

  final Zone zone;

  GapWall({
    required super.obstacleId,
    required double centerY,
    required this.playWidth,
    required this.gapCenterX,
    required double rawGapWidth,
    required this.zone,
  })  : gapWidth = math.max(minGapWidth, rawGapWidth),
        super(
          position: Vector2(playWidth / 2, centerY),
          size: Vector2(playWidth, wallHeight),
        );

  Rect get _leftWallRect {
    final leftRight = (gapCenterX - gapWidth / 2).clamp(0.0, playWidth);
    return Rect.fromLTWH(0, topY, leftRight, wallHeight);
  }

  Rect get _rightWallRect {
    final rightLeft = (gapCenterX + gapWidth / 2).clamp(0.0, playWidth);
    return Rect.fromLTWH(rightLeft, topY, playWidth - rightLeft, wallHeight);
  }

  @override
  bool intersects(Rect playerRect) =>
      _leftWallRect.overlaps(playerRect) ||
      _rightWallRect.overlaps(playerRect);

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.damage;

  @override
  void render(Canvas canvas) {
    // Render in local space — position is the wall's center, anchor=center,
    // so (0,0) here is the top-left of the size box (full playWidth wide,
    // wallHeight tall).
    final fill = Paint()..color = zone.bottomColor;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = zone.accentColor;

    final leftEnd = (gapCenterX - gapWidth / 2).clamp(0.0, playWidth);
    final rightStart = (gapCenterX + gapWidth / 2).clamp(0.0, playWidth);

    if (leftEnd > 0) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, leftEnd, wallHeight),
        const Radius.circular(cornerRadius),
      );
      canvas.drawRRect(r, fill);
      canvas.drawRRect(r, stroke);
    }
    if (rightStart < playWidth) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(rightStart, 0, playWidth - rightStart, wallHeight),
        const Radius.circular(cornerRadius),
      );
      canvas.drawRRect(r, fill);
      canvas.drawRRect(r, stroke);
    }
  }
}
