// components/hud.dart
//
// Heads-up display overlay for the running game. Lives in the camera
// viewport (not the world) so it stays anchored to the screen as the
// player descends. Reads from session-scoped state every frame and
// paints all the live counters:
//   * top-left:    depth "1234m" + downward arrow
//   * top-center:  coin counter + small coin icon
//   * top-right:   zone name + 0..1 progress bar
//   * bottom-left: lives as filled/empty dots
//   * bottom-center: score
//   * mid-right:   active powerup pill strip (icon + countdown bar)
//
// All values are sourced through opt-in getter callbacks so the HUD
// stays decoupled from the systems it visualizes — tests can stub it
// without booting Flame.

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/freefall_game.dart';
import '../models/collectible.dart';
import '../systems/collectible_manager.dart';
import '../systems/powerup_manager.dart';
import 'collectibles/powerup_item.dart';

/// Minimal read interface the HUD needs from a Player (or test stub),
/// avoiding a hard dependency on the player component shape.
abstract class HudPlayerSnapshot {
  int get lives;
  int get maxLives;
}

class GameHud extends PositionComponent {
  /// Layout constants. All in screen-space px.
  static const double padding = 16;
  static const double powerupIconSize = 28;
  static const double powerupBarHeight = 4;
  static const double powerupSpacing = 8;
  static const double lifeDotRadius = 6;
  static const double lifeDotSpacing = 16;
  static const double zoneBarWidth = 90;
  static const double zoneBarHeight = 5;

  final PowerupManager powerupManager;
  final CollectibleManager collectibleManager;

  /// Source of current player lives. Late-set by the host because the
  /// player is constructed after the HUD on most boot paths.
  HudPlayerSnapshot? player;

  /// Session coin count — bumped by the host whenever a coin is
  /// collected. Decoupled from CoinRepository so the HUD updates
  /// instantly without waiting on async storage.
  int sessionCoins = 0;

  /// Live readers — set by the host after construction. Each returns
  /// the freshest value for its widget; the HUD never caches them.
  int Function()? scoreGetter;
  double Function()? depthMetersGetter;
  String Function()? zoneNameGetter;
  double Function()? zoneProgressGetter;

  GameHud({
    required this.powerupManager,
    required this.collectibleManager,
    this.player,
  }) : super(
          priority: 999, // below ZoneTransition (1000), above world.
          size: Vector2(FreefallGame.logicalWidth, FreefallGame.logicalHeight),
        );

  @override
  void render(Canvas canvas) {
    _renderDepth(canvas);
    _renderCoinCounter(canvas);
    _renderZone(canvas);
    _renderLives(canvas);
    _renderScore(canvas);
    _renderPowerups(canvas);
  }

  // ---- top row ------------------------------------------------------------

  void _renderDepth(Canvas canvas) {
    final getter = depthMetersGetter;
    if (getter == null) return;
    final depth = getter();
    final tp = TextPainter(
      text: TextSpan(
        text: '${depth.toStringAsFixed(0)}m',
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          shadows: [Shadow(color: Color(0xCC000000), blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const left = padding;
    const top = padding;

    // Downward chevron — drawn as a small triangle so it reads at
    // tiny sizes without leaning on icon fonts.
    const cx = left + 8;
    const cy = top + 9;
    final path = Path()
      ..moveTo(cx - 5, cy - 3)
      ..lineTo(cx + 5, cy - 3)
      ..lineTo(cx, cy + 5)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFD700));

    tp.paint(canvas, const Offset(left + 18, top - 2));
  }

  void _renderCoinCounter(Canvas canvas) {
    final cx = size.x / 2;
    const cy = padding + 12;

    final iconC = Offset(cx - 28, cy);
    canvas.drawCircle(
      iconC,
      8,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
          stops: [0.2, 1.0],
        ).createShader(Rect.fromCircle(center: iconC, radius: 8)),
    );

    final tp = TextPainter(
      text: TextSpan(
        text: '$sessionCoins',
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 22,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Color(0xCC000000), blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - 14, cy - tp.height / 2));
  }

  void _renderZone(Canvas canvas) {
    final nameGetter = zoneNameGetter;
    if (nameGetter == null) return;
    final name = nameGetter();
    final progress = zoneProgressGetter?.call() ?? 0.0;

    final right = size.x - padding;
    const top = padding;

    final tp = TextPainter(
      text: TextSpan(
        text: name.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 12,
          letterSpacing: 2.5,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Color(0xCC000000), blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final textOrigin = Offset(right - tp.width, top);
    tp.paint(canvas, textOrigin);

    // Progress bar — sits directly under the label so it reads as a
    // single unit. Width matches the wider of (label, zoneBarWidth).
    final barLeft = right - math.max(zoneBarWidth, tp.width);
    final barTop = textOrigin.dy + tp.height + 4;
    final barW = math.max(zoneBarWidth, tp.width);
    final pct = progress.clamp(0.0, 1.0);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barLeft, barTop, barW, zoneBarHeight),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0x44000000),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barLeft, barTop, barW * pct, zoneBarHeight),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF40E0D0),
    );
  }

  // ---- bottom row ---------------------------------------------------------

  void _renderLives(Canvas canvas) {
    final p = player;
    if (p == null) return;
    final cy = size.y - padding - lifeDotRadius;
    const left = padding + lifeDotRadius;
    for (int i = 0; i < p.maxLives; i++) {
      final c = Offset(left + i * lifeDotSpacing, cy);
      final filled = i < p.lives;
      canvas.drawCircle(
        c,
        lifeDotRadius,
        Paint()
          ..color = filled
              ? const Color(0xFFFF1744)
              : const Color(0x55FF1744)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        c,
        lifeDotRadius,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  void _renderScore(Canvas canvas) {
    final getter = scoreGetter;
    if (getter == null) return;
    final cx = size.x / 2;
    final cy = size.y - padding - 12;
    final tp = TextPainter(
      text: TextSpan(
        text: '${getter()}',
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          shadows: [Shadow(color: Color(0xCC000000), blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  // ---- powerup strip ------------------------------------------------------

  void _renderPowerups(Canvas canvas) {
    final effects = powerupManager.activeEffects.toList(growable: false);
    if (effects.isEmpty) return;

    final right = size.x - padding;
    // Sit just under the zone progress bar so the top row stays clean.
    const top = padding + 30 + zoneBarHeight + 8;
    for (int i = 0; i < effects.length; i++) {
      final eff = effects[i];
      final x = right -
          (effects.length - i) * (powerupIconSize + powerupSpacing) +
          powerupIconSize / 2;
      final iconCenter = Offset(x, top + powerupIconSize / 2);
      _drawPowerupBadge(canvas, iconCenter, eff.type);

      // Countdown bar — hidden for shield (infinite). Width fills 100%
      // when full, drains as the powerup expires.
      final dur = PowerupDuration.forType(eff.type);
      if (dur.isFinite && dur > 0) {
        final t = (eff.remainingSeconds / dur).clamp(0.0, 1.0);
        final barW = powerupIconSize * t;
        final barRect = Rect.fromLTWH(
          iconCenter.dx - powerupIconSize / 2,
          iconCenter.dy + powerupIconSize / 2 + 2,
          barW,
          powerupBarHeight,
        );
        canvas.drawRect(
          barRect,
          Paint()..color = PowerupItem.accentFor(eff.type),
        );
      }
    }
  }

  void _drawPowerupBadge(Canvas canvas, Offset c, PowerupType type) {
    final accent = PowerupItem.accentFor(type);
    canvas.drawCircle(
      c,
      powerupIconSize / 2,
      Paint()..color = const Color(0xCC101018),
    );
    canvas.drawCircle(
      c,
      powerupIconSize / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );
    final glyph = switch (type) {
      PowerupType.shield => 'S',
      PowerupType.magnet => 'M',
      PowerupType.slowMo => 'T',
      PowerupType.scoreMultiplier => '×',
      PowerupType.coinMultiplier => '\$',
      PowerupType.extraLife => '+',
    };
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          color: accent,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
  }
}

/// Adapter wrapping any object exposing `lives`/`maxLives` so the HUD
/// doesn't need to import the Player concrete type.
class HudPlayerAdapter implements HudPlayerSnapshot {
  final int Function() livesGetter;
  final int Function() maxLivesGetter;
  HudPlayerAdapter(this.livesGetter, this.maxLivesGetter);

  @override
  int get lives => livesGetter();

  @override
  int get maxLives => maxLivesGetter();
}
