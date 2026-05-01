// components/collectibles/coin.dart
//
// Visual coin Flame component. Four tiers (bronze/silver/gold/diamond)
// share rendering; size and color are picked from [coinType]. The coin
// pulses (radial scale) via a sin wave so it reads as "alive" against
// the dark background.
//
// Coin doesn't move on its own — the world scrolls past it. The magnet
// powerup pulls it toward the player by mutating [position] from
// CollectibleManager, never from the component itself.
//
// Note: Phase 1 introduced a barebones data carrier `Coin` in
// lib/components/coin.dart that the legacy CoinPool uses. This visual
// Coin lives in a different library path so callers can pick which
// one they need (CoinPool keeps the data carrier; CollectibleManager
// uses this component).

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/collectible.dart';

class Coin extends PositionComponent {
  static const double pulseHz = 1.4;

  /// Per-tier visual radius in world pixels.
  static double radiusFor(CoinType t) => switch (t) {
        CoinType.bronze => 7,
        CoinType.silver => 8,
        CoinType.gold => 9,
        CoinType.diamond => 11,
      };

  /// Per-tier metallic palette (rim, core).
  static (Color rim, Color core) paletteFor(CoinType t) => switch (t) {
        CoinType.bronze => (const Color(0xFF8B4513), const Color(0xFFCD7F32)),
        CoinType.silver => (const Color(0xFF7A7A7A), const Color(0xFFE0E0E0)),
        CoinType.gold => (const Color(0xFFB8860B), const Color(0xFFFFD700)),
        CoinType.diamond => (const Color(0xFF008B8B), const Color(0xFF80FFFF)),
      };

  CoinType coinType;

  /// Audio cue queued by the collectible manager on pickup. Stored on
  /// the model so the manager doesn't need a switch.
  final String collectSound;

  /// Stable id used by tests/manager bookkeeping.
  final String collectibleId;

  /// True once the manager has consumed this coin. Render skips drawing
  /// it so the next-frame removal is invisible.
  bool collected = false;

  /// Per-coin phase offset so neighboring coins don't pulse in lock-step.
  final double _phaseOffset;
  double _t = 0;

  Coin({
    required this.collectibleId,
    required this.coinType,
    required Vector2 worldPosition,
    String? collectSound,
    double? phaseOffset,
  })  : collectSound = collectSound ?? _defaultSound(coinType),
        _phaseOffset = phaseOffset ?? math.Random().nextDouble() * math.pi * 2,
        super(
          position: worldPosition,
          size: Vector2.all(radiusFor(coinType) * 2),
          anchor: Anchor.center,
        );

  /// Currency value of this coin, looked up from the model.
  int get value => CoinValue.forType(coinType);

  /// Visual radius (excludes glow).
  double get radius => radiusFor(coinType);

  static String _defaultSound(CoinType t) => switch (t) {
        CoinType.bronze => 'coin_bronze',
        CoinType.silver => 'coin_silver',
        CoinType.gold => 'coin_gold',
        CoinType.diamond => 'coin_diamond',
      };

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  /// 0.9..1.1 pulsing scale factor. Public so tests can assert the wave
  /// is bounded and not stuck.
  double get pulseScale =>
      1.0 + 0.1 * math.sin((_t * pulseHz * math.pi * 2) + _phaseOffset);

  @override
  void render(Canvas canvas) {
    if (collected) return;

    final scale = pulseScale;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final center = Offset(cx, cy);
    final r = radius * scale;

    final palette = paletteFor(coinType);

    // Soft outer halo so the coin reads from a distance — bigger and
    // dimmer than the body. Radial gradient fading to transparent.
    final haloR = r * 2.4;
    final haloRect = Rect.fromCircle(center: center, radius: haloR);
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.$2.withValues(alpha: 0.55),
          palette.$2.withValues(alpha: 0.0),
        ],
      ).createShader(haloRect);
    canvas.drawCircle(center, haloR, haloPaint);

    // Body — bright core fading to rim color.
    final bodyRect = Rect.fromCircle(center: center, radius: r);
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        colors: [palette.$2, palette.$1],
        stops: const [0.2, 1.0],
      ).createShader(bodyRect);
    canvas.drawCircle(center, r, bodyPaint);

    // Specular highlight — small white dot offset toward upper-left so
    // the coin looks rounded.
    canvas.drawCircle(
      Offset(center.dx - r * 0.35, center.dy - r * 0.35),
      r * 0.22,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.7),
    );
  }
}
