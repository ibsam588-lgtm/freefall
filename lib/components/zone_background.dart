// components/zone_background.dart
//
// Full-viewport backdrop component. Each frame it:
//   1. Repositions itself to cover the camera viewport (it lives in
//      world space but tracks the camera so we don't need a separate
//      viewport child for the gradient).
//   2. Draws the vertical zone gradient resolved by [ZoneManager].
//   3. Renders zone-specific ambient layers (skyline, stalactites,
//      ocean bands, magma glow) at parallax-fractional scroll rates.
//   4. Steps and renders a small pool of zone-flavored particles
//      (clouds, neon dots, dust, bubbles, embers).
//
// Particles & ambient layers are deliberately allocation-light: a fixed
// pool of [_particleCount] structs is reused for the run, so this whole
// file should add zero per-frame heap pressure.

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/freefall_game.dart';
import '../models/zone.dart';
import '../systems/camera_system.dart';
import '../systems/performance_monitor.dart';
import '../systems/zone_manager.dart';

/// Single ambient particle (cloud puff, ember, bubble, etc). Reused
/// across the run — we just rewrap one when it scrolls off-screen.
class _Particle {
  double x = 0;
  double y = 0;
  double radius = 4;
  double drift = 0; // horizontal drift px/s
  double rise = 0; // vertical rise px/s (negative == moves down)
  double phase = 0; // phase offset for pulses / wobble
  double seed = 0; // deterministic per-particle randomness
}

class ZoneBackground extends PositionComponent {
  /// Camera scroll fraction for the far parallax layer.
  static const double farParallax = 0.3;

  /// Camera scroll fraction for the near parallax layer.
  static const double nearParallax = 0.6;

  /// Fixed particle pool size. Tuned to read as a populated background
  /// without becoming a fillrate problem on lower-end devices.
  static const int _particleCount = 36;

  final ZoneManager zoneManager;
  final CameraSystem cameraSystem;

  /// Phase 14: optional perf monitor. When wired:
  ///   * `monitor.maxParticles` caps how many ambient particles step
  ///     and render each frame (cheaper fillrate on low tier),
  ///   * `monitor.backgroundLayers` decides whether to render the far
  ///     parallax layer (drops out at the lowest tier).
  PerformanceMonitor? performanceMonitor;

  final math.Random _rng = math.Random(42);
  final List<_Particle> _particles =
      List.generate(_particleCount, (_) => _Particle());

  // Ambient phase counter — feeds neon pulse, water waving, ember flicker.
  double _t = 0;

  // The most recently observed zone type. We re-seed the particle pool
  // on every zone change so the visual immediately matches the new zone
  // instead of waiting for the old particles to drift off-screen.
  ZoneType? _lastSeededZone;

  ZoneBackground({
    required this.zoneManager,
    required this.cameraSystem,
    this.performanceMonitor,
  }) : super(
          // Sit far behind everything else in the world.
          priority: -1000,
          size: Vector2(FreefallGame.logicalWidth, FreefallGame.logicalHeight),
        );

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _seedParticles(zoneManager.currentZone.type);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;

    // Track the camera so we always paint behind whatever the player is
    // looking at, without needing a viewport-anchored parent.
    final cam = cameraSystem.playerWorldPosition;
    position = Vector2(
      cam.x - FreefallGame.logicalWidth / 2,
      cam.y - FreefallGame.logicalHeight / 2,
    );

    // Re-seed on a fresh zone so the new flavor appears immediately.
    final z = zoneManager.currentZone.type;
    if (z != _lastSeededZone) {
      _seedParticles(z);
    }

    _stepParticles(dt);
  }

  void _seedParticles(ZoneType zone) {
    _lastSeededZone = zone;
    for (final p in _particles) {
      _initParticle(p, zone, randomY: true);
    }
  }

  void _initParticle(_Particle p, ZoneType zone, {required bool randomY}) {
    p.x = _rng.nextDouble() * size.x;
    p.y = randomY
        ? _rng.nextDouble() * size.y
        : (zone == ZoneType.deepOcean || zone == ZoneType.core
            ? size.y + 8 // bubbles & embers spawn just below the bottom
            : -8); // everything else spawns just above the top
    p.phase = _rng.nextDouble() * math.pi * 2;
    p.seed = _rng.nextDouble();

    switch (zone) {
      case ZoneType.stratosphere:
        p.radius = 14 + _rng.nextDouble() * 22;
        p.drift = -10 + _rng.nextDouble() * 20;
        p.rise = -25 - _rng.nextDouble() * 25; // moves down with the wind
        break;
      case ZoneType.city:
        p.radius = 1.5 + _rng.nextDouble() * 2.5;
        p.drift = -4 + _rng.nextDouble() * 8;
        p.rise = -20 - _rng.nextDouble() * 30;
        break;
      case ZoneType.underground:
        p.radius = 1.2 + _rng.nextDouble() * 2.2;
        p.drift = -8 + _rng.nextDouble() * 16;
        p.rise = -15 - _rng.nextDouble() * 25;
        break;
      case ZoneType.deepOcean:
        p.radius = 2 + _rng.nextDouble() * 5;
        p.drift = -6 + _rng.nextDouble() * 12;
        p.rise = 30 + _rng.nextDouble() * 40; // bubbles rise upward
        break;
      case ZoneType.core:
        p.radius = 1.5 + _rng.nextDouble() * 3;
        p.drift = -10 + _rng.nextDouble() * 20;
        p.rise = 50 + _rng.nextDouble() * 60; // embers rise upward fast
        break;
    }
  }

  /// How many ambient particles to step + render this frame. Caps at
  /// the static pool size; reads the perf-monitor cap when wired.
  int get _ambientParticleBudget {
    final cap = performanceMonitor?.maxParticles;
    if (cap == null) return _particleCount;
    return cap < _particleCount ? cap : _particleCount;
  }

  void _stepParticles(double dt) {
    final zone = zoneManager.currentZone.type;
    final budget = _ambientParticleBudget;
    for (int i = 0; i < budget; i++) {
      final p = _particles[i];
      p.x += p.drift * dt;
      // p.rise is the apparent screen-space vertical motion: negative =
      // moves down (clouds, dust), positive = moves up (bubbles, embers).
      // We subtract because screen-space y grows downward but "rise" reads
      // intuitively as upward motion.
      p.y -= p.rise * dt;

      // Wrap horizontally so particles aren't lost off the side.
      if (p.x < -20) p.x += size.x + 40;
      if (p.x > size.x + 20) p.x -= size.x + 40;

      // Recycle any particle that has scrolled off the visible region.
      final offTop = p.y < -p.radius * 2;
      final offBot = p.y > size.y + p.radius * 2;
      if (offTop || offBot) {
        _initParticle(p, zone, randomY: false);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    _renderGradient(canvas);
    // Phase 14: respect the perf-monitor's parallax-layer budget.
    //   2 layers → far + near (default high-tier behavior),
    //   1 layer  → near only,
    //   0 layers → gradient + ambient particles only.
    final layers = performanceMonitor?.backgroundLayers ?? 2;
    if (layers >= 2) _renderFarLayer(canvas);
    if (layers >= 1) _renderNearLayer(canvas);
    _renderParticles(canvas);
  }

  // ---- gradient ---------------------------------------------------------

  void _renderGradient(Canvas canvas) {
    final g = zoneManager.backgroundGradient(zoneManager.currentDepthMeters);
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [g.top, g.bottom],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  // ---- parallax layers --------------------------------------------------

  /// Camera scroll position in pixels — used to drive parallax.
  double get _scrollPx => cameraSystem.scrolledPixels;

  void _renderFarLayer(Canvas canvas) {
    // Far layer slides up at 0.3x the camera scroll rate — same direction
    // as the world (negative localY as the camera falls), but scaled down
    // to read as distant.
    final offset = -_scrollPx * farParallax;
    switch (zoneManager.currentZone.type) {
      case ZoneType.stratosphere:
        _drawDistantClouds(canvas, offset, alpha: 0.18);
        break;
      case ZoneType.city:
        _drawSkyline(canvas, offset, height: 80, alpha: 0.55);
        break;
      case ZoneType.underground:
        _drawCaveWalls(canvas, offset, inset: 14, alpha: 0.35);
        break;
      case ZoneType.deepOcean:
        _drawOceanBands(canvas, offset, alpha: 0.2);
        break;
      case ZoneType.core:
        _drawMagmaGlow(canvas, offset, alpha: 0.25);
        break;
    }
  }

  void _renderNearLayer(Canvas canvas) {
    // Near layer moves at 0.6x camera scroll — twice as fast as the far
    // layer, but still slower than world objects, so it reads as foreground
    // ambience without competing with gameplay obstacles for attention.
    final offset = -_scrollPx * nearParallax;
    switch (zoneManager.currentZone.type) {
      case ZoneType.stratosphere:
        _drawDistantClouds(canvas, offset, alpha: 0.32, scale: 1.4);
        break;
      case ZoneType.city:
        _drawSkyline(canvas, offset, height: 130, alpha: 0.85);
        break;
      case ZoneType.underground:
        _drawStalactites(canvas, offset, alpha: 0.7);
        break;
      case ZoneType.deepOcean:
        _drawOceanBands(canvas, offset, alpha: 0.35, dense: true);
        break;
      case ZoneType.core:
        _drawMagmaGlow(canvas, offset, alpha: 0.45, scale: 1.4);
        break;
    }
  }

  // Helper: tile a vertical pattern by a given period. The drawer is
  // called once per tile, with a baseline y in component-local coords.
  void _tileVertical(
    Canvas canvas,
    double offset,
    double period,
    void Function(double y) drawer,
  ) {
    // Bring [offset] back into [0, period) so we never draw infinitely.
    var top = offset % period;
    if (top > 0) top -= period;
    for (double y = top; y < size.y + period; y += period) {
      drawer(y);
    }
  }

  void _drawDistantClouds(
    Canvas canvas,
    double offset, {
    required double alpha,
    double scale = 1.0,
  }) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    _tileVertical(canvas, offset, 220, (y) {
      for (int i = 0; i < 3; i++) {
        final cx = (i * 150 + 60.0) % size.x;
        final cy = y + (i.isEven ? 30 : 90);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: 110 * scale,
            height: 28 * scale,
          ),
          paint,
        );
      }
    });
  }

  void _drawSkyline(
    Canvas canvas,
    double offset, {
    required double height,
    required double alpha,
  }) {
    final paint = Paint()..color = Colors.black.withValues(alpha: alpha);
    final accent = zoneManager.currentZone.accentColor;
    final lit = Paint()..color = accent.withValues(alpha: alpha * 0.4);
    _tileVertical(canvas, offset, size.y + height + 4, (y) {
      // One band of skyline per tile, at the bottom of the band.
      final baseY = y + size.y - height;
      double x = 0;
      var i = 0;
      while (x < size.x) {
        final w = 22 + (i * 13 % 28).toDouble();
        final h = 24 + (i * 19 % (height - 20)).toDouble();
        canvas.drawRect(Rect.fromLTWH(x, baseY + (height - h), w, h), paint);
        // Sprinkle lit windows.
        if (i.isOdd) {
          canvas.drawRect(
            Rect.fromLTWH(x + 3, baseY + (height - h) + 6, w - 6, 3),
            lit,
          );
        }
        x += w + 2;
        i++;
      }
    });
  }

  void _drawCaveWalls(
    Canvas canvas,
    double offset, {
    required double inset,
    required double alpha,
  }) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    _tileVertical(canvas, offset, 90, (y) {
      // Wavy left/right wall blocks.
      final l = Path()
        ..moveTo(0, y)
        ..lineTo(inset + 6, y + 18)
        ..lineTo(inset, y + 45)
        ..lineTo(inset + 8, y + 90)
        ..lineTo(0, y + 90)
        ..close();
      final r = Path()
        ..moveTo(size.x, y)
        ..lineTo(size.x - inset - 6, y + 18)
        ..lineTo(size.x - inset, y + 45)
        ..lineTo(size.x - inset - 8, y + 90)
        ..lineTo(size.x, y + 90)
        ..close();
      canvas.drawPath(l, paint);
      canvas.drawPath(r, paint);
    });
  }

  void _drawStalactites(
    Canvas canvas,
    double offset, {
    required double alpha,
  }) {
    final paint = Paint()..color = const Color(0xFF2A1500).withValues(alpha: alpha);
    _tileVertical(canvas, offset, 200, (y) {
      for (int i = 0; i < 6; i++) {
        final cx = (i * 70 + 30.0) % size.x;
        final h = 24 + (i * 13 % 28).toDouble();
        final p = Path()
          ..moveTo(cx - 14, y)
          ..lineTo(cx + 14, y)
          ..lineTo(cx, y + h)
          ..close();
        canvas.drawPath(p, paint);
      }
    });
  }

  void _drawOceanBands(
    Canvas canvas,
    double offset, {
    required double alpha,
    bool dense = false,
  }) {
    final period = dense ? 60.0 : 120.0;
    final paint = Paint()..color = Colors.black.withValues(alpha: alpha);
    _tileVertical(canvas, offset, period, (y) {
      // Subtle horizontal "wave" via a stretched ellipse.
      final wobble = math.sin(_t * 0.6 + y * 0.02) * 6;
      canvas.drawOval(
        Rect.fromLTWH(-30 + wobble, y, size.x + 60, period * 0.4),
        paint,
      );
    });
  }

  void _drawMagmaGlow(
    Canvas canvas,
    double offset, {
    required double alpha,
    double scale = 1.0,
  }) {
    _tileVertical(canvas, offset, 240, (y) {
      for (int i = 0; i < 4; i++) {
        final cx = (i * 110 + 60.0) % size.x;
        final cy = y + (i.isEven ? 60 : 160);
        final r = (40 + (i * 19 % 30).toDouble()) * scale;
        final paint = Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFA040).withValues(alpha: alpha),
              const Color(0xFFFF4500).withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
        canvas.drawCircle(Offset(cx, cy), r, paint);
      }
    });
  }

  // ---- particles --------------------------------------------------------

  void _renderParticles(Canvas canvas) {
    final zone = zoneManager.currentZone.type;
    final accent = zoneManager.currentZone.accentColor;
    final budget = _ambientParticleBudget;
    for (int i = 0; i < budget; i++) {
      final p = _particles[i];
      switch (zone) {
        case ZoneType.stratosphere:
          _renderCloudParticle(canvas, p);
          break;
        case ZoneType.city:
          _renderNeonParticle(canvas, p, accent);
          break;
        case ZoneType.underground:
          _renderDustParticle(canvas, p);
          break;
        case ZoneType.deepOcean:
          _renderBubbleParticle(canvas, p);
          break;
        case ZoneType.core:
          _renderEmberParticle(canvas, p);
          break;
      }
    }
  }

  void _renderCloudParticle(Canvas canvas, _Particle p) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(p.x, p.y),
        width: p.radius * 2.6,
        height: p.radius * 0.9,
      ),
      paint,
    );
  }

  void _renderNeonParticle(Canvas canvas, _Particle p, Color accent) {
    // Pulse uses the per-particle phase so neon dots flicker out of sync.
    final pulse = 0.5 + 0.5 * math.sin(_t * 4 + p.phase);
    final color = HSVColor.fromAHSV(
      0.55 + 0.4 * pulse,
      (p.seed * 360),
      0.9,
      1.0,
    ).toColor();
    canvas.drawCircle(
      Offset(p.x, p.y),
      p.radius * (0.8 + 0.5 * pulse),
      Paint()..color = color,
    );
    // Subtle accent ring so the dots feel zone-tinted.
    canvas.drawCircle(
      Offset(p.x, p.y),
      p.radius * 1.8,
      Paint()
        ..color = accent.withValues(alpha: 0.12 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  void _renderDustParticle(Canvas canvas, _Particle p) {
    canvas.drawCircle(
      Offset(p.x, p.y),
      p.radius,
      Paint()..color = const Color(0xFFFFC97A).withValues(alpha: 0.45),
    );
  }

  void _renderBubbleParticle(Canvas canvas, _Particle p) {
    // Wobble bubbles sideways for that "rising water" vibe.
    final wobble = math.sin(_t * 2 + p.phase) * 1.5;
    final cx = p.x + wobble;
    canvas.drawCircle(
      Offset(cx, p.y),
      p.radius,
      Paint()
        ..color = const Color(0xFF80E5FF).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(cx, p.y),
      p.radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    // Highlight dot for sphere read.
    canvas.drawCircle(
      Offset(cx - p.radius * 0.4, p.y - p.radius * 0.4),
      p.radius * 0.25,
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );
  }

  void _renderEmberParticle(Canvas canvas, _Particle p) {
    final flicker = 0.6 + 0.4 * math.sin(_t * 6 + p.phase);
    final hot = Color.lerp(
      const Color(0xFFFF7800),
      const Color(0xFFFFE066),
      flicker,
    )!;
    canvas.drawCircle(
      Offset(p.x, p.y),
      p.radius * (0.8 + 0.4 * flicker),
      Paint()
        ..color = hot.withValues(alpha: 0.85 * flicker)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }
}
