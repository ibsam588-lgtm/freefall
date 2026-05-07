// components/player.dart
//
// The player avatar — a glowing orb that falls under gravity, tilts
// left/right under accelerometer (or touch fallback), wears a chosen
// skin, leaves a trail (rendered by PlayerTrail), and shows a pulsing
// shield bubble during i-frames.
//
// Lives & death/respawn:
//  - Player has [maxLives] (default 3, upgradable to 4 via the store).
//  - [onHit] reduces lives by 1 and grants 2s of invincibility.
//  - When lives hit 0 a death sequence triggers: the orb hides, and if a
//    PlayerParticleSystem is wired up, 60 particles burst outward.
//  - [respawn(position)] reassembles particles inward to [position],
//    restores lives, and re-shows the orb.
//
// Zone color sync:
//  - The host calls [setZoneColor] each tick with the active zone's
//    accent color. The player blends the skin glow toward that accent
//    so the orb visually belongs to whatever zone you're falling
//    through, without losing the skin's identity.

import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/player_skin.dart';
import '../models/trail_effect.dart';
import '../systems/gravity_system.dart';
import 'particle_system.dart';
import 'player_trail.dart';

class Player extends PositionComponent {
  /// Visible orb radius in world pixels.
  static const double radius = 18;

  /// How aggressively device tilt converts to horizontal velocity.
  /// Tuned so a comfortable ~30° tilt produces near-max horizontal speed.
  static const double tiltSensitivity = 420; // px/s per (m/s^2)

  /// Maximum horizontal speed produced by tilt or touch.
  static const double maxHorizontalSpeed = 420;

  /// Default starting and minimum-upgrade life count.
  static const int defaultMaxLives = 3;

  /// Hard ceiling on max lives (store upgrade can push to 4, never higher).
  static const int absoluteMaxLives = 4;

  /// Seconds of invincibility granted per non-lethal hit.
  static const double invincibilityDuration = 2.0;

  /// How many position samples the trail history retains. The trail
  /// renderer can read fewer than this when its effect calls for it.
  static const int trailHistoryLength = 24;

  /// Number of vertical wind streaks drawn above the orb.
  static const int windLineCount = 5;

  /// Zone-color blend strength: 0 = ignore zone, 1 = fully replace skin
  /// glow. 0.55 looks identifiably zone-tinted while keeping the skin's
  /// hue legible.
  static const double zoneTintStrength = 0.55;

  /// Gravity utility — injected so tests can swap it.
  final GravitySystem gravity;

  /// Logical play-field width. X position is clamped to [radius .. playWidth-radius].
  final double playWidth;

  /// Where [respawn] returns the player when called without an explicit
  /// position (also where the orb starts the run).
  final Vector2 startPosition;

  /// Active cosmetic skin. Mutable so the store can change it live.
  PlayerSkin skin;

  /// Active trail effect. Updates [trailRenderer.effect] in [setTrail].
  TrailEffect trail;

  /// Optional external particle system. When wired, death/respawn use
  /// the dedicated 60-particle pool. When null, [Player] falls back to
  /// an internal 30-particle burst (used by unit tests with no Flame
  /// world to host the particle component).
  PlayerParticleSystem? particleSystem;

  /// Fires every time [onHit] actually lands a hit (returns true). The
  /// host wires this to ScoreManager so the combo can collapse on
  /// damage. Not fired for i-framed or already-dead hits.
  void Function()? onHitCallback;

  /// Current world-space velocity. Public so tests can inspect it.
  final Vector2 velocity = Vector2.zero();

  /// Maximum lives. Mutable for store upgrades — clamped at construction
  /// and on assignment to [defaultMaxLives].. [absoluteMaxLives].
  int _maxLives;

  // Last raw accelerometer reading on the X axis (in m/s^2). Cached so
  // render passes can also peek at it for subtle squash effects.
  double _accelX = 0;
  bool _hasAccel = false;

  // Touch-fallback input range: -1 (full left) .. 1 (full right).
  double _touchInput = 0;

  int _lives;
  double _invincibleTimer = 0;
  double _flashPhase = 0; // drives shield pulse + i-frame strobe

  // Recent positions for the motion trail (oldest first). Owned here so
  // the trail renderer doesn't double-buffer.
  final List<Vector2> _trail = [];

  // Active fallback death particles. Only used when no external
  // particleSystem is provided.
  final List<_DeathParticle> _fallbackDeathParticles = [];

  // Current zone accent color blended into the orb's glow. Defaults to
  // white so a Player constructed without setZoneColor still renders.
  Color _zoneAccent = const Color(0xFFFFFFFF);

  // While true the orb itself is not drawn (death animation is showing
  // particles instead). Cleared by [respawn].
  bool _isDeadState = false;

  late PlayerTrail trailRenderer;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  Player({
    required this.gravity,
    required this.startPosition,
    PlayerSkin? skin,
    TrailEffect? trail,
    int maxLives = defaultMaxLives,
    this.particleSystem,
    this.playWidth = 414,
  })  : skin = skin ?? PlayerSkin.defaultSkin,
        trail = trail ?? TrailEffect.defaultTrail,
        _maxLives = maxLives.clamp(1, absoluteMaxLives),
        _lives = maxLives.clamp(1, absoluteMaxLives),
        super(
          position: startPosition.clone(),
          size: Vector2.all(radius * 2),
          anchor: Anchor.center,
          // Render above obstacles (priority 0) so the orb — and its
          // shield/flash i-frame feedback — are visible during contact
          // instead of being painted over by the plank the player just
          // hit. ZoneTransition / HUD sit at >= 999 so this stays
          // safely below the screen-space overlay layers.
          priority: 100,
        );

  // ---- Public state getters ------------------------------------------------

  int get lives => _lives;
  int get maxLives => _maxLives;
  bool get isAlive => _lives > 0 && !_isDeadState;
  bool get isDead => _isDeadState;
  bool get isInvincible => _invincibleTimer > 0;
  bool get hasAccelerometer => _hasAccel;
  Color get zoneAccent => _zoneAccent;
  int get activeFallbackParticleCount => _fallbackDeathParticles.length;

  /// The actual color drawn on the orb body. Skin primary blended
  /// toward the current zone accent so the player reads as part of the
  /// world.
  Color get effectiveGlowColor =>
      Color.lerp(skin.glowColor, _zoneAccent, zoneTintStrength)!;

  // ---- Public mutators -----------------------------------------------------

  /// Update max lives (used by store upgrades). Clamped to the legal
  /// range; if the upgrade increases the cap and the player is at full
  /// life, [_lives] is bumped to match.
  set maxLives(int value) {
    final clamped = value.clamp(1, absoluteMaxLives);
    final wasFull = _lives == _maxLives;
    _maxLives = clamped;
    if (wasFull) _lives = clamped;
    if (_lives > _maxLives) _lives = _maxLives;
  }

  /// Grant +1 life. If already at the max-lives cap, bumps the cap
  /// (capped at [absoluteMaxLives]). Used by the extraLife powerup.
  void gainLife() {
    if (_lives < _maxLives) {
      _lives++;
      return;
    }
    if (_maxLives < absoluteMaxLives) {
      _maxLives++;
      _lives = _maxLives;
    }
  }

  /// Update the active skin and propagate the trail color to the trail
  /// renderer (if mounted).
  void setSkin(PlayerSkin newSkin) {
    skin = newSkin;
    if (isMounted) {
      trailRenderer.color = newSkin.trailColor;
    }
  }

  /// Update the active trail effect.
  void setTrail(TrailEffect newTrail) {
    trail = newTrail;
    if (isMounted) {
      trailRenderer.effect = newTrail;
    }
  }

  /// Push the active zone's accent color into the player. Called by
  /// the host each tick (or whenever a zone transition lands).
  void setZoneColor(Color accent) {
    _zoneAccent = accent;
  }

  /// Touch-zone input: -1 (left), 0 (none), 1 (right). Applied only when
  /// no accelerometer reading is available.
  void setTouchInput(double horizontal) {
    _touchInput = horizontal.clamp(-1.0, 1.0);
  }

  // ---- Lifecycle -----------------------------------------------------------

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _subscribeAccelerometer();

    // The trail renderer is intentionally NOT added as a child component:
    // Flame renders children *after* the parent, which would put the
    // trail on top of the orb. We own its update/render manually inside
    // [update]/[render] so we can draw the trail behind the orb body.
    trailRenderer = PlayerTrail(
      effect: trail,
      color: skin.trailColor,
      trailProvider: () => _trail,
      positionProvider: () => position,
      radiusProvider: () => radius,
    );
  }

  @override
  void onRemove() {
    _accelSub?.cancel();
    _accelSub = null;
    super.onRemove();
  }

  void _subscribeAccelerometer() {
    try {
      _accelSub = accelerometerEventStream().listen(
        (event) {
          // WHY invert: in portrait, tilting the device's right edge down
          // produces a positive event.x, but the player should slide right
          // (positive screen x), so we invert to match the user's intent.
          _accelX = -event.x;
          _hasAccel = true;
        },
        onError: (_) {
          _hasAccel = false;
        },
        cancelOnError: false,
      );
    } catch (_) {
      // Some platforms / test contexts don't have a sensor backend at all.
      _hasAccel = false;
    }
  }

  // ---- Hit / death / respawn ----------------------------------------------

  /// Apply a hit. Returns true if it actually landed (not i-framed/dead).
  /// On a fatal hit, kicks off the death sequence.
  bool onHit() {
    if (!isAlive || isInvincible) return false;
    _lives--;
    if (_lives <= 0) {
      _triggerDeath();
    } else {
      _invincibleTimer = invincibilityDuration;
    }
    onHitCallback?.call();
    return true;
  }

  /// Backwards-compatible alias for [onHit].
  bool hit() => onHit();

  /// Force a fatal hit. Bypasses i-frames and drains all lives in one
  /// step, then triggers the death sequence. Used by lethal hazards
  /// (lightning, stalactite) — the per-frame [onHit] loop they used to
  /// run hung the game whenever a non-fatal first hit set i-frames,
  /// because subsequent [onHit] calls then no-op'd while [isAlive]
  /// stayed true.
  void kill() {
    if (!isAlive) return;
    _lives = 0;
    _invincibleTimer = 0;
    _triggerDeath();
    onHitCallback?.call();
  }

  void _triggerDeath() {
    _isDeadState = true;
    velocity.setZero();
    final ps = particleSystem;
    if (ps != null) {
      ps.triggerDeath(position.clone(), skin.primaryColor);
    } else {
      _emitFallbackDeathParticles();
    }
  }

  /// Re-assemble at [target] (or the configured spawn point if omitted).
  /// Restores lives to [maxLives], clears velocity and i-frames, and
  /// triggers the inward-converge respawn particle effect.
  void respawn([Vector2? target]) {
    final dest = target ?? startPosition;
    position.setFrom(dest);
    velocity.setZero();
    _trail.clear();
    _lives = _maxLives;
    _isDeadState = false;
    _invincibleTimer = invincibilityDuration;
    _fallbackDeathParticles.clear();
    final ps = particleSystem;
    if (ps != null) {
      ps.triggerRespawn(dest.clone(), skin.primaryColor);
    }
  }

  void _emitFallbackDeathParticles() {
    final rng = math.Random();
    for (int i = 0; i < 30; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 100 + rng.nextDouble() * 220;
      _fallbackDeathParticles.add(_DeathParticle(
        position: position.clone(),
        velocity: Vector2(math.cos(angle), math.sin(angle)) * speed,
        life: 0.8 + rng.nextDouble() * 0.7,
      ));
    }
  }

  // ---- Update --------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    _stepPhysics(dt);
    _stepTrail();
    _stepInvincibility(dt);
    _stepFallbackParticles(dt);
    // Drive the trail's animation phase ourselves since it's no longer
    // attached as a child component (see onLoad). Guarded so headless
    // unit tests that drive update() without going through onLoad don't
    // hit a LateInitializationError.
    if (isMounted) {
      trailRenderer.update(dt);
    }
  }

  void _stepPhysics(double dt) {
    if (!isAlive) return;

    // Horizontal: prefer accelerometer when reporting; otherwise touch.
    // Convert raw input to a target velocity and snap to it — there's
    // no horizontal inertia, the orb feels twitchy if there is.
    final hInput = _hasAccel
        ? (_accelX * tiltSensitivity)
        : (_touchInput * maxHorizontalSpeed);
    velocity.x = hInput.clamp(-maxHorizontalSpeed, maxHorizontalSpeed);

    // Vertical: gravity + drag + terminal velocity, courtesy GravitySystem.
    final newVel = gravity.applyGravity(velocity, dt);
    velocity.setFrom(newVel);

    position.add(velocity * dt);

    // Clamp x so the ball never exits the horizontal play area.
    position.x = position.x.clamp(radius, playWidth - radius);
  }

  void _stepTrail() {
    if (!isAlive) return;
    _trail.add(position.clone());
    final cap = trail.sampleCount.clamp(1, trailHistoryLength);
    while (_trail.length > cap) {
      _trail.removeAt(0);
    }
  }

  void _stepInvincibility(double dt) {
    if (_invincibleTimer > 0) {
      _invincibleTimer = (_invincibleTimer - dt).clamp(0.0, invincibilityDuration);
    }
    _flashPhase += dt * 12; // ~6 flashes/sec when shield active
  }

  void _stepFallbackParticles(double dt) {
    if (_fallbackDeathParticles.isEmpty) return;
    for (final p in _fallbackDeathParticles) {
      // Linear drag — simple and matches the dedicated particle system.
      final decel = (1 - 1.5 * dt).clamp(0.0, 1.0);
      p.velocity.scale(decel);
      p.position.add(p.velocity * dt);
      p.life -= dt;
    }
    _fallbackDeathParticles.removeWhere((p) => p.life <= 0);
  }

  // ---- Render --------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    // PositionComponent renders in its own local space — anchor=center
    // means (size/2, size/2) is the orb's center.
    final cx = size.x / 2;
    final cy = size.y / 2;
    final center = Offset(cx, cy);

    // Trail draws first so the orb sits on top of it. Rendering the
    // trail manually here (instead of as a child component) is the
    // only way to get the trail BEHIND the orb — Flame's renderTree
    // unconditionally draws children after the parent.
    if (isMounted) {
      trailRenderer.render(canvas);
    }

    if (isAlive) {
      _renderWindLines(canvas, center);
      _renderOrb(canvas, center);
      _renderShield(canvas, center);
    }
    _renderFallbackDeathParticles(canvas, center);
  }

  void _renderWindLines(Canvas canvas, Offset center) {
    final speedMag = velocity.y.abs();
    if (speedMag < 50) return;

    // Both alpha and length scale with vertical speed up to terminal.
    final alpha =
        (speedMag / GravitySystem.terminalVelocity).clamp(0.0, 0.6);
    final lineLen = (speedMag / 800.0 * 36.0).clamp(8.0, 56.0);
    final paint = Paint()
      ..color = effectiveGlowColor.withValues(alpha: alpha)
      ..strokeWidth = 1.4;

    for (int i = 0; i < windLineCount; i++) {
      // Spread the streaks horizontally across the orb's width.
      final dx = (i - (windLineCount - 1) / 2) * 6.0;
      final topY = center.dy - radius - 6 - lineLen;
      canvas.drawLine(
        Offset(center.dx + dx, topY),
        Offset(center.dx + dx, topY + lineLen),
        paint,
      );
    }
  }

  void _renderOrb(Canvas canvas, Offset center) {
    // Skip drawing on alternating frames during i-frames for the flash.
    if (isInvincible && _flashPhase.floor() % 2 == 0) return;

    final glow = effectiveGlowColor;

    // Outer halo — soft falloff radial gradient.
    final haloRect = Rect.fromCircle(center: center, radius: radius * 2.2);
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          glow.withValues(alpha: 0.65),
          glow.withValues(alpha: 0.0),
        ],
      ).createShader(haloRect);
    canvas.drawCircle(center, radius * 2.2, haloPaint);

    // Body — bright primary core fading to glow at the rim.
    final bodyRect = Rect.fromCircle(center: center, radius: radius);
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        colors: [skin.primaryColor, glow],
        stops: const [0.15, 1.0],
      ).createShader(bodyRect);
    canvas.drawCircle(center, radius, bodyPaint);
  }

  void _renderShield(Canvas canvas, Offset center) {
    if (!isInvincible) return;
    // Sin-driven pulse: shield radius oscillates 30..45 px (the spec
    // calls for that range explicitly so the bubble visibly breathes).
    final pulse01 = 0.5 + 0.5 * math.sin(_flashPhase * math.pi);
    final shieldRadius = 30.0 + 15.0 * pulse01;

    final shieldFill = Paint()
      ..color = const Color(0xFF80DEEA).withValues(alpha: 0.10 + 0.10 * pulse01)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, shieldRadius, shieldFill);

    final shieldStroke = Paint()
      ..color = const Color(0xFF40E0D0).withValues(alpha: 0.45 + 0.30 * pulse01)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, shieldRadius, shieldStroke);
  }

  void _renderFallbackDeathParticles(Canvas canvas, Offset center) {
    if (_fallbackDeathParticles.isEmpty) return;
    for (final p in _fallbackDeathParticles) {
      final delta = p.position - position;
      final off = Offset(center.dx + delta.x, center.dy + delta.y);
      final alpha = (p.life / 1.5).clamp(0.0, 1.0);
      canvas.drawCircle(
        off,
        2 + (1 - alpha) * 1.5,
        Paint()..color = skin.primaryColor.withValues(alpha: alpha),
      );
    }
  }
}

/// Internal — fallback death-burst particle used only when the player
/// has no external PlayerParticleSystem wired up (mostly unit tests).
class _DeathParticle {
  final Vector2 position;
  final Vector2 velocity;
  double life;

  _DeathParticle({
    required this.position,
    required this.velocity,
    required this.life,
  });
}
