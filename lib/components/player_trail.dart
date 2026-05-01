// components/player_trail.dart
//
// Trail renderer attached to the Player. Reads the player's recent
// position history and draws one of seven cosmetic effects switched on
// the active TrailEffect. Lives as a child of Player so it inherits the
// player's transform — but it draws in *world* coordinates relative to
// the player's local origin so each trail sample maps back to where the
// player physically was.

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../models/trail_effect.dart';

class PlayerTrail extends Component {
  /// Active effect — the parent Player swaps this when the user picks a
  /// new trail in the store.
  TrailEffect effect;

  /// Base color, usually pulled from the active PlayerSkin's trailColor.
  Color color;

  /// Reference back to the player so we can read [_trail] and the
  /// player's current position. Kept as a callback rather than a
  /// PositionComponent reference to avoid a hard import cycle in tests.
  final List<Vector2> Function() trailProvider;
  final Vector2 Function() positionProvider;
  final double Function() radiusProvider;

  /// Internal animation phase. Drives sparkle rotation, glitch flicker,
  /// helix sine wave. Advanced in [update] every frame.
  double _phase = 0;

  // Stable per-sample jitter for the glitch effect. Re-rolling every
  // frame would alias into a noise field — caching here gives a
  // glitch that stutters rather than fizzes.
  final List<double> _glitchOffsets = List.filled(64, 0);
  double _glitchTimer = 0;
  final math.Random _rng = math.Random(0xFEED);

  PlayerTrail({
    required this.effect,
    required this.color,
    required this.trailProvider,
    required this.positionProvider,
    required this.radiusProvider,
  });

  @override
  void update(double dt) {
    super.update(dt);
    if (effect.animated) {
      _phase += dt;
      if (effect.id == TrailId.glitch) {
        _glitchTimer -= dt;
        if (_glitchTimer <= 0) {
          // Re-roll offsets ~15 times a second.
          _glitchTimer = 1 / 15;
          for (int i = 0; i < _glitchOffsets.length; i++) {
            _glitchOffsets[i] = (_rng.nextDouble() * 2 - 1) * 10;
          }
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final samples = trailProvider();
    if (samples.isEmpty) return;

    switch (effect.id) {
      case TrailId.default_:
        _renderDefault(canvas, samples);
        break;
      case TrailId.comet:
        _renderComet(canvas, samples);
        break;
      case TrailId.helix:
        _renderHelix(canvas, samples);
        break;
      case TrailId.sparkle:
        _renderSparkle(canvas, samples);
        break;
      case TrailId.glitch:
        _renderGlitch(canvas, samples);
        break;
      case TrailId.ghost:
        _renderGhost(canvas, samples);
        break;
      case TrailId.warp:
        _renderWarp(canvas, samples);
        break;
    }
  }

  // Trail samples are stored in *world* coordinates. Since this
  // component is a child of Player (which is positioned in the world),
  // we render relative to the player's local origin by subtracting the
  // player's current world position from each sample.
  Offset _toLocal(Vector2 world) {
    final p = positionProvider();
    return Offset(world.x - p.x, world.y - p.y);
  }

  void _renderDefault(Canvas canvas, List<Vector2> samples) {
    final r = radiusProvider();
    for (int i = 0; i < samples.length; i++) {
      // i==last is newest; fade from headAlpha down to 0.
      final t = (i + 1) / samples.length; // 0..1
      final p = _toLocal(samples[i]);
      final a = effect.headAlpha * t;
      final paint = Paint()..color = color.withValues(alpha: a.clamp(0, 1));
      canvas.drawCircle(p, r * (0.35 + 0.45 * t), paint);
    }
  }

  void _renderComet(Canvas canvas, List<Vector2> samples) {
    final r = radiusProvider();
    const hot = Color(0xFFFFFFFF);
    for (int i = 0; i < samples.length; i++) {
      final t = (i + 1) / samples.length;
      final p = _toLocal(samples[i]);
      // Lerp hot-white head -> base color tail.
      final c = Color.lerp(color, hot, t)!;
      // Elongated ellipse: thinner at the back, taller at the front.
      final w = r * (0.25 + 0.7 * t);
      final h = r * (0.6 + 1.4 * t);
      final paint = Paint()..color = c.withValues(alpha: effect.headAlpha * t);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: w * 2, height: h * 2), paint);
      canvas.restore();
    }
  }

  void _renderHelix(Canvas canvas, List<Vector2> samples) {
    final r = radiusProvider();
    for (int i = 0; i < samples.length; i++) {
      final t = (i + 1) / samples.length;
      final p = _toLocal(samples[i]);
      // Sine offset around the trail's vertical axis. Phase shifts in
      // time so the helix appears to spin.
      final theta = (i * 0.6) - _phase * 4;
      final swing = math.sin(theta) * r * 1.2;
      final a = effect.headAlpha * t;
      final paint = Paint()..color = color.withValues(alpha: a);
      canvas.drawCircle(Offset(p.dx + swing, p.dy), r * (0.25 + 0.4 * t), paint);
      // Mirrored strand for the second helix coil.
      canvas.drawCircle(Offset(p.dx - swing, p.dy), r * (0.25 + 0.4 * t),
          Paint()..color = color.withValues(alpha: a * 0.7));
    }
  }

  void _renderSparkle(Canvas canvas, List<Vector2> samples) {
    final r = radiusProvider();
    for (int i = 0; i < samples.length; i++) {
      final t = (i + 1) / samples.length;
      final p = _toLocal(samples[i]);
      final rotation = _phase * 3 + i * 0.4;
      _drawStar(canvas, p, r * 0.55 * t, rotation,
          color.withValues(alpha: effect.headAlpha * t));
    }
  }

  /// Five-point star centered on [c]. [rOuter] sets the tip radius;
  /// inner points are 40% of that. [rotation] is in radians.
  void _drawStar(Canvas canvas, Offset c, double rOuter, double rotation, Color col) {
    if (rOuter < 0.5) return;
    final rInner = rOuter * 0.4;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final a = rotation + i * math.pi / 5;
      final r = i.isEven ? rOuter : rInner;
      final x = c.dx + math.cos(a) * r;
      final y = c.dy + math.sin(a) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = col);
  }

  void _renderGlitch(Canvas canvas, List<Vector2> samples) {
    final r = radiusProvider();
    // Brief flicker: alternate sample alpha based on phase parity.
    final flickerOn = (_phase * 30).floor().isEven;
    for (int i = 0; i < samples.length; i++) {
      final t = (i + 1) / samples.length;
      final p = _toLocal(samples[i]);
      final dx = _glitchOffsets[i % _glitchOffsets.length];
      final flickerAlpha = flickerOn || i.isEven ? 1.0 : 0.4;
      final a = effect.headAlpha * t * flickerAlpha;
      // Three-channel chromatic split for that VHS-glitch look.
      final paintR = Paint()..color = const Color(0xFFFF3366).withValues(alpha: a * 0.6);
      final paintB = Paint()..color = const Color(0xFF33CCFF).withValues(alpha: a * 0.6);
      final paintMain = Paint()..color = color.withValues(alpha: a);
      canvas.drawCircle(Offset(p.dx + dx + 2, p.dy), r * 0.5 * t, paintR);
      canvas.drawCircle(Offset(p.dx + dx - 2, p.dy), r * 0.5 * t, paintB);
      canvas.drawCircle(Offset(p.dx + dx, p.dy), r * 0.5 * t, paintMain);
    }
  }

  void _renderGhost(Canvas canvas, List<Vector2> samples) {
    final r = radiusProvider();
    for (int i = 0; i < samples.length; i++) {
      final t = (i + 1) / samples.length;
      final p = _toLocal(samples[i]);
      // Soft, blurred white blob that absorbs the skin's trailColor only
      // faintly — ghost should always read as ethereal and pale.
      final tint = Color.lerp(Colors.white, color, 0.25)!;
      final paint = Paint()
        ..color = tint.withValues(alpha: effect.headAlpha * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(p, r * (0.6 + 0.6 * t), paint);
    }
  }

  void _renderWarp(Canvas canvas, List<Vector2> samples) {
    if (samples.length < 2) return;
    // Curved path connecting all sample points using cubic beziers.
    // Control points are offsets perpendicular to the segment so the
    // line snakes — gives the "warp tunnel" feel.
    final paint = Paint()
      ..color = const Color(0xFF40C4FF).withValues(alpha: effect.headAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final path = Path();
    final first = _toLocal(samples.first);
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < samples.length; i++) {
      final prev = _toLocal(samples[i - 1]);
      final curr = _toLocal(samples[i]);
      // Symmetric control points around the segment midpoint, swung
      // by an alternating perpendicular offset.
      final mx = (prev.dx + curr.dx) / 2;
      final my = (prev.dy + curr.dy) / 2;
      final perp = (i.isEven ? 1 : -1) * 8.0;
      path.cubicTo(prev.dx + perp, prev.dy, mx + perp, my, curr.dx, curr.dy);
    }
    canvas.drawPath(path, paint);

    // Bright core overlay.
    final core = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawPath(path, core);
  }
}
