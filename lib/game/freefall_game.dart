// game/freefall_game.dart
//
// Root FlameGame for Freefall. Owns the GameLoop and every system,
// hosts the Player component, and pumps Flame's update with a clamped
// dt so the simulation stays well-behaved across long frames.
//
// Logical resolution is fixed at 414x896 (iPhone 12 Pro reference).
// Every gameplay constant is authored against this — Flame's
// CameraComponent.withFixedResolution scales to fit the device.

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../components/player.dart';
import '../systems/camera_system.dart';
import '../systems/coin_system.dart';
import '../systems/collision_system.dart';
import '../systems/gravity_system.dart';
import '../systems/input_system.dart';
import '../systems/object_pool.dart';
import '../systems/obstacle_system.dart';
import '../systems/particle_system.dart';
import '../systems/player_system.dart';
import 'game_loop.dart';

class FreefallGame extends FlameGame {
  /// Reference logical resolution. Tune gameplay numbers against this.
  static const double logicalWidth = 414;
  static const double logicalHeight = 896;

  /// Cap on a single frame's wall-clock dt, in seconds.
  /// WHY: a long pause (GC, app foregrounding) can hand us a 0.5s dt.
  /// Stepping physics that far in one shot tunnels through obstacles
  /// and is the classic "spiral of death" setup. Clamping says
  /// "slow time during stalls" — much friendlier than skipping frames.
  static const double maxFrameDt = 1.0 / 30.0;

  // Systems — late so we can construct them in onLoad with full context.
  late final InputSystem inputSystem;
  late final GravitySystem gravitySystem;
  late final CameraSystem cameraSystem;
  late final CollisionSystem collisionSystem;
  late final PlayerSystem playerSystem;
  late final ObstacleSystem obstacleSystem;
  late final CoinSystem coinSystem;
  late final ParticleSystem particleSystem;

  // Object pools, ready for Phase 2 to consume.
  late final ObstaclePool obstaclePool;
  late final CoinPool coinPool;
  late final ParticlePool particlePool;

  late final GameLoop gameLoop;
  late final Player player;

  FreefallGame()
      : super(
          camera: CameraComponent.withFixedResolution(
            width: logicalWidth,
            height: logicalHeight,
          ),
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    inputSystem = InputSystem();
    gravitySystem = GravitySystem();
    cameraSystem = CameraSystem();
    collisionSystem = CollisionSystem();
    playerSystem = PlayerSystem();
    obstacleSystem = ObstacleSystem();
    coinSystem = CoinSystem();
    particleSystem = ParticleSystem();

    obstaclePool = ObstaclePool();
    coinPool = CoinPool();
    particlePool = ParticlePool();

    gameLoop = GameLoop.standard(
      input: inputSystem,
      gravity: gravitySystem,
      camera: cameraSystem,
      collision: collisionSystem,
      player: playerSystem,
      obstacle: obstacleSystem,
      coin: coinSystem,
      particle: particleSystem,
    );

    player = Player(
      gravity: gravitySystem,
      startPosition: Vector2(logicalWidth / 2, 120),
    );
    await world.add(player);

    // The Flame camera follows the player vertically. The auto-scroll
    // feeling comes from the player constantly accelerating downward
    // under gravity — the camera tags along, and CameraSystem's
    // currentDepthMeters reads as "depth fallen".
    camera.follow(player, snap: true);
  }

  @override
  void update(double dt) {
    final clamped = dt > maxFrameDt ? maxFrameDt : dt;

    // Keep CameraSystem in sync with the player's world position so
    // anything that wants "player depth" reads a fresh value.
    cameraSystem.playerWorldPosition.setFrom(player.position);

    // Run our deterministic fixed-step systems FIRST so Flame's component
    // updates (which run in super.update) see the latest system state.
    gameLoop.tick(clamped);

    super.update(clamped);
  }

  /// Total fixed-timestep ticks since startup. Useful for tests.
  int get totalSimSteps => gameLoop.totalSteps;
}
