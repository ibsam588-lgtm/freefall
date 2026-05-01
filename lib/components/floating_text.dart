// components/floating_text.dart
//
// One-shot floating score popup. Spawned at a world position, rises
// 40px over its lifetime, and fades out linearly. Used for "+50 CLOSE!",
// gem score numbers, zone-completion bonuses, etc.
//
// Self-disposing: the component removes itself from its parent when
// its life timer hits zero, so callers can just `world.add` and forget.

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class FloatingText extends PositionComponent {
  /// Pixels to drift upward over the full lifetime.
  static const double riseDistance = 40;

  /// Default fade-out duration in seconds.
  static const double defaultLifetime = 1.0;

  final String text;
  final Color color;
  final double fontSize;
  final double total;
  double remaining;

  // Cached starting Y so we can interpolate position based on life.
  late double _startY;

  FloatingText({
    required this.text,
    required Vector2 worldPosition,
    this.color = const Color(0xFFFFFFFF),
    this.fontSize = 14,
    double lifetime = defaultLifetime,
  })  : total = lifetime,
        remaining = lifetime,
        super(
          position: worldPosition,
          // Generous size box so the text isn't clipped during render.
          size: Vector2(120, 24),
          anchor: Anchor.center,
          priority: 800,
        );

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _startY = position.y;
  }

  /// Public for tests + the HUD to query without mounting Flame.
  double get lifeFraction => total <= 0 ? 0 : (remaining / total).clamp(0.0, 1.0);

  @override
  void update(double dt) {
    super.update(dt);
    remaining -= dt;
    final t = 1.0 - lifeFraction; // 0 at spawn, 1 at end
    position.y = _startY - riseDistance * t;
    if (remaining <= 0) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final alpha = lifeFraction;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withValues(alpha: alpha),
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: const Color(0xFF000000).withValues(alpha: alpha * 0.7),
              blurRadius: 4,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(size.x / 2 - tp.width / 2, size.y / 2 - tp.height / 2),
    );
  }
}
