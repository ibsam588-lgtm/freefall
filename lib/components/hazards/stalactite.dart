// components/hazards/stalactite.dart
//
// Underground hazard. Hangs from above; once the player passes within
// 200px horizontally, the stalactite releases and falls under gravity.
// In flight it's an instant kill — landing on a stalactite head is
// usually how a deep underground run ends.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../obstacles/game_obstacle.dart';

class Stalactite extends GameObstacle {
  /// Horizontal distance at which the stalactite triggers and starts to
  /// fall. Exposed as a static constant so the spawner can reason about
  /// safe spacing of triggering corridors.
  static const double triggerHorizontalDistance = 200;

  static const double spikeWidth = 26;
  static const double spikeHeight = 60;
  static const double dropAcceleration = 1400; // px/s²
  static const double maxDropSpeed = 1200; // px/s

  bool _falling = false;
  double _fallVelocity = 0;

  /// World-Y position at the START of the most recent frame. Stored so
  /// [intersects] can sweep across the frame's vertical travel — at
  /// [maxDropSpeed] (1200 px/s) under a clamped 1/30s frame the spike
  /// can move 40px in one step, large enough to overshoot a slow player
  /// without an end-of-frame-only check catching it.
  double _prevPositionY = double.nan;

  Stalactite({
    required super.obstacleId,
    required Vector2 worldPosition,
  }) : super(
          position: worldPosition,
          size: Vector2(spikeWidth, spikeHeight),
        );

  bool get isFalling => _falling;

  /// Per-frame trigger check. The owning system or manager calls this
  /// with the player's current world position; once triggered the
  /// stalactite begins falling and the call becomes a no-op.
  void considerTrigger(Vector2 playerWorldPos) {
    if (_falling) return;
    final dx = (playerWorldPos.x - position.x).abs();
    if (dx <= triggerHorizontalDistance &&
        playerWorldPos.y < position.y + spikeHeight) {
      _falling = true;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Snapshot the pre-physics Y so [intersects] can sweep the spike's
    // body across the frame's full vertical travel. NaN-guard for the
    // first frame: before any update has run, prev == current.
    if (_prevPositionY.isNaN) _prevPositionY = position.y;
    final priorY = position.y;
    if (_falling) {
      _fallVelocity =
          (_fallVelocity + dropAcceleration * dt).clamp(0.0, maxDropSpeed);
      position.y += _fallVelocity * dt;
    }
    _prevPositionY = priorY;
  }

  /// Triangle-vs-circle hitbox. Visual is a downward-pointing triangle
  /// (wide at top, lethal point at bottom); the AABB has empty corner
  /// regions on the lower half. We test the player's circle against the
  /// triangle directly and additionally sweep the triangle's vertical
  /// travel between [_prevPositionY] and the current position so a
  /// fast-falling spike can't tunnel past a slow player between frames.
  @override
  bool intersects(Rect playerRect) {
    final cx = playerRect.center.dx;
    final cy = playerRect.center.dy;
    final r = math.min(playerRect.width, playerRect.height) / 2;

    // Sweep: try the spike at both prev and current Y. Same X (the spike
    // doesn't move horizontally). NaN guard for first frame.
    final positionsToTest = <double>[
      position.y,
      if (!_prevPositionY.isNaN && _prevPositionY != position.y) _prevPositionY,
    ];
    for (final ty in positionsToTest) {
      final tlX = position.x - size.x / 2;
      final tlY = ty - size.y / 2;
      final a = Offset(tlX, tlY);
      final b = Offset(tlX + size.x, tlY);
      final tip = Offset(tlX + size.x * 0.5, tlY + size.y);
      if (_circleHitsTriangle(cx, cy, r, a, b, tip)) return true;
    }
    return false;
  }

  static bool _circleHitsTriangle(
    double cx,
    double cy,
    double r,
    Offset a,
    Offset b,
    Offset c,
  ) {
    if (_pointInTriangle(cx, cy, a, b, c)) return true;
    return _circleHitsSegment(cx, cy, r, a, b) ||
        _circleHitsSegment(cx, cy, r, b, c) ||
        _circleHitsSegment(cx, cy, r, c, a);
  }

  static bool _pointInTriangle(double px, double py, Offset a, Offset b, Offset c) {
    double sign(double x1, double y1, double x2, double y2, double x3, double y3) =>
        (x1 - x3) * (y2 - y3) - (x2 - x3) * (y1 - y3);
    final d1 = sign(px, py, a.dx, a.dy, b.dx, b.dy);
    final d2 = sign(px, py, b.dx, b.dy, c.dx, c.dy);
    final d3 = sign(px, py, c.dx, c.dy, a.dx, a.dy);
    final hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
    final hasPos = d1 > 0 || d2 > 0 || d3 > 0;
    return !(hasNeg && hasPos);
  }

  static bool _circleHitsSegment(
    double cx,
    double cy,
    double r,
    Offset a,
    Offset b,
  ) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) {
      final ex = cx - a.dx, ey = cy - a.dy;
      return ex * ex + ey * ey <= r * r;
    }
    final t = (((cx - a.dx) * dx + (cy - a.dy) * dy) / lenSq).clamp(0.0, 1.0);
    final px = a.dx + dx * t, py = a.dy + dy * t;
    final ex = cx - px, ey = cy - py;
    return ex * ex + ey * ey <= r * r;
  }

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.kill;

  @override
  void render(Canvas canvas) {
    // Tapered downward — wide at top (where it hangs), narrow point at
    // bottom (the lethal tip).
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.x, 0)
      ..lineTo(size.x * 0.5, size.y)
      ..close();

    final body = Paint()..color = const Color(0xFF6B4423);
    final stroke = Paint()
      ..color = const Color(0xFFFFB347)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, body);
    canvas.drawPath(path, stroke);

    // Subtle highlight stripe so the stalactite reads as 3D rock.
    final highlight = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.18)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.x * 0.3, 4),
      Offset(size.x * 0.45, size.y * 0.85),
      highlight,
    );
  }
}
