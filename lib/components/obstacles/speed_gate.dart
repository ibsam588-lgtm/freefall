// components/obstacles/speed_gate.dart
//
// Friendly pickup, not a hazard. A glowing green ring the player passes
// through to claim +100 score and a 3-second camera-speed boost.
//
// One-shot: after the player passes through once, [onPlayerHit] returns
// [ObstacleHitEffect.none] and the gate dims. We keep the component
// alive for the dim animation so it visibly "spends" rather than
// vanishing under the player.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import 'game_obstacle.dart';

class SpeedGate extends GameObstacle {
  /// Score awarded on pass-through.
  static const int scoreReward = 100;

  /// Camera-speed boost amount, in px/s, applied for [boostDuration].
  static const double cameraBoostSpeed = 100;
  static const double boostDuration = 3.0;

  static const double ringRadius = 36;
  static const double ringThickness = 6;
  static const Color ringColor = Color(0xFF00FF88);
  static const Color glowColor = Color(0xFFA0FFD0);

  bool _consumed = false;
  double _consumedT = 0;
  double _phase = 0;

  SpeedGate({
    required super.obstacleId,
    required Vector2 worldPosition,
  }) : super(
          position: worldPosition,
          size: Vector2.all(ringRadius * 2),
        );

  bool get isConsumed => _consumed;

  @override
  void update(double dt) {
    super.update(dt);
    _phase += dt;
    if (_consumed) _consumedT += dt;
  }

  @override
  bool intersects(Rect playerRect) {
    if (_consumed) return false;
    return super.intersects(playerRect);
  }

  @override
  ObstacleHitEffect onPlayerHit() {
    if (_consumed) return ObstacleHitEffect.none;
    _consumed = true;
    return ObstacleHitEffect.boost;
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Once consumed, fade out over ~0.4s so the spend reads visually.
    final alpha = _consumed ? (1.0 - (_consumedT / 0.4)).clamp(0.0, 1.0) : 1.0;
    if (alpha <= 0) return;

    final pulse = 0.7 + 0.3 * math.sin(_phase * 4);

    // Outer glow halo.
    final halo = Paint()
      ..color = glowColor.withValues(alpha: 0.25 * alpha * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringThickness * 2.4;
    canvas.drawCircle(Offset(cx, cy), ringRadius, halo);

    // Bright primary ring.
    final ring = Paint()
      ..color = ringColor.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringThickness;
    canvas.drawCircle(Offset(cx, cy), ringRadius, ring);

    // Center sparkle hint to make the goal obvious.
    final sparkle = Paint()
      ..color = glowColor.withValues(alpha: 0.45 * alpha * pulse);
    canvas.drawCircle(Offset(cx, cy), ringThickness * 0.6, sparkle);
  }
}
