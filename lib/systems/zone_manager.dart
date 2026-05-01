// systems/zone_manager.dart
//
// Authoritative depth → zone mapper. ZoneManager turns a single scalar
// (current depth in meters) into:
//   * the active Zone,
//   * the next Zone (used for gradient blending at the deep edge),
//   * a 0..1 fraction through the active zone,
//   * a smoothly interpolated background gradient,
//   * a "cycle multiplier" that ticks up every full 5-zone descent.
//
// ZoneManager is intentionally NOT a GameSystem: it doesn't run on the
// fixed-step loop. CameraSystem is the source of truth for depth, so it
// pokes ZoneManager once per camera tick. This keeps zone state in lockstep
// with the camera without a second redundant integration.

import 'dart:ui';

import '../models/zone.dart';

/// Resolved background gradient at a given depth. Returned by
/// [ZoneManager.backgroundGradient]; the renderer draws a vertical
/// linear gradient from [top] to [bottom].
class ZoneGradient {
  final Color top;
  final Color bottom;
  const ZoneGradient(this.top, this.bottom);
}

class ZoneManager {
  /// Zones that make up one descent cycle. Defaults to the canonical
  /// 5-zone Phase-2 set; tests override this to exercise edge cases.
  final List<Zone> cycle;

  /// Difficulty multiplier added each full cycle. Tuned to 0.2 so the
  /// jump on the second pass through the Stratosphere is "noticeably
  /// harder" without instantly capping out our spawn-rate / speed
  /// ceilings (those land around the 5th cycle).
  static const double cycleMultiplierStep = 0.2;

  /// Notification fired the first frame the player crosses into a new
  /// zone. The host wires this to [ZoneTransition] for the name flash.
  void Function(ZoneType zone)? onZoneEnter;

  ZoneType? _previousZoneType;
  double _depthMeters = 0;
  int _completedCycles = 0;

  ZoneManager({List<Zone>? cycle, this.onZoneEnter})
      : cycle = cycle ?? Zone.defaultCycle {
    assert(this.cycle.isNotEmpty, 'ZoneManager needs at least one zone');
  }

  /// Current depth fed in by CameraSystem. Read by [DifficultyScaler]
  /// and tests for assertions.
  double get currentDepthMeters => _depthMeters;

  /// Number of full 5-zone cycles completed so far.
  int get completedCycles => _completedCycles;

  /// 1.0 on the first descent, 1.2 on the second, 1.4 on the third…
  /// Bumped each time depth crosses a multiple of [Zone.cycleDepth].
  double get currentCycleMultiplier =>
      1.0 + cycleMultiplierStep * _completedCycles;

  /// Total depth of one cycle in meters. Convenience for callers that
  /// don't want to import [Zone] directly.
  double get cycleDepth => cycle.fold<double>(
      0, (acc, z) => acc + (z.endDepth - z.startDepth));

  /// The zone the player is currently inside. Always non-null because
  /// [_depthInCycle] wraps depth back into [0, cycleDepth).
  Zone get currentZone => _zoneAtCycleDepth(_depthInCycle(_depthMeters));

  /// The next zone after [currentZone], wrapping back to index 0 after
  /// the last zone. Used to lerp the gradient through the deep-edge
  /// transition slice.
  Zone get nextZone {
    final i = cycle.indexWhere((z) => z.type == currentZone.type);
    return cycle[(i + 1) % cycle.length];
  }

  /// True iff the current depth is within [Zone.transitionDepth] of the
  /// active zone's deep edge. The renderer blends gradients while this
  /// is on; gameplay systems can use it to telegraph zone changes.
  bool get isInTransition {
    final z = currentZone;
    final inCycle = _depthInCycle(_depthMeters);
    return inCycle >= z.endDepth - Zone.transitionDepth;
  }

  /// 0..1 progress through the active zone. 0.0 at the shallow edge,
  /// 1.0 at the deep edge.
  double zoneFraction(double depthMeters) {
    final inCycle = _depthInCycle(depthMeters);
    final z = _zoneAtCycleDepth(inCycle);
    final span = z.endDepth - z.startDepth;
    if (span <= 0) return 0;
    return ((inCycle - z.startDepth) / span).clamp(0.0, 1.0);
  }

  /// Resolved top/bottom colors for the gradient rendered at [depthMeters].
  ///
  /// Within a zone we lerp between [topColor] and [bottomColor] by the
  /// zone fraction, which gives a smooth top-to-bottom darkening as the
  /// player descends. In the deep-edge transition slice we additionally
  /// lerp toward the next zone's colors so the seam disappears.
  ZoneGradient backgroundGradient(double depthMeters) {
    final inCycle = _depthInCycle(depthMeters);
    final z = _zoneAtCycleDepth(inCycle);
    final f = zoneFraction(depthMeters);

    // Within-zone gradient — top/bottom shift slightly with depth so the
    // viewport is never pure top OR pure bottom; the player always sees
    // motion in the colors as they fall.
    var top = Color.lerp(z.topColor, z.bottomColor, f * 0.4)!;
    var bottom = Color.lerp(z.topColor, z.bottomColor, 0.6 + f * 0.4)!;

    // Deep-edge transition: lerp toward the next zone over the last
    // [Zone.transitionDepth] meters. By the moment we cross the edge
    // we're already 100% in the next zone's palette, so onZoneEnter's
    // flash lands on a settled background.
    final transitionStart = z.endDepth - Zone.transitionDepth;
    if (inCycle >= transitionStart) {
      final t = ((inCycle - transitionStart) / Zone.transitionDepth)
          .clamp(0.0, 1.0);
      final n = _zoneAfter(z);
      top = Color.lerp(top, n.topColor, t)!;
      bottom = Color.lerp(bottom, n.bottomColor, t)!;
    }

    return ZoneGradient(top, bottom);
  }

  /// Called by [CameraSystem] every fixed step. Detects zone crossings
  /// (fires [onZoneEnter]) and cycle wraps (bumps [currentCycleMultiplier]).
  ///
  /// Idempotent for repeated calls at the same depth — only state edges
  /// trigger side effects.
  void update(double depthMeters) {
    final prev = _depthMeters;
    _depthMeters = depthMeters;

    final prevCycles = (prev / Zone.cycleDepth).floor();
    final newCycles = (depthMeters / Zone.cycleDepth).floor();
    if (newCycles > prevCycles && newCycles > _completedCycles) {
      _completedCycles = newCycles;
    }

    final activeType = currentZone.type;
    if (_previousZoneType != activeType) {
      _previousZoneType = activeType;
      onZoneEnter?.call(activeType);
    }
  }

  /// Reset all state for a new run. Does NOT clear the [onZoneEnter]
  /// callback — the host registers that once at game-load time.
  void reset() {
    _depthMeters = 0;
    _completedCycles = 0;
    _previousZoneType = null;
  }

  // ---- internals --------------------------------------------------------

  double _depthInCycle(double depthMeters) {
    if (depthMeters < 0) return 0;
    return depthMeters % Zone.cycleDepth;
  }

  Zone _zoneAtCycleDepth(double inCycle) {
    for (final z in cycle) {
      if (inCycle < z.endDepth) return z;
    }
    return cycle.last;
  }

  Zone _zoneAfter(Zone z) {
    final i = cycle.indexWhere((c) => c.type == z.type);
    return cycle[(i + 1) % cycle.length];
  }
}
