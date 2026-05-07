// components/floating_text.dart
//
// One-shot floating score popup. Spawned at a world position, rises
// 40px over its lifetime, and fades out linearly. Used for "+50 CLOSE!",
// gem score numbers, zone-completion bonuses, etc.
//
// Self-disposing: the component removes itself from its parent when
// its life timer hits zero, so callers can just `world.add` and forget.
//
// Performance note: at peak we can have ~60 FloatingTexts alive during
// a long combo (near-miss spam). The naive implementation allocated a
// TextPainter and called `.layout()` every frame, which burns
// measurable time on Skia's text measurement. We re-layout only when
// the alpha actually changes by more than [_alphaQuantum] (i.e. ~20
// times per second instead of 60), then paint the cached painter.

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class FloatingText extends PositionComponent {
  /// Pixels to drift upward over the full lifetime.
  static const double riseDistance = 40;

  /// Default fade-out duration in seconds.
  static const double defaultLifetime = 1.0;

  /// Quantize the rendered alpha to this granularity. 0.05 -> 20
  /// distinct alpha steps over the fade window, which is visually
  /// indistinguishable from a smooth fade but cuts TextPainter.layout
  /// calls by ~3x at 60 fps.
  static const double _alphaQuantum = 0.05;

  final String text;
  final Color color;
  final double fontSize;
  final double total;
  double remaining;

  // Cached starting Y so we can interpolate position based on life.
  late double _startY;

  // Cached painter; rebuilt when [_paintedAlpha] no longer matches the
  // quantized current alpha. Null until the first paint pass.
  TextPainter? _painter;
  double _paintedAlpha = -1;

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
    final raw = lifeFraction;
    if (raw <= 0) return;
    // Quantize to a small set of distinct alpha values; rebuild the
    // painter only when we cross a step.
    final alpha = (raw / _alphaQuantum).round() * _alphaQuantum;
    if (_painter == null || alpha != _paintedAlpha) {
      _painter = TextPainter(
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
      _paintedAlpha = alpha;
    }
    final tp = _painter!;
    tp.paint(
      canvas,
      Offset(size.x / 2 - tp.width / 2, size.y / 2 - tp.height / 2),
    );
  }
}
