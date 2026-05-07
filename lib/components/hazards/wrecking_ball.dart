// components/hazards/wrecking_ball.dart
//
// City-zone hazard. A heavy spherical mass on a chain that swings as a
// damped pendulum from a fixed anchor. The anchor lives "above" the
// hazard's spawn position; the ball traces an arc through the play column.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../obstacles/game_obstacle.dart';

class WreckingBall extends GameObstacle {
  static const double ballRadius = 22;
  static const double chainLength = 120; // pixels from anchor to ball center
  static const double maxSwingAngle = math.pi / 3; // 60° each side
  static const double angularSpeed = 1.6; // rad/s

  /// Anchor in world coordinates. The ball's position is derived from
  /// anchor + chain at the current swing angle.
  final Vector2 anchorPosition;

  double _swingPhase;

  /// Ball center at the START of the most recent frame. Used to sweep
  /// the ball's arc through the frame in [intersects] so a fast
  /// pendulum can't pass over a slow player between physics steps.
  final Vector2 _prevPosition = Vector2.zero();
  bool _prevPositionInitialized = false;

  WreckingBall({
    required super.obstacleId,
    required this.anchorPosition,
    double? initialPhase,
    math.Random? rng,
  })  : _swingPhase = initialPhase ??
            (rng ?? math.Random()).nextDouble() * math.pi * 2,
        super(
          position: anchorPosition + Vector2(0, chainLength),
          size: Vector2.all(ballRadius * 2),
        );

  double get swingAngle =>
      maxSwingAngle * math.sin(_swingPhase);

  @override
  void update(double dt) {
    super.update(dt);
    if (!_prevPositionInitialized) {
      _prevPosition.setFrom(position);
      _prevPositionInitialized = true;
    } else {
      _prevPosition.setFrom(position);
    }
    _swingPhase += angularSpeed * dt;
    final angle = swingAngle;
    position
      ..x = anchorPosition.x + chainLength * math.sin(angle)
      ..y = anchorPosition.y + chainLength * math.cos(angle);
  }

  /// Circle-vs-AABB distance test against the player's rect. The old
  /// rect-vs-rect check inflated the lethal zone at the diagonal
  /// corners (~7px past the visible ball edge). Also checks the prior
  /// frame's center so a pendulum that swung past the player between
  /// frames isn't missed.
  @override
  bool intersects(Rect playerRect) {
    if (_circleHitsRect(position.x, position.y, playerRect)) return true;
    if (_prevPositionInitialized &&
        _circleHitsRect(_prevPosition.x, _prevPosition.y, playerRect)) {
      return true;
    }
    return false;
  }

  bool _circleHitsRect(double cx, double cy, Rect r) {
    final closestX = cx.clamp(r.left, r.right);
    final closestY = cy.clamp(r.top, r.bottom);
    final dx = cx - closestX;
    final dy = cy - closestY;
    return dx * dx + dy * dy <= ballRadius * ballRadius;
  }

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.damage;

  @override
  void render(Canvas canvas) {
    // Draw chain in world coords by shifting back from local space:
    // local (size/2, size/2) corresponds to world (position.x, position.y),
    // so anchor in local space is anchor - position + size/2.
    final localAnchor = Offset(
      anchorPosition.x - position.x + size.x / 2,
      anchorPosition.y - position.y + size.y / 2,
    );
    final localCenter = Offset(size.x / 2, size.y / 2);

    final chainPaint = Paint()
      ..color = const Color(0xFF555555)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawLine(localAnchor, localCenter, chainPaint);

    // Anchor mount — small block at the chain's top.
    canvas.drawRect(
      Rect.fromCenter(center: localAnchor, width: 14, height: 8),
      Paint()..color = const Color(0xFF222222),
    );

    // Ball — dark with a metallic accent.
    final body = Paint()..color = const Color(0xFF2A2A35);
    final accent = Paint()
      ..color = const Color(0xFFFF3DCB).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(localCenter, ballRadius, body);
    canvas.drawCircle(localCenter, ballRadius, accent);

    // Spike highlight to read as heavy iron.
    final highlight = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.15);
    canvas.drawCircle(
      localCenter.translate(-ballRadius / 3, -ballRadius / 3),
      ballRadius / 3,
      highlight,
    );
  }
}
