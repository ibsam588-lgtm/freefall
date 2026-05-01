// components/combo_display.dart
//
// Centered "COMBO x3!" overlay that wakes up when the score manager
// reports a combo and goes quiet when the combo expires.
//
// Behavior:
//   * On combo increment: snaps to full alpha, kicks a brief scale
//     pulse, and updates the displayed multiplier.
//   * On combo reset: fades out over [fadeDuration], staying readable
//     just long enough to register the loss.
//
// Color is driven by the score multiplier, not the raw combo count:
//   * 1x → white       (no combo / fresh)
//   * 2-3x → yellow    (combo 2-4)
//   * 4-6x → orange    (combo 5-9)
//   * 8x  → red        (combo 10-14)
//   * 10x → cycling rainbow (combo 15+)
//
// The component lives in the camera viewport so it stays anchored to
// the screen as the player descends.

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/freefall_game.dart';
import '../systems/score_manager.dart';

class ComboDisplay extends PositionComponent {
  /// How long the pulse animation runs after each increment.
  static const double pulseDuration = 0.25;

  /// How long the display fades after a combo reset.
  static const double fadeDuration = 0.8;

  /// Minimum combo count before the display becomes visible. Below this,
  /// the screen stays clean.
  static const int minVisibleCombo = 2;

  /// Currently-displayed combo count. 0 means "hidden".
  int _combo = 0;

  /// 0..1 alpha, driven by reset fade.
  double _alpha = 0;

  /// 0..pulseDuration. While >0, scale spikes.
  double _pulseRemaining = 0;

  /// Continuously-running phase used for the rainbow color at max combo.
  double _rainbowPhase = 0;

  ComboDisplay()
      : super(
          priority: 950, // below ZoneTransition (1000) + HUD (999) is fine here too.
          size: Vector2(FreefallGame.logicalWidth, FreefallGame.logicalHeight),
        );

  /// Read-only state for tests.
  int get combo => _combo;
  double get alpha => _alpha;
  bool get isVisible => _alpha > 0 && _combo >= minVisibleCombo;

  /// Color the display text uses based on the score multiplier of the
  /// active combo. White when there's no real combo yet.
  Color get currentColor {
    final mult = ScoreManager.scoreMultiplierForCombo(_combo);
    if (mult >= 10) {
      // Rainbow: HSV cycle on the rainbow phase.
      final h = (_rainbowPhase * 360) % 360;
      return HSVColor.fromAHSV(1, h, 1, 1).toColor();
    }
    if (mult >= 8) return const Color(0xFFFF1744); // red
    if (mult >= 4) return const Color(0xFFFF9100); // orange
    if (mult >= 2) return const Color(0xFFFFD600); // yellow
    return const Color(0xFFFFFFFF);
  }

  /// Hook for ScoreManager.onComboChanged.
  void onComboIncrement(int newCombo) {
    _combo = newCombo;
    _alpha = 1.0;
    _pulseRemaining = pulseDuration;
  }

  /// Hook for ScoreManager.onComboReset.
  void onComboReset() {
    if (_alpha == 0) {
      _combo = 0;
      return;
    }
    // Don't wipe _combo immediately — the fade-out should still show
    // the last value as it dims.
  }

  @override
  void update(double dt) {
    super.update(dt);
    _rainbowPhase = (_rainbowPhase + dt * 0.5) % 1.0;
    if (_pulseRemaining > 0) {
      _pulseRemaining = math.max(0, _pulseRemaining - dt);
    }
    // Fade only when there is a combo present and no recent increment.
    // The host calls [onComboReset] explicitly when the combo collapses;
    // we fade alpha down from there until it's gone.
    if (_combo == 0 && _alpha > 0) {
      _alpha = math.max(0, _alpha - dt / fadeDuration);
      if (_alpha == 0) {
        _combo = 0;
      }
    }
  }

  /// External trigger from ScoreManager to start the fade. Kept
  /// separate from [onComboReset] so tests can call directly.
  void startFade() {
    if (_combo == 0) {
      _alpha = 0;
      return;
    }
    // Schedule a fade — combo hits 0 here, alpha drains via update.
    _combo = 0;
  }

  @override
  void render(Canvas canvas) {
    if (!isVisible) return;

    final cx = size.x / 2;
    final cy = size.y * 0.32; // upper third — sits above the player.

    // Pulse: scale 1.0 → 1.4 → 1.0 over pulseDuration. Eased so the
    // peak is at ~30% into the pulse window.
    double scale = 1.0;
    if (_pulseRemaining > 0) {
      final t = 1 - (_pulseRemaining / pulseDuration);
      scale = 1.0 + 0.4 * math.sin(t * math.pi);
    }

    final mult = ScoreManager.scoreMultiplierForCombo(_combo);
    final label = 'COMBO x$mult!';
    final color = currentColor.withValues(alpha: _alpha);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 36 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          shadows: [
            Shadow(
              color: color.withValues(alpha: _alpha * 0.6),
              blurRadius: 18,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }
}
