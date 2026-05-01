// systems/powerup_manager.dart
//
// Active-powerup state machine. CollectibleManager calls
// [activatePowerup] on pickup; the manager runs a per-frame countdown,
// exposes "is X active" + per-effect multiplier getters, and clears
// timers as they expire.
//
// Special-cased durations:
//   * shield: stays active until consumeShield() is called (one-hit).
//   * extraLife: 0-second duration; we never enter the active map for
//     it — handled inline by the caller, who bumps Player.maxLives /
//     lives. We still expose a getter for tests.
//
// Multipliers are 1.0 when no effect of that flavor is active, the
// effect's value when it is. Magnet exposes a radius (0 vs 200).

import '../models/collectible.dart';
import 'system_base.dart';

/// One in-flight powerup. Mutable [remainingSeconds] is decremented by
/// [PowerupManager.update] each tick.
class ActivePowerup {
  final PowerupType type;
  double remainingSeconds;

  ActivePowerup({required this.type, required this.remainingSeconds});
}

class PowerupManager implements GameSystem {
  /// Magnet pull radius, in world pixels.
  static const double magnetActiveRadius = 200;

  /// Slow-mo speed scalar — camera+world step at this fraction of normal.
  static const double slowMoScalar = 0.5;

  /// Score and coin multiplier values when active.
  static const double scoreActiveMultiplier = 2.0;
  static const double coinActiveMultiplier = 2.0;

  /// Number of extra lives granted by a single extraLife pickup.
  static const int extraLifeAmount = 1;

  // Map keyed by type so two consecutive magnet pickups extend the
  // existing timer rather than spawning a duplicate entry.
  final Map<PowerupType, ActivePowerup> _active = {};

  /// Optional hook for the host to grant a life when extraLife fires.
  /// The manager doesn't reach into Player directly; the caller wires
  /// this so the headless tests can observe a counter without Flame.
  void Function()? onExtraLife;

  /// Read-only snapshot of currently active effects.
  Iterable<ActivePowerup> get activeEffects => _active.values;

  /// Convenience: number of distinct effects currently in flight.
  int get activeCount => _active.length;

  /// Activate [type] for the spec'd duration. extraLife is instant —
  /// it fires [onExtraLife] and never enters the active map.
  void activatePowerup(PowerupType type, {double? duration}) {
    if (type == PowerupType.extraLife) {
      onExtraLife?.call();
      return;
    }
    final secs = duration ?? PowerupDuration.forType(type);
    final existing = _active[type];
    if (existing == null) {
      _active[type] = ActivePowerup(type: type, remainingSeconds: secs);
    } else {
      // Re-pickup extends to the larger of (current remaining, new
      // duration). Picking the max means a fresh full-duration pickup
      // never *shortens* an in-flight long-tail effect.
      if (secs > existing.remainingSeconds) {
        existing.remainingSeconds = secs;
      }
    }
  }

  /// True iff [type] currently has time remaining (or is the consume-on-hit
  /// shield, which is "active until consumed").
  bool isActive(PowerupType type) {
    final p = _active[type];
    if (p == null) return false;
    return p.remainingSeconds > 0 || p.remainingSeconds == double.infinity;
  }

  /// Time left on [type], or 0 if not active. Returns +inf for shield.
  double remaining(PowerupType type) =>
      _active[type]?.remainingSeconds ?? 0;

  /// Magnet pull radius in world pixels. 0 when magnet inactive.
  double get magnetRadius =>
      isActive(PowerupType.magnet) ? magnetActiveRadius : 0;

  /// Speed scalar applied to camera/world motion (slow-mo). 1.0 normally.
  double get speedMultiplier =>
      isActive(PowerupType.slowMo) ? slowMoScalar : 1.0;

  /// Score awarded on pickup is multiplied by this. 1.0 normally.
  double get scoreMultiplier =>
      isActive(PowerupType.scoreMultiplier) ? scoreActiveMultiplier : 1.0;

  /// Coin currency awarded on pickup is multiplied by this. 1.0 normally.
  double get coinMultiplier =>
      isActive(PowerupType.coinMultiplier) ? coinActiveMultiplier : 1.0;

  /// Consume the shield. Called by collision pipeline on a damaging hit
  /// before lives are decremented. Returns true if a shield was active
  /// (i.e. the hit should be absorbed).
  bool consumeShield() {
    if (!isActive(PowerupType.shield)) return false;
    _active.remove(PowerupType.shield);
    return true;
  }

  /// Cancel everything — used on player death / new run.
  void clear() => _active.clear();

  @override
  void update(double dt) {
    if (_active.isEmpty) return;
    final expired = <PowerupType>[];
    for (final entry in _active.entries) {
      // Shield's remainingSeconds is +inf so subtraction is a no-op
      // arithmetically. Skip explicitly so we don't accidentally turn
      // it into NaN on long sessions.
      if (entry.value.remainingSeconds == double.infinity) continue;
      entry.value.remainingSeconds -= dt;
      if (entry.value.remainingSeconds <= 0) {
        expired.add(entry.key);
      }
    }
    for (final t in expired) {
      _active.remove(t);
    }
  }
}
