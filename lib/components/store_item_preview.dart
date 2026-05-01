// components/store_item_preview.dart
//
// Two pieces in one file:
//
//  * [StoreItemArtwork] — a small CustomPaint widget that draws a
//    representative visual for any store item (skin orb, trail
//    streak, shield ring, death-effect particle ring, upgrade icon).
//    Used in store cards AND in the full-screen preview.
//
//  * [StoreItemPreview] — the dark-overlay full-screen confirm
//    screen. Shows a big artwork, name, description, cost, and a
//    Buy/Cancel pair of buttons.
//
// Keeping both here means the store screen file stays focused on
// layout instead of paint code.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/death_effect.dart';
import '../models/player_skin.dart';
import '../models/powerup_upgrade.dart';
import '../models/shield_skin.dart';
import '../models/trail_effect.dart';
import '../store/store_inventory.dart';

/// Tiny card-sized animated preview. Plays a short looping motion (orb
/// pulse, shield bubble breath, gem rotation) so the store doesn't
/// feel like a static price list.
class StoreItemArtwork extends StatefulWidget {
  final StoreItem item;
  final double size;

  const StoreItemArtwork({
    super.key,
    required this.item,
    this.size = 64,
  });

  @override
  State<StoreItemArtwork> createState() => _StoreItemArtworkState();
}

class _StoreItemArtworkState extends State<StoreItemArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => CustomPaint(
          painter: _StoreItemPainter(
            item: widget.item,
            phase: _controller.value,
          ),
        ),
      ),
    );
  }
}

/// Paint dispatcher. Reads the item ID prefix to pick a routine —
/// keeps the StatefulWidget lean and lets each visual stay self-
/// contained.
class _StoreItemPainter extends CustomPainter {
  final StoreItem item;
  final double phase;

  _StoreItemPainter({required this.item, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final r = math.min(size.width, size.height) * 0.4;

    final skinId = StoreInventory.parseSkinId(item.id);
    if (skinId != null) {
      _paintSkin(canvas, center, r, PlayerSkin.byId(skinId));
      return;
    }
    final trailId = StoreInventory.parseTrailId(item.id);
    if (trailId != null) {
      _paintTrail(canvas, center, r, TrailEffect.byId(trailId));
      return;
    }
    final shieldId = StoreInventory.parseShieldId(item.id);
    if (shieldId != null) {
      _paintShield(canvas, center, r, ShieldSkin.byId(shieldId));
      return;
    }
    final deathId = StoreInventory.parseDeathId(item.id);
    if (deathId != null) {
      _paintDeath(canvas, center, r, DeathEffect.byId(deathId));
      return;
    }
    final upgradeId = StoreInventory.parseUpgradeId(item.id);
    if (upgradeId != null) {
      _paintUpgrade(canvas, center, r, PowerupUpgrade.byId(upgradeId));
      return;
    }
  }

  void _paintSkin(Canvas canvas, Offset c, double r, PlayerSkin s) {
    final pulse = 0.92 + 0.08 * math.sin(phase * math.pi * 2);
    final actual = r * pulse;
    // Halo.
    canvas.drawCircle(
      c,
      actual * 1.7,
      Paint()
        ..shader = RadialGradient(
          colors: [
            s.glowColor.withValues(alpha: 0.6),
            s.glowColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: actual * 1.7)),
    );
    // Body.
    canvas.drawCircle(
      c,
      actual,
      Paint()
        ..shader = RadialGradient(
          colors: [s.primaryColor, s.glowColor],
          stops: const [0.15, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: actual)),
    );
    // Specular dot — keeps the orb reading as round.
    canvas.drawCircle(
      Offset(c.dx - actual * 0.35, c.dy - actual * 0.35),
      actual * 0.22,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.7),
    );
  }

  void _paintTrail(Canvas canvas, Offset c, double r, TrailEffect t) {
    // Render as a few falling dots forming the trail's shape, sized by
    // sampleCount so longer-tail trails read as denser.
    final steps = (t.sampleCount / 2).clamp(6, 14).toInt();
    final color = _trailColorFor(t);
    // Trail moves down across the artwork; phase shifts the head
    // position so it looks like the player is falling continuously.
    final headOffset = phase * r * 0.5;
    for (int i = 0; i < steps; i++) {
      final f = i / steps;
      final dy = c.dy - r + i * (r * 1.6 / steps) + headOffset;
      // Wrap so dots stay within the artwork bounds.
      final wrappedY = ((dy - (c.dy - r)) % (r * 1.6)) + (c.dy - r);
      final dotR = (r * 0.18) * (1.0 - f * 0.7);
      final alpha = t.headAlpha * (1.0 - f);
      final wobble = t.animated
          ? math.sin((phase + i * 0.15) * math.pi * 2) * r * 0.15
          : 0.0;
      canvas.drawCircle(
        Offset(c.dx + wobble, wrappedY),
        dotR,
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  /// Per-trail accent color (TrailEffect doesn't carry one — Player
  /// uses skin.trailColor at runtime). For the store preview we pick a
  /// signature hue so the trails are visually distinct.
  Color _trailColorFor(TrailEffect t) {
    return switch (t.id) {
      TrailId.default_ => const Color(0xFFFFFFFF),
      TrailId.comet => const Color(0xFFFF8A00),
      TrailId.helix => const Color(0xFF00E5FF),
      TrailId.sparkle => const Color(0xFFFFD600),
      TrailId.glitch => const Color(0xFFFF00E5),
      TrailId.ghost => const Color(0xFFB0BEC5),
      TrailId.warp => const Color(0xFF7C4DFF),
    };
  }

  void _paintShield(Canvas canvas, Offset c, double r, ShieldSkin s) {
    final pulse = 0.85 + 0.15 * math.sin(phase * math.pi * 2);
    final shieldR = r * pulse;
    canvas.drawCircle(
      c,
      shieldR,
      Paint()..color = s.primaryColor.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      c,
      shieldR,
      Paint()
        ..color = s.accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // Inner core dot to suggest a player inside the bubble.
    canvas.drawCircle(c, r * 0.25, Paint()..color = const Color(0xFFFFFFFF));
  }

  void _paintDeath(Canvas canvas, Offset c, double r, DeathEffect e) {
    // Particles burst outward and fade. Phase 0..1 maps to one burst.
    final burst = (phase * 1.4) % 1.0; // re-trigger frequently
    const dots = 18;
    for (int i = 0; i < dots; i++) {
      final angle = (i / dots) * math.pi * 2;
      final dist = r * burst;
      final dotR = r * 0.12 * (1.0 - burst);
      final color = e.id == DeathEffectId.confetti
          ? HSVColor.fromAHSV(1, (i * 360 / dots) % 360, 1, 1).toColor()
          : e.tint;
      canvas.drawCircle(
        Offset(c.dx + math.cos(angle) * dist, c.dy + math.sin(angle) * dist),
        dotR.clamp(0.5, r),
        Paint()..color = color.withValues(alpha: (1.0 - burst).clamp(0, 1)),
      );
    }
  }

  void _paintUpgrade(Canvas canvas, Offset c, double r, PowerupUpgrade u) {
    final pulse = 0.85 + 0.15 * math.sin(phase * math.pi * 2);
    final accent = _upgradeAccentFor(u.id);
    canvas.drawCircle(
      c,
      r * pulse,
      Paint()
        ..shader = RadialGradient(
          colors: [accent.withValues(alpha: 0.55), accent.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r * pulse)),
    );
    canvas.drawCircle(
      c,
      r * 0.55,
      Paint()..color = const Color(0xFF101018).withValues(alpha: 0.75),
    );
    canvas.drawCircle(
      c,
      r * 0.55,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // A short letter glyph hints at the upgrade's category.
    final glyph = _upgradeGlyphFor(u.id);
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          color: accent,
          fontSize: r * 0.7,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
  }

  Color _upgradeAccentFor(PowerupUpgradeId id) => switch (id) {
        PowerupUpgradeId.magnetRange => const Color(0xFFFF5252),
        PowerupUpgradeId.shieldDuration => const Color(0xFF40C4FF),
        PowerupUpgradeId.slowMoDuration => const Color(0xFFB388FF),
        PowerupUpgradeId.scoreMultiplier => const Color(0xFFFFD740),
        PowerupUpgradeId.coinMultiplier => const Color(0xFFFFB300),
        PowerupUpgradeId.extraStartingLife => const Color(0xFFFF1744),
        PowerupUpgradeId.luckyDrop => const Color(0xFF69F0AE),
      };

  String _upgradeGlyphFor(PowerupUpgradeId id) => switch (id) {
        PowerupUpgradeId.magnetRange => 'M',
        PowerupUpgradeId.shieldDuration => 'S',
        PowerupUpgradeId.slowMoDuration => 'T',
        PowerupUpgradeId.scoreMultiplier => '×',
        PowerupUpgradeId.coinMultiplier => '\$',
        PowerupUpgradeId.extraStartingLife => '+',
        PowerupUpgradeId.luckyDrop => '★',
      };

  @override
  bool shouldRepaint(_StoreItemPainter old) =>
      old.phase != phase || old.item.id != item.id;
}

/// Full-screen confirm overlay. Pushed via Navigator.push when the
/// player taps an unowned item; calls [onConfirm] on Buy press,
/// [onCancel] on Cancel press / barrier dismiss.
class StoreItemPreview extends StatelessWidget {
  final StoreItem item;
  final String description;
  final int displayCost;
  final bool canAfford;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const StoreItemPreview({
    super.key,
    required this.item,
    required this.description,
    required this.displayCost,
    required this.canAfford,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC000010),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.tag.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  StoreItemArtwork(item: item, size: 180),
                  const SizedBox(height: 16),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canAfford ? onConfirm : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: const Color(0xFF101018),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        canAfford
                            ? 'BUY FOR $displayCost COINS'
                            : 'NOT ENOUGH COINS',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onCancel,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
