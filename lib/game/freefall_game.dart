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

import '../components/particle_system.dart' as comp_particles;
import '../components/player.dart';
import '../components/zone_background.dart';
import '../components/zone_transition.dart';
import '../systems/camera_system.dart';
import '../systems/coin_system.dart';
import '../systems/collision_system.dart';
import '../systems/difficulty_scaler.dart';
import '../systems/gravity_system.dart';
import '../systems/input_system.dart';
import '../systems/object_pool.dart';
import '../systems/obstacle_manager.dart';
import '../systems/obstacle_spawner.dart';
import '../systems/obstacle_system.dart';
import '../systems/particle_system.dart';
import '../systems/player_system.dart';
import '../systems/zone_manager.dart';
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

  // Phase 2: zone & difficulty state. ZoneManager isn't a GameSystem
  // (it's pumped by CameraSystem each tick); DifficultyScaler is a
  // pure-function lookup, no per-frame work of its own.
  late final ZoneManager zoneManager;
  late final DifficultyScaler difficultyScaler;

  // Phase 3: obstacle pipeline. The spawner produces obstacles two
  // screens ahead; the manager owns their lifecycle (attach to world,
  // prune offscreen). Both are GameSystems registered on the fixed-step
  // bus so spawning stays in lockstep with camera advance.
  late final ObstacleManager obstacleManager;
  late final ObstacleSpawner obstacleSpawner;

  // Object pools, ready for Phase 2 to consume.
  late final ObstaclePool obstaclePool;
  late final CoinPool coinPool;
  late final ParticlePool particlePool;

  late final GameLoop gameLoop;
  late final Player player;
  late final ZoneBackground zoneBackground;
  late final ZoneTransition zoneTransition;

  // Phase 4: dedicated death/respawn particle component. Lives in the
  // world (above background, below player) and is driven by the player
  // through PlayerParticleSystem.triggerDeath / triggerRespawn.
  late final comp_particles.PlayerParticleSystem playerParticles;

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

    // Phase 2: zone state. The transition overlay listens for zone
    // entries via ZoneManager's callback. CameraSystem owns pumping the
    // manager each fixed step.
    zoneTransition = ZoneTransition();
    zoneManager = ZoneManager(onZoneEnter: zoneTransition.show);
    cameraSystem.zoneManager = zoneManager;
    difficultyScaler = DifficultyScaler(zoneManager: zoneManager);

    obstaclePool = ObstaclePool();
    coinPool = CoinPool();
    particlePool = ParticlePool();

    // Phase 3: build the obstacle pipeline before the world is populated
    // so the first-frame spawn batch is in flight by the time Flame draws.
    obstacleManager = ObstacleManager(
      onSpawn: (o) => world.add(o),
      onDespawn: (o) => o.removeFromParent(),
    );
    obstacleSpawner = ObstacleSpawner(
      cameraSystem: cameraSystem,
      difficultyScaler: difficultyScaler,
      zoneManager: zoneManager,
      manager: obstacleManager,
      playWidth: logicalWidth,
      viewportHeight: logicalHeight,
    );

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
    // Spawner runs after camera so it sees the freshest player position;
    // manager runs last so any pruning happens after spawner adds.
    gameLoop.register(obstacleSpawner);
    gameLoop.register(obstacleManager);

    // Background goes into the world *before* the player so it sits at
    // the bottom of the draw order. The component reads from
    // CameraSystem each frame and re-anchors itself to the viewport.
    zoneBackground = ZoneBackground(
      zoneManager: zoneManager,
      cameraSystem: cameraSystem,
    );
    await world.add(zoneBackground);

    // Phase 4: particle system shares the global ParticlePool so the
    // 60-particle death burst doesn't allocate per death.
    playerParticles = comp_particles.PlayerParticleSystem(pool: particlePool);
    await world.add(playerParticles);

    player = Player(
      gravity: gravitySystem,
      startPosition: Vector2(logicalWidth / 2, 120),
      particleSystem: playerParticles,
    );
    await world.add(player);

    // Zone-name flash overlay sits in the camera viewport so it stays
    // anchored to the screen instead of drifting with the world.
    await camera.viewport.add(zoneTransition);

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

    // Phase 3: prune obstacles that have scrolled off the top of the
    // viewport. Done here (after gameLoop) so we use the freshest camera
    // position. The viewport top in world Y is the player's Y minus
    // half the logical height since the camera follows the player.
    final viewportTopY = player.position.y - logicalHeight / 2;
    obstacleManager.pruneOffscreen(viewportTopY);
    obstacleManager.notifyPlayer(player.position);

    // Phase 4: tint the player's glow with the active zone accent. Done
    // every tick (cheap — just stashes a color) so zone-edge gradient
    // blends and the orb's color stay in sync without a callback.
    player.setZoneColor(zoneManager.currentZone.accentColor);

    super.update(clamped);
  }

  /// Total fixed-timestep ticks since startup. Useful for tests.
  int get totalSimSteps => gameLoop.totalSteps;
}
