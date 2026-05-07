// components/obstacles/rotating_obstacle.dart
//
// 2–4 arms radiating from a hub, rotating at a fixed angular velocity.
// The collision test sweeps each arm as a thin oriented rectangle and
// reduces it to an AABB-vs-AABB check after rotating the player into
// the arm's local frame.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../models/zone.dart';
import 'game_obstacle.dart';

class RotatingObstacle extends GameObstacle {
  static const double minAngularSpeed = 1.0; // rad/s
  static const double maxAngularSpeed = 3.0; // rad/s
  static const int minArms = 2;
  static const int maxArms = 4;

  static const double armLength = 50; // pixels from hub center to tip
  static const double armWidth = 14;
  static const double hubRadius = 10;

  final Zone zone;
  final int armCount;
  final double angularSpeed; // signed
  double _rotation = 0;

  /// Arm angle at the START of the most recent frame. Stored so that
  /// [intersects] can check both the previous and current rotation.
  /// WHY: [_rotation] is already advanced by [update] before the
  /// collision pass runs. If an arm was in the player's path at frame
  /// start and has since rotated away, the end-of-frame-only check
  /// would miss the contact. Testing both endpoints covers all cases
  /// given that max angular travel per frame (~0.1 rad) is smaller than
  /// the player's angular width from the arm (~0.36 rad at arm tip).
  double _prevRotation = 0;

  RotatingObstacle({
    required super.obstacleId,
    required Vector2 worldPosition,
    required this.zone,
    int? armCount,
    double? angularSpeed,
    math.Random? rng,
  })  : armCount = (armCount ??
                ((rng ?? math.Random()).nextInt(maxArms - minArms + 1) +
                    minArms))
            .clamp(minArms, maxArms),
        // Random sign flip only applies when no explicit speed was
        // given. WHY: a caller passing a specific value (like a test
        // expecting rotation +2 rad/s) shouldn't see the value clobbered
        // to -2 half the time.
        angularSpeed = angularSpeed ??
            ((minAngularSpeed +
                    (rng ?? math.Random()).nextDouble() *
                        (maxAngularSpeed - minAngularSpeed)) *
                ((rng ?? math.Random()).nextBool() ? 1 : -1)),
        super(
          position: worldPosition,
          // Bounding box covers a full arm sweep in any direction.
          size: Vector2.all((armLength + armWidth) * 2),
        );

  double get rotation => _rotation;

  @override
  void update(double dt) {
    super.update(dt);
    _prevRotation = _rotation; // snapshot before advancing
    _rotation += angularSpeed * dt;
  }

  @override
  bool intersects(Rect playerRect) {
    // Hub is always solid.
    final hub = Rect.fromCircle(
      center: Offset(position.x, position.y),
      radius: hubRadius,
    );
    if (hub.overlaps(playerRect)) return true;

    // Each arm: rotate the player rect into the arm's local frame and
    // do an AABB overlap with the arm's axis-aligned local box.
    //
    // We test both [_prevRotation] (arm position at frame start) and
    // [_rotation] (arm position at frame end). The collision pass sweeps
    // the player through multiple positions between those two extremes,
    // but the arm angle is always the end-of-frame value for every
    // substep — so an arm that was in the player's path at frame start
    // and has since rotated away would go undetected without this.
    // Checking both endpoints is sufficient because the max angular
    // travel per frame (~0.1 rad at maxAngularSpeed) is less than the
    // player's angular width as seen from the arm (~0.36 rad at tip).
    final px = playerRect.center.dx - position.x;
    final py = playerRect.center.dy - position.y;
    final r2 = math.max(playerRect.width, playerRect.height) / 2;

    // Arm extends from x=0..armLength, half-width armWidth/2 around y=0.
    // Inflate by the player's circumscribed half-extent for a cheap
    // capsule-circle approximation.
    final armRect = Rect.fromLTWH(
      -r2,
      -armWidth / 2 - r2,
      armLength + 2 * r2,
      armWidth + 2 * r2,
    );

    for (final baseAngle in [_rotation, _prevRotation]) {
      for (int i = 0; i < armCount; i++) {
        final angle = baseAngle + i * (math.pi * 2 / armCount);
        final c = math.cos(-angle);
        final s = math.sin(-angle);
        final localX = px * c - py * s;
        final localY = px * s + py * c;
        if (armRect.contains(Offset(localX, localY))) return true;
      }
    }
    return false;
  }

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.damage;

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    final armPaint = Paint()..color = zone.bottomColor;
    final armStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = zone.accentColor;

    for (int i = 0; i < armCount; i++) {
      final angle = _rotation + i * (math.pi * 2 / armCount);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      const r = Rect.fromLTWH(0, -armWidth / 2, armLength, armWidth);
      final rr =
          RRect.fromRectAndRadius(r, const Radius.circular(armWidth / 2));
      canvas.drawRRect(rr, armPaint);
      canvas.drawRRect(rr, armStroke);
      canvas.restore();
    }

    // Hub on top so the arms appear to attach to it cleanly.
    canvas.drawCircle(
      Offset(cx, cy),
      hubRadius,
      Paint()..color = zone.accentColor,
    );
  }
}
