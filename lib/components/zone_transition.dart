// components/zone_transition.dart
//
// Screen-space overlay that flashes the active zone's name when the
// player crosses into a new zone. Wired by FreefallGame: ZoneManager's
// onZoneEnter callback pokes [show], which kicks off a 2-second
// fade-out animation.
//
// Lives in the camera viewport (not the world) so it stays anchored to
// the screen regardless of the player's world position. Drawn at high
// priority so nothing in the world or HUD covers it during the flash.

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/freefall_game.dart';
import '../models/zone.dart';

class ZoneTransition extends PositionComponent {
  /// Total visible duration of the flash, including the fade. Tuned
  /// long enough to read but short enough to clear before the next
  /// gameplay beat (typical zone span is ~6 seconds at terminal
  /// velocity).
  static const double flashDuration = 2.0;

  /// Map of zone-type → resolved label + accent color. Cached at
  /// construction time so we don't re-walk the [Zone.defaultCycle]
  /// list every frame.
  late final Map<ZoneType, Zone> _byType;

  String _label = '';
  Color _accent = Colors.white;
  double _timer = 0;

  ZoneTransition({Iterable<Zone>? zones})
      : super(
          // Above the world; below any debug HUD.
          priority: 1000,
          size: Vector2(FreefallGame.logicalWidth, FreefallGame.logicalHeight),
        ) {
    final list = zones ?? Zone.defaultCycle;
    _byType = {for (final z in list) z.type: z};
  }

  /// True iff the flash is currently visible. Useful for tests that want
  /// to assert the overlay reacted to a zone change.
  bool get isFlashing => _timer > 0;

  /// Currently-displayed zone label (uppercase). Empty when not flashing.
  String get label => _label;

  /// Trigger the flash for [zone]. Re-triggering interrupts and resets
  /// the fade — handy if zones change rapidly during cycle wraps.
  void show(ZoneType zone) {
    final z = _byType[zone];
    if (z == null) return;
    _label = z.name.toUpperCase();
    _accent = z.accentColor;
    _timer = flashDuration;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_timer > 0) {
      _timer = (_timer - dt).clamp(0.0, flashDuration);
    }
  }

  @override
  void render(Canvas canvas) {
    if (_timer <= 0 || _label.isEmpty) return;

    // Curve: punch in fast (last 20% of timer = ramp up), hold, then
    // fade out. Reading [_timer] backwards: t == 1 at trigger, 0 at end.
    final t = _timer / flashDuration;
    final alpha = _flashCurve(t);
    if (alpha <= 0) return;

    final centerX = size.x / 2;
    final centerY = size.y / 2;

    // Glow layer — accent color, blurred wide so the title reads as a
    // burst of zone-flavored light.
    final glow = TextPainter(
      text: TextSpan(
        text: _label,
        style: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
          color: _accent.withValues(alpha: alpha * 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    // Soft halo — draw the same string several times with a blur filter
    // for a cheap glow without offscreen passes.
    final glowPaint = Paint()
      ..color = _accent.withValues(alpha: alpha * 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(
      Offset(centerX, centerY),
      glow.width * 0.6,
      glowPaint,
    );

    // White headline text — drawn last so it sits crisp on top of the
    // glow. Fades in / out together with [alpha].
    final main = TextPainter(
      text: TextSpan(
        text: _label,
        style: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
          color: Colors.white.withValues(alpha: alpha),
          shadows: [
            Shadow(
              color: _accent.withValues(alpha: alpha * 0.9),
              blurRadius: 18,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    main.paint(
      canvas,
      Offset(centerX - main.width / 2, centerY - main.height / 2),
    );
  }

  /// Maps [t] (1 → 0 over the flash window) to a 0..1 alpha. The first
  /// 20% of the window is a snap-in pop; the last 80% is a smooth fade
  /// to nothing. Keeps the trigger feeling sharp without hard cutoffs.
  double _flashCurve(double t) {
    if (t >= 0.8) {
      // Ramp 0→1 quickly during initial 20%.
      return ((1 - t) / 0.2).clamp(0.0, 1.0);
    }
    // Long ease-out: alpha == t / 0.8 with a curve.
    final f = (t / 0.8).clamp(0.0, 1.0);
    return f * f;
  }
}
