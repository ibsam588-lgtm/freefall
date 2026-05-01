// systems/obstacle_manager.dart
//
// Owns the live set of obstacles in the world. Spawner produces new
// obstacles and hands them off here; ObstacleManager handles attaching
// them to the Flame world (via injected callbacks), removing them when
// they scroll out of frame, and exposing the current active set to the
// collision pipeline.
//
// We keep attach/detach as injected callbacks rather than holding a
// FlameGame reference so the manager can be unit-tested headlessly —
// the spawner test passes no-op callbacks and asserts on the active
// list directly.

import 'package:flame/components.dart';

import '../components/hazards/stalactite.dart';
import '../components/obstacles/breakable_platform.dart';
import '../components/obstacles/game_obstacle.dart';
import '../components/obstacles/speed_gate.dart';
import 'system_base.dart';

class ObstacleManager implements GameSystem {
  /// How far above the camera viewport's top edge an obstacle has to
  /// drift before we recycle it. Bigger margin = more in flight at
  /// once but a smoother edge as obstacles scroll off; 200px is a
  /// safe buffer for tall obstacles like LightningBolt.
  static const double offscreenMargin = 200;

  /// Called when the manager wants the obstacle attached to the visual
  /// scene (typically `world.add(obstacle)`).
  final void Function(GameObstacle obstacle)? onSpawn;

  /// Called when the manager wants the obstacle detached. The manager
  /// has already removed it from its own active list at this point.
  final void Function(GameObstacle obstacle)? onDespawn;

  final List<GameObstacle> _active = [];

  /// Cached for tests/diagnostics.
  int spawnCount = 0;
  int despawnCount = 0;

  ObstacleManager({this.onSpawn, this.onDespawn});

  /// Live obstacle list. Callers must not mutate this — they should use
  /// [add] / [removeAll]. Kept as a List (not iterable) so the collision
  /// pipeline can index into it without copying.
  List<GameObstacle> get activeObstacles => List.unmodifiable(_active);

  /// Number of currently tracked obstacles. Cheap.
  int get activeCount => _active.length;

  /// Track [obstacle] and fire the spawn callback. Idempotent — adding
  /// the same instance twice is a no-op.
  void add(GameObstacle obstacle) {
    if (_active.contains(obstacle)) return;
    _active.add(obstacle);
    spawnCount++;
    onSpawn?.call(obstacle);
  }

  /// Untrack and detach [obstacle]. Idempotent.
  void remove(GameObstacle obstacle) {
    if (!_active.remove(obstacle)) return;
    despawnCount++;
    onDespawn?.call(obstacle);
  }

  /// Wipe the world for a fresh run.
  void clear() {
    while (_active.isNotEmpty) {
      remove(_active.first);
    }
  }

  /// Each fixed step: prune obstacles whose bottoms have fully cleared
  /// the camera viewport, plus consumed/expired one-shots.
  ///
  /// [viewportTopY] is the world-Y of the camera viewport's top edge —
  /// anything with a bottom Y above (less than) that minus
  /// [offscreenMargin] is offscreen and safe to remove.
  void pruneOffscreen(double viewportTopY) {
    final threshold = viewportTopY - offscreenMargin;
    for (int i = _active.length - 1; i >= 0; i--) {
      final o = _active[i];
      if (o.bottomY < threshold) {
        _active.removeAt(i);
        despawnCount++;
        onDespawn?.call(o);
        continue;
      }
      // Consumed one-shots that have finished animating.
      if (o is BreakablePlatform && o.isGone) {
        _active.removeAt(i);
        despawnCount++;
        onDespawn?.call(o);
      } else if (o is SpeedGate && o.isConsumed) {
        // Speed gate fades for ~0.4s after consume; keep until offscreen
        // OR until the fade finishes (visually invisible).
        // Defer removal to the offscreen branch above; rendering already
        // hides it at alpha 0.
      }
    }
  }

  /// Notify obstacles that the player is at [playerWorldPos]. Currently
  /// only stalactites care — they trigger their drop when the player
  /// passes within [Stalactite.triggerHorizontalDistance].
  void notifyPlayer(Vector2 playerWorldPos) {
    for (final o in _active) {
      if (o is Stalactite) o.considerTrigger(playerWorldPos);
    }
  }

  @override
  void update(double dt) {
    // The manager doesn't drive its own pruning here — it doesn't know
    // the camera position. The host (FreefallGame) calls [pruneOffscreen]
    // each tick after CameraSystem has advanced. Keeping update() empty
    // means GameLoop dispatch order doesn't matter for pruning.
  }
}
