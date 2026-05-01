// game/freefall_game.dart
//
// Root FlameGame for Freefall. Owns the GameLoop and every system,
// hosts the Player component, and pumps Flame's update with a clamped
// dt so the simulation stays well-behaved across long frames.
//
// Logical resolution is fixed at 414x896 (iPhone 12 Pro reference).
// Every gameplay constant is authored against this — Flame's
// CameraComponent.withFixedResolution scales to fit the device.

import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../components/combo_display.dart';
import '../components/floating_text.dart';
import '../components/hud.dart';
import '../components/near_miss_detector.dart';
import '../components/particle_system.dart' as comp_particles;
import '../components/player.dart';
import '../components/zone_background.dart';
import '../components/zone_transition.dart';
import '../models/zone.dart';
import '../repositories/coin_repository.dart';
import '../repositories/stats_repository.dart';
import '../services/analytics_service.dart';
import '../services/audio_service.dart';
import '../systems/achievement_manager.dart';
import '../systems/camera_system.dart';
import '../systems/performance_monitor.dart';
import '../systems/coin_system.dart';
import '../systems/collectible_manager.dart';
import '../systems/collectible_spawner.dart';
import '../systems/collision_system.dart';
import '../systems/difficulty_scaler.dart';
import '../systems/ghost_runner.dart';
import '../systems/gravity_system.dart';
import '../systems/input_system.dart';
import '../systems/object_pool.dart';
import '../systems/obstacle_manager.dart';
import '../systems/obstacle_spawner.dart';
import '../systems/obstacle_system.dart';
import '../systems/particle_system.dart';
import '../systems/player_system.dart';
import '../systems/powerup_manager.dart';
import '../systems/score_manager.dart';
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

  // Phase 5: collectibles + powerups. PowerupManager runs on the fixed
  // step bus (timer countdowns); CollectibleManager owns the live set
  // and pickup pipeline; CollectibleSpawner produces them ahead of the
  // camera. CoinRepository persists the spendable balance across runs.
  late final PowerupManager powerupManager;
  late final CollectibleManager collectibleManager;
  late final CollectibleSpawner collectibleSpawner;
  late final CoinRepository coinRepository;
  late final GameHud hud;

  // Phase 6: scoring + combo. ScoreManager is on the fixed-step bus
  // (combo timeout decay); NearMissDetector runs from the host with
  // the freshest player rect; StatsRepository persists lifetime
  // counters across runs.
  late final ScoreManager scoreManager;
  late final NearMissDetector nearMissDetector;
  late final ComboDisplay comboDisplay;
  late final StatsRepository statsRepository;

  /// Phase 9: fired exactly once per run when the player's death
  /// sequence has finished and the run summary should be shown.
  /// GameScreen sets this; FreefallGame fires it from the per-frame
  /// death-edge detector.
  void Function()? onRunEnded;

  /// Internal: tracks whether [onRunEnded] has been fired for the
  /// current run. Cleared by [restartRun].
  bool _runEnded = false;

  /// Phase 10: optional. When set, the game routes in-run signals
  /// (combo, gem, zone, hit, speed gate) into the manager so unlock
  /// popups can fire mid-run.
  AchievementManager? achievementManager;

  /// Phase 10: optional ghost runner. When set, the game records the
  /// player's x position every fixed step and saves the run as the new
  /// best ghost when the score beats the previous record.
  GhostRunner? ghostRunner;

  /// Phase 11: optional audio backend. When set, gameplay events
  /// trigger sound effects + zone music. Defaults to a silent
  /// [AudioService] so the game runs without one wired up.
  AudioService audio = AudioService();

  /// Phase 14: optional perf monitor. When set, the game feeds
  /// per-frame dts into it (after clamping) and downstream visual
  /// components (ZoneBackground, PlayerParticleSystem) read its
  /// `maxParticles` / `backgroundLayers` budgets each frame.
  PerformanceMonitor? performanceMonitor;

  /// Phase 14: optional analytics. When set, the game logs
  /// `zone_reached` events on each zone crossing.
  AnalyticsService? analytics;

  /// Elapsed run time in seconds — driven from [update]. Used by the
  /// ghost runner for sample timestamps; reset on [restartRun].
  double _runElapsed = 0;

  /// Phase 11: throttle for the periodic whoosh SFX. Counts down to
  /// zero, fires the whoosh, resets to [whooshIntervalSeconds]. Reset
  /// on [restartRun] so the next run doesn't fire mid-respawn.
  static const double whooshIntervalSeconds = 0.5;
  double _whooshCooldown = whooshIntervalSeconds;

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
    // manager each fixed step. Phase 6 chains onto the same callback
    // so a fresh zone fires both the flash AND the +500 score bonus.
    // Phase 10 chains onto it again to feed the achievement manager.
    zoneTransition = ZoneTransition();
    zoneManager = ZoneManager(onZoneEnter: (zone) {
      zoneTransition.show(zone);
      scoreManager.onZoneComplete();
      _emitZoneEvent(zone);
      // Phase 11: switch background music to the zone track and
      // accent the change with the transition SFX. Same-zone calls
      // dedup inside AudioService so a no-op rebuild stays silent.
      audio.playZoneMusic(zone);
      audio.playZoneTransition();
      // Phase 14: log to analytics. The fire-and-forget call no-ops
      // when the analytics backend is the null impl.
      analytics?.logZoneReached(zone);
    });
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

    // Phase 5: powerup + collectibles pipeline. Built before the loop is
    // wired so we can register the systems in the right order.
    powerupManager = PowerupManager();
    collectibleManager = CollectibleManager(
      onAttach: (c) => world.add(c),
      onDetach: (c) => c.removeFromParent(),
    )..powerupManager = powerupManager;
    collectibleSpawner = CollectibleSpawner(
      cameraSystem: cameraSystem,
      manager: collectibleManager,
      playWidth: logicalWidth,
      viewportHeight: logicalHeight,
    );
    coinRepository = CoinRepository();

    // Phase 6: scoring + combo. ScoreManager reads the powerup
    // multiplier; NearMissDetector is a plain helper, no per-tick
    // bookkeeping of its own (the host pumps it).
    scoreManager = ScoreManager(powerupManager: powerupManager);
    nearMissDetector = NearMissDetector();
    statsRepository = StatsRepository();

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
    // Powerup manager ticks before collectible manager so any expiring
    // magnet doesn't pull a coin one extra frame after expiry.
    gameLoop.register(powerupManager);
    gameLoop.register(collectibleSpawner);
    gameLoop.register(collectibleManager);
    // Score manager ticks last in the registry so it sees a settled
    // world (combo timer drains here; depth points are added from the
    // host after the camera has advanced).
    gameLoop.register(scoreManager);

    // Background goes into the world *before* the player so it sits at
    // the bottom of the draw order. The component reads from
    // CameraSystem each frame and re-anchors itself to the viewport.
    zoneBackground = ZoneBackground(
      zoneManager: zoneManager,
      cameraSystem: cameraSystem,
      performanceMonitor: performanceMonitor,
    );
    await world.add(zoneBackground);

    // Phase 4: particle system shares the global ParticlePool so the
    // 60-particle death burst doesn't allocate per death. Phase 14
    // feeds it the perf monitor so a struggling device gets a 30/15
    // particle burst instead of the full 60.
    playerParticles = comp_particles.PlayerParticleSystem(
      pool: particlePool,
      performanceMonitor: performanceMonitor,
    );
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

    // Phase 5+9: HUD rides the same viewport so it tracks the screen.
    // Live readers wired here so the HUD pulls depth/zone/score off
    // the freshest values every frame without owning a system ref.
    hud = GameHud(
      powerupManager: powerupManager,
      collectibleManager: collectibleManager,
      player: HudPlayerAdapter(() => player.lives, () => player.maxLives),
    )
      ..scoreGetter = (() => scoreManager.score)
      ..depthMetersGetter = (() => cameraSystem.currentDepthMeters)
      ..zoneNameGetter = (() => zoneManager.currentZone.name)
      ..zoneProgressGetter =
          (() => zoneManager.zoneFraction(zoneManager.currentDepthMeters));
    await camera.viewport.add(hud);

    // Phase 6: combo display sits in the same viewport so it stays
    // anchored to the screen. ScoreManager pokes it via callbacks.
    comboDisplay = ComboDisplay();
    await camera.viewport.add(comboDisplay);
    scoreManager.onComboChanged = (combo) {
      comboDisplay.onComboIncrement(combo);
      _emitComboEvent(combo);
    };
    scoreManager.onComboReset = comboDisplay.startFade;

    // Phase 6: a player hit collapses the combo. Wired via the callback
    // hook on Player so the combo reset stays in lockstep with damage.
    // Phase 10 also forwards the hit to the achievement manager so
    // no-hit-zone progress gets correctly invalidated.
    player.onHitCallback = () {
      scoreManager.onPlayerHit();
      achievementManager?.onEvent(
        const AchievementEvent(AchievementEventKind.playerHit),
      );
      audio.playHitImpact();
    };

    // Phase 5: now that player + hud both exist, wire pickup callbacks.
    // extraLife heals or pushes the cap; coins/gems bump the live HUD
    // counter and queue an async persistence write. ScoreManager
    // tallies on top so the run summary reads correctly.
    powerupManager.onExtraLife = player.gainLife;
    collectibleManager.onCoinCollected = (coin) {
      // Combo amplifies the currency value (coin tier × combo coin mult).
      final coinMult =
          powerupManager.coinMultiplier * scoreManager.currentCoinMultiplier;
      final value = (coin.value * coinMult).round();
      hud.sessionCoins += value;
      coinRepository.addCoins(value);
      scoreManager.onCoinCollected();
      audio.playCoinCollect(coin.coinType);
    };
    collectibleManager.onGemCollected = (gem) {
      // Gems award currency AND score; ScoreManager handles the score
      // side so combo + powerup multipliers compose in one place.
      final coinMult = powerupManager.coinMultiplier;
      final currency = (gem.value * coinMult).round();
      hud.sessionCoins += currency;
      coinRepository.addCoins(currency);
      scoreManager.onGemCollected(gem.value);
      achievementManager?.onEvent(
        const AchievementEvent(AchievementEventKind.gemCollected),
      );
      audio.playGemCollect(gem.gemType);
    };
    collectibleManager.onPowerupCollected = (powerup) {
      audio.playPowerupPickup(powerup.powerupType);
    };

    // The Flame camera follows the player vertically. The auto-scroll
    // feeling comes from the player constantly accelerating downward
    // under gravity — the camera tags along, and CameraSystem's
    // currentDepthMeters reads as "depth fallen".
    camera.follow(player, snap: true);
  }

  @override
  void update(double dt) {
    final clamped = dt > maxFrameDt ? maxFrameDt : dt;

    // Phase 14: feed the post-clamp dt into the perf monitor so the
    // rolling average tracks actual frame pacing (not the GC-pause
    // tail we already chopped off via maxFrameDt).
    performanceMonitor?.recordFrame(clamped);

    // Phase 10: advance the run-time clock + record a ghost sample.
    // Both gated on isAlive so a corpse doesn't keep ticking the ghost
    // past death and make a bogus best run.
    if (player.isAlive) {
      _runElapsed += clamped;
      ghostRunner?.recordSample(_runElapsed, player.position.x);
    }

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

    // Phase 5: drive collectible magnet + pickup detection from the
    // host (instead of inside the manager's update) so we always see
    // the freshest player position. Pruning runs against the same
    // viewport-top reference as obstacles for consistency.
    collectibleManager.runPickupPass(player.position, clamped);
    collectibleManager.pruneOffscreen(viewportTopY);

    // Phase 6: bill the player's depth into the score (delta-based,
    // so the score is monotonic and never refunds), then run a near-
    // miss pass against the live obstacle set. Each fresh near-miss
    // becomes a +50 score bonus and a floating "CLOSE!" popup.
    scoreManager.onDepthTick(cameraSystem.currentDepthMeters);
    final hits = nearMissDetector.detect(
      _playerHitbox(),
      obstacleManager.activeObstacles,
      clamped,
    );
    for (final o in hits) {
      scoreManager.onNearMiss();
      world.add(FloatingText(
        text: 'CLOSE! +${ScoreManager.nearMissBonus}',
        worldPosition: o.position.clone(),
        color: const Color(0xFFFFD600),
        fontSize: 13,
      ));
      audio.playNearMiss();
    }

    // Phase 4: tint the player's glow with the active zone accent. Done
    // every tick (cheap — just stashes a color) so zone-edge gradient
    // blends and the orb's color stay in sync without a callback.
    player.setZoneColor(zoneManager.currentZone.accentColor);

    // Phase 11: throttled wind whoosh. Pitch climbs with camera speed
    // so the audio reinforces "things are getting fast." Suppressed
    // while the player is mid-death-animation.
    if (player.isAlive) {
      _whooshCooldown -= clamped;
      if (_whooshCooldown <= 0) {
        _whooshCooldown = whooshIntervalSeconds;
        final speed = cameraSystem.currentSpeed;
        const baseSpeed = 200.0; // CameraSystem.baseSpeed
        const maxSpeed = 800.0; // CameraSystem.maxSpeed
        final t = ((speed - baseSpeed) / (maxSpeed - baseSpeed))
            .clamp(0.0, 1.0);
        // Map [0..1] → [0.5..2.0] so a slow fall is a low rumble and
        // top speed is a sharp whistle.
        final factor = 0.5 + t * 1.5;
        audio.playWhoosh(factor);
      }
    }

    // Phase 9: edge-trigger the run-summary callback the first frame
    // after the player dies. The callback owns the actual screen
    // transition; we just hand it the moment to fire.
    if (!_runEnded && player.isDead) {
      _runEnded = true;
      // Phase 11: shatter SFX on the same edge so it lands once per
      // run instead of looping the death animation.
      audio.playDeath();
      onRunEnded?.call();
    }

    super.update(clamped);
  }

  /// Phase 9: rebuild a fresh run on the same FreefallGame instance.
  /// Drops every in-flight obstacle/collectible, clears scoring state,
  /// and respawns the player at the start position. Cheaper than
  /// rebuilding FreefallGame because Flame's component tree + cached
  /// viewport stay live.
  void restartRun() {
    obstacleManager.clear();
    collectibleManager.clear();
    powerupManager.clear();
    scoreManager.reset();
    nearMissDetector.reset();
    cameraSystem.reset();
    obstacleSpawner.reset();
    collectibleSpawner.reset();
    hud.sessionCoins = 0;
    _runEnded = false;
    _runElapsed = 0;
    _whooshCooldown = whooshIntervalSeconds;
    achievementManager?.onRunStarted();
    ghostRunner?.onRunStarted();
    player.respawn();
    // Phase 11: respawn cue + restart the music for the starting zone
    // (Stratosphere). playZoneMusic dedups so a fresh instance whose
    // last music was already Stratosphere stays playing.
    audio.playRespawn();
    audio.playZoneMusic(zoneManager.currentZone.type);
  }

  /// Forward zone-enter events to the achievement manager. Maps the
  /// 5-zone canonical cycle to the manager's 0..4 zone-index space.
  void _emitZoneEvent(ZoneType zone) {
    final mgr = achievementManager;
    if (mgr == null) return;
    final idx = Zone.defaultCycle.indexWhere((z) => z.type == zone);
    mgr.onEvent(
      AchievementEvent(AchievementEventKind.zoneEntered, idx),
    );
  }

  /// Forward combo-increment events to the achievement manager.
  void _emitComboEvent(int combo) {
    achievementManager?.onEvent(
      AchievementEvent(AchievementEventKind.comboReached, combo),
    );
  }

  /// Total fixed-timestep ticks since startup. Useful for tests.
  int get totalSimSteps => gameLoop.totalSteps;

  /// World-space AABB of the player orb. Recomputed each frame; used
  /// by Phase-6 near-miss detection. Anchored at the player's center
  /// (Player.anchor == Anchor.center), so we offset by the radius.
  Rect _playerHitbox() {
    const r = Player.radius;
    return Rect.fromLTWH(
      player.position.x - r,
      player.position.y - r,
      r * 2,
      r * 2,
    );
  }
}
