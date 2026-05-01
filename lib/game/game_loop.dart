// game/game_loop.dart
//
// Fixed-timestep simulation driver. The renderer (Flame) calls tick(dt)
// once per frame with the variable wall-clock delta; we accumulate that
// and fire each registered system at exactly [fixedDt] seconds. This
// gives deterministic physics regardless of display refresh rate.
//
// Spiral-of-death guard: if a long frame would force >5 fixed steps in
// a single tick, we drop the excess. WHY: better to lose 80ms of sim
// time once than to lock up the main thread trying to catch up.

import 'dart:ui';

import '../systems/coin_system.dart';
import '../systems/collision_system.dart';
import '../systems/gravity_system.dart';
import '../systems/input_system.dart';
import '../systems/obstacle_system.dart';
import '../systems/particle_system.dart';
import '../systems/player_system.dart';
import '../systems/system_base.dart';
import '../systems/camera_system.dart';

class GameLoop {
  /// Target tick rate. 60 Hz is the highest non-Pro Android refresh and
  /// what every gameplay constant in the project is tuned against.
  static const double fixedDt = 1.0 / 60.0;

  /// Hard cap on fixed steps per render frame (see top-of-file note).
  static const int maxStepsPerFrame = 5;

  final List<GameSystem> _systems = [];
  double _accumulator = 0;
  int _totalSteps = 0;

  GameLoop({Iterable<GameSystem>? systems}) {
    if (systems != null) _systems.addAll(systems);
  }

  /// Add a system to the dispatch list. Order matters — earlier systems
  /// see input that later systems will consume.
  void register(GameSystem system) => _systems.add(system);

  /// Total fixed steps executed since construction. Useful for tests
  /// and as a deterministic random seed input.
  int get totalSteps => _totalSteps;

  /// Number of registered systems.
  int get systemCount => _systems.length;

  /// Advance the simulation by [dt] seconds of wall-clock time.
  /// Returns the number of fixed steps actually run this call.
  int tick(double dt) {
    _accumulator += dt;
    int steps = 0;
    while (_accumulator >= fixedDt && steps < maxStepsPerFrame) {
      for (final system in _systems) {
        system.update(fixedDt);
      }
      _accumulator -= fixedDt;
      steps++;
      _totalSteps++;
    }
    // Drop any leftover accumulated time we refused to simulate, so we
    // don't carry a debt into the next frame and cascade.
    if (steps == maxStepsPerFrame && _accumulator >= fixedDt) {
      _accumulator = 0;
    }
    return steps;
  }

  /// Render hook for spec compliance. Components are drawn by Flame's
  /// own render pipeline (FlameGame.render walks the component tree),
  /// so this is a no-op pass-through. Kept here for future systems
  /// that want to draw debug overlays.
  void render(Canvas canvas) {
    // intentionally empty
  }

  /// Builds a GameLoop pre-wired with the canonical Phase-1 system order.
  /// Centralizes the dispatch order so FreefallGame doesn't have to
  /// repeat it (and the tests can build the same loop trivially).
  factory GameLoop.standard({
    required InputSystem input,
    required GravitySystem gravity,
    required CameraSystem camera,
    required CollisionSystem collision,
    required PlayerSystem player,
    required ObstacleSystem obstacle,
    required CoinSystem coin,
    required ParticleSystem particle,
  }) {
    return GameLoop(systems: [
      input,
      gravity,
      camera,
      collision,
      player,
      obstacle,
      coin,
      particle,
    ]);
  }
}
