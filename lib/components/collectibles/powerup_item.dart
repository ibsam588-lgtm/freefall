// components/collectibles/powerup_item.dart
//
// Visual powerup pickup. Six effect kinds, each with a recognizable
// icon and a per-type accent color glow. Bounces vertically (sine
// wave, ~0.3s period) so it reads as interactive.
//
// On collection, the manager:
//   1. Reads [powerupType] and calls PowerupManager.activatePowerup,
//   2. Plays the [collectSound],
//   3. Pushes a brief HUD notification (managed elsewhere).

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../models/collectible.dart';

class PowerupItem extends PositionComponent {
  /// Bounce period in seconds.
  static const double bouncePeriod = 0.3;

  /// Vertical amplitude of the bounce in pixels.
  static const double bounceAmplitude = 4;

  /// Visual radius (icon fits inside this).
  static const double radius = 14;

  static Color accentFor(PowerupType t) => switch (t) {
        PowerupType.shield => const Color(0xFF40C4FF), // blue
        PowerupType.magnet => const Color(0xFFFF5252), // red horseshoe
        PowerupType.slowMo => const Color(0xFFB388FF), // violet clock
        PowerupType.scoreMultiplier => const Color(0xFFFFD740), // gold star
        PowerupType.coinMultiplier => const Color(0xFFFFB300), // amber coin stack
        PowerupType.extraLife => const Color(0xFFFF1744), // red heart
      };

  final PowerupType powerupType;
  final String collectibleId;
  final String collectSound;
  bool collected = false;

  // Cached bounce offset so render() and tests can read the same value
  // without re-evaluating the sine wave.
  double _t = 0;

  PowerupItem({
    required this.collectibleId,
    required this.powerupType,
    required Vector2 worldPosition,
    double? initialPhase,
  })  : collectSound = 'powerup_${powerupType.name}',
        super(
          position: worldPosition,
          size: Vector2.all(radius * 2),
          anchor: Anchor.center,
        ) {
    _t = initialPhase ?? 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  /// Current vertical offset in pixels (positive == bouncing up).
  double get bounceOffset =>
      bounceAmplitude * math.sin(_t * (2 * math.pi / bouncePeriod));

  @override
  void render(Canvas canvas) {
    if (collected) return;

    final accent = accentFor(powerupType);
    final cx = size.x / 2;
    final cy = size.y / 2 - bounceOffset;
    final center = Offset(cx, cy);

    // Halo — same blueprint as coin/gem, accent-colored.
    const haloR = radius * 2.0;
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: 0.6),
          accent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: haloR));
    canvas.drawCircle(center, haloR, haloPaint);

    // Disk backdrop so the icon reads no matter what's behind.
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFF101018).withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );

    // Per-type icon. Each draws in its own helper for clarity and so
    // tests can render-pump a single type without surprises.
    switch (powerupType) {
      case PowerupType.shield:
        _drawShield(canvas, center, accent);
        break;
      case PowerupType.magnet:
        _drawMagnet(canvas, center, accent);
        break;
      case PowerupType.slowMo:
        _drawClock(canvas, center, accent);
        break;
      case PowerupType.scoreMultiplier:
        _drawStarText(canvas, center, accent);
        break;
      case PowerupType.coinMultiplier:
        _drawCoinStack(canvas, center, accent);
        break;
      case PowerupType.extraLife:
        _drawHeart(canvas, center, accent);
        break;
    }
  }

  void _drawShield(Canvas canvas, Offset c, Color accent) {
    canvas.drawCircle(
      c,
      radius * 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = accent,
    );
    canvas.drawCircle(
      c,
      radius * 0.35,
      Paint()..color = accent.withValues(alpha: 0.4),
    );
  }

  void _drawMagnet(Canvas canvas, Offset c, Color accent) {
    // Two arcs forming a horseshoe + two pole tips.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = accent;
    final ringRect = Rect.fromCircle(center: c, radius: radius * 0.55);
    // Top half of a circle (arc from -π to 0).
    canvas.drawArc(ringRect, math.pi, math.pi, false, paint);

    // Pole tips — short verticals on either side, drawn in white-ish so
    // the magnet reads as positive/negative tips.
    final tipPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke;
    const r = radius * 0.55;
    canvas.drawLine(
      Offset(c.dx - r, c.dy),
      Offset(c.dx - r, c.dy + 4),
      tipPaint,
    );
    canvas.drawLine(
      Offset(c.dx + r, c.dy),
      Offset(c.dx + r, c.dy + 4),
      tipPaint,
    );
  }

  void _drawClock(Canvas canvas, Offset c, Color accent) {
    // Face.
    canvas.drawCircle(
      c,
      radius * 0.55,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );
    // Hour hand pointing up-right, minute hand pointing up — together
    // they read as "ticking forward".
    final handPaint = Paint()
      ..color = accent
      ..strokeWidth = 2;
    canvas.drawLine(c, Offset(c.dx, c.dy - radius * 0.45), handPaint);
    canvas.drawLine(
        c, Offset(c.dx + radius * 0.30, c.dy - radius * 0.20), handPaint);
  }

  void _drawStarText(Canvas canvas, Offset c, Color accent) {
    _drawStar(canvas, c, radius * 0.85, accent);
    final tp = TextPainter(
      text: const TextSpan(
        text: '2x',
        style: TextStyle(
          color: Color(0xFF101018),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(c.dx - tp.width / 2, c.dy - tp.height / 2),
    );
  }

  void _drawStar(Canvas canvas, Offset c, double r, Color accent) {
    // 5-point star.
    final path = Path();
    const points = 5;
    final outer = r;
    final inner = r * 0.45;
    for (int i = 0; i < points * 2; i++) {
      final angle = -math.pi / 2 + i * math.pi / points;
      final radius = i.isEven ? outer : inner;
      final p =
          Offset(c.dx + math.cos(angle) * radius, c.dy + math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = accent);
  }

  void _drawCoinStack(Canvas canvas, Offset c, Color accent) {
    // Three nested ellipses for a stack-of-coins read.
    for (int i = 0; i < 3; i++) {
      final dy = 4.0 - i * 4;
      final ellipse = Rect.fromCenter(
        center: Offset(c.dx, c.dy + dy),
        width: radius * 1.2,
        height: radius * 0.45,
      );
      canvas.drawOval(
        ellipse,
        Paint()..color = accent.withValues(alpha: 0.85),
      );
      canvas.drawOval(
        ellipse,
        Paint()
          ..color = const Color(0xFF101018)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  void _drawHeart(Canvas canvas, Offset c, Color accent) {
    // Two top lobes + bottom point. Drawn as a Path with cubics for the
    // smooth lobes.
    final path = Path();
    const w = radius * 0.85;
    final top = c.dy - w * 0.2;
    final bottom = c.dy + w * 0.85;
    path.moveTo(c.dx, bottom);
    path.cubicTo(
      c.dx - w * 1.3, c.dy + w * 0.1,
      c.dx - w * 0.6, top - w * 0.6,
      c.dx, c.dy - w * 0.1,
    );
    path.cubicTo(
      c.dx + w * 0.6, top - w * 0.6,
      c.dx + w * 1.3, c.dy + w * 0.1,
      c.dx, bottom,
    );
    path.close();
    canvas.drawPath(path, Paint()..color = accent);
  }
}
