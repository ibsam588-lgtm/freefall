// components/hazards/lightning_bolt.dart
//
// Stratosphere hazard. A vertical bolt that flashes for 0.3s, sleeps
// for 2s, then flashes again. Only lethal during the active flash —
// most contacts pass through harmless. Instant kill (bypasses lives).
//
// Telegraph timing — designed to be readable, not random:
//   * The standby column is always faintly visible during cooldown so
//     the player can see WHERE the next strike will land.
//   * In the last [warningDuration] seconds before a strike, a glow
//     ramps up from 0 → full so the strike is genuinely predictable.
//     A player who notices the warning has ~1s to move out of the
//     column before the lethal flash.
//   * Bolt position (column) is fixed at spawn time and never changes
//     between cooldown and strike — what you see is where it'll hit.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../obstacles/game_obstacle.dart';

class LightningBolt extends GameObstacle {
  static const double flashDuration = 0.3; // seconds active + lethal
  static const double cooldownDuration = 2.0; // seconds idle (with telegraph)
  static const double boltHeight = 220;
  static const double boltWidth = 36;

  /// How long, immediately before a strike, to show the warning glow.
  /// Tuned so a typical reaction (300–500 ms) leaves the player ~half
  /// a second to physically reposition out of the column.
  static const double warningDuration = 1.0;

  /// Active phase = flashing & lethal. Inactive = invisible & passable.
  bool _active = false;
  double _phaseT = 0;

  /// Wall-clock dt of the most recent update. Lets [intersects] answer
  /// "was this bolt active at ANY moment during the just-finished
  /// frame?" — strikes that lasted 90% of a 33ms frame but flipped off
  /// at the end would otherwise be invisible to the post-physics
  /// collision pass and let the player walk through a flash.
  double _lastDt = 0;

  /// Random initial offset so a row of bolts doesn't strobe in lockstep.
  LightningBolt({
    required super.obstacleId,
    required Vector2 worldPosition,
    double? initialPhase,
    math.Random? rng,
  }) : super(
          position: worldPosition,
          size: Vector2(boltWidth, boltHeight),
        ) {
    _phaseT = initialPhase ??
        (rng ?? math.Random()).nextDouble() *
            (flashDuration + cooldownDuration);
    _active = _phaseT < flashDuration;
  }

  bool get isActive => _active;

  /// 0..1 ramp during the warning window before a strike. 0 outside it,
  /// 1 the instant before the bolt becomes lethal. Tested via
  /// obstacle_spawner_test for predictability.
  double get warningIntensity {
    if (_active) return 0;
    const cycle = flashDuration + cooldownDuration;
    final timeUntilStrike = cycle - _phaseT;
    if (timeUntilStrike >= warningDuration) return 0;
    return ((warningDuration - timeUntilStrike) / warningDuration)
        .clamp(0.0, 1.0);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lastDt = dt;
    _phaseT += dt;
    const cycle = flashDuration + cooldownDuration;
    if (_phaseT >= cycle) _phaseT -= cycle;
    _active = _phaseT < flashDuration;
  }

  /// True iff the active flash window overlapped ANY moment during the
  /// just-finished frame [_phaseT - _lastDt .. _phaseT]. Wraps the cycle
  /// so a window straddling the cooldown→flash boundary still counts.
  bool _wasActiveDuringFrame() {
    if (_active) return true;
    if (_lastDt <= 0) return false;
    const cycle = flashDuration + cooldownDuration;
    var startT = _phaseT - _lastDt;
    if (startT < 0) startT += cycle;
    final endT = _phaseT;
    if (startT <= endT) {
      return startT < flashDuration;
    }
    // Wrapped: frame straddled the cycle reset, so it definitely crossed
    // the [0..flashDuration] active window.
    return true;
  }

  /// Tighter hitbox than the parent AABB — the visible zigzag peaks at
  /// `cx ± size.x*0.35`, so the AABB's full half-width includes ~5px of
  /// invisible-but-lethal space on each side. Use the actual zigzag
  /// envelope plus the player's circumscribed radius for forgiveness.
  @override
  bool intersects(Rect playerRect) {
    if (!_wasActiveDuringFrame()) return false;
    final localCx = playerRect.center.dx - position.x;
    final localCy = playerRect.center.dy - position.y;
    final r = math.min(playerRect.width, playerRect.height) / 2;
    // Reject outside the bolt's vertical span (with circle forgiveness).
    if (localCy < -size.y / 2 - r || localCy > size.y / 2 + r) return false;
    // Horizontal: the zigzag peaks reach 35% of size.x to either side
    // (see _renderActiveBolt). Use that as the lethal half-width.
    final halfW = size.x * 0.35;
    return localCx.abs() <= halfW + r;
  }

  @override
  ObstacleHitEffect onPlayerHit() => ObstacleHitEffect.kill;

  @override
  void render(Canvas canvas) {
    if (!_active) {
      _renderTelegraph(canvas);
      return;
    }
    _renderActiveBolt(canvas);
  }

  /// Inactive-phase rendering: a faint always-on column line, plus a
  /// brightening warning glow during the last [warningDuration] seconds.
  void _renderTelegraph(Canvas canvas) {
    final cx = size.x / 2;

    // Always-on standby line so the column is visible.
    final telegraph = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.y),
      telegraph,
    );

    // Warning glow — escalates to clearly readable in the last second.
    final w = warningIntensity;
    if (w <= 0) return;

    // Pulse for the second half so it reads as urgent rather than static.
    final pulse = w > 0.5
        ? 0.5 + 0.5 * math.sin(_phaseT * 30)
        : 1.0;
    final alpha = (w * 0.7 * pulse).clamp(0.0, 0.9);

    // Bright vertical core line that thickens with intensity.
    final coreWarn = Paint()
      ..color = const Color(0xFFFFEB3B).withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 + 3.5 * w;
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.y),
      coreWarn,
    );

    // A few small chevrons along the column to telegraph the strike path.
    final chevron = Paint()
      ..color = const Color(0xFFFFD600).withValues(alpha: alpha * 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const chevronCount = 5;
    final span = size.y;
    final chevronWidth = 6.0 + 6.0 * w;
    for (int i = 0; i < chevronCount; i++) {
      final cy = (i + 0.5) * span / chevronCount;
      final p = Path()
        ..moveTo(cx - chevronWidth, cy - chevronWidth)
        ..lineTo(cx, cy)
        ..lineTo(cx + chevronWidth, cy - chevronWidth);
      canvas.drawPath(p, chevron);
    }
  }

  void _renderActiveBolt(Canvas canvas) {
    // Active: zig-zag bolt path with hot core + cool halo.
    final core = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final halo = Paint()
      ..color = const Color(0xFFB3E0FF).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;

    final path = Path();
    final cx = size.x / 2;
    const segments = 6;
    final segH = size.y / segments;
    path.moveTo(cx, 0);
    for (int i = 1; i <= segments; i++) {
      final dx = (i.isOdd ? 1 : -1) * size.x * 0.35;
      path.lineTo(cx + dx, i * segH);
    }
    canvas.drawPath(path, halo);
    canvas.drawPath(path, core);
  }
}
