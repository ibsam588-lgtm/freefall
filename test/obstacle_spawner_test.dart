// Phase-3 obstacle spawner & manager tests.
//
// Both ObstacleSpawner and ObstacleManager are designed to run headless
// — the manager's attach/detach hooks are injected, and the spawner
// drives lookahead off the camera + difficulty scaler instead of
// rigging up a Flame world. So we exercise the structural rules
// (gap-floor, gap-wall separation, zone-appropriate mixing, offscreen
// pruning) directly without spinning up a FlameGame.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/components/hazards/jellyfish.dart';
import 'package:freefall/components/hazards/lava_jet.dart';
import 'package:freefall/components/hazards/lightning_bolt.dart';
import 'package:freefall/components/hazards/stalactite.dart';
import 'package:freefall/components/hazards/wrecking_ball.dart';
import 'package:freefall/components/obstacles/breakable_platform.dart';
import 'package:freefall/components/obstacles/game_obstacle.dart';
import 'package:freefall/components/obstacles/gap_wall.dart';
import 'package:freefall/components/obstacles/magnet_obstacle.dart';
import 'package:freefall/components/obstacles/moving_block.dart';
import 'package:freefall/components/obstacles/rotating_obstacle.dart';
import 'package:freefall/components/obstacles/speed_gate.dart';
import 'package:freefall/components/obstacles/static_platform.dart';
import 'package:freefall/models/zone.dart';
import 'package:freefall/systems/camera_system.dart';
import 'package:freefall/systems/collision_system.dart';
import 'package:freefall/systems/difficulty_scaler.dart';
import 'package:freefall/systems/obstacle_manager.dart';
import 'package:freefall/systems/obstacle_spawner.dart';
import 'package:freefall/systems/zone_manager.dart';

const double _playWidth = 414;
const double _viewportHeight = 896;

({
  ObstacleSpawner spawner,
  ObstacleManager manager,
  CameraSystem camera,
  ZoneManager zone,
  DifficultyScaler scaler,
}) _build({int seed = 1, double depthMeters = 0}) {
  final zone = ZoneManager();
  zone.update(depthMeters);
  final scaler = DifficultyScaler(zoneManager: zone);
  final camera = CameraSystem();
  // CameraSystem doesn't expose an explicit "set depth" method, but the
  // spawner only reads currentSpeed and playerWorldPosition off it; we
  // can drive both directly from tests without ticking the system.
  camera.playerWorldPosition.setFrom(Vector2(_playWidth / 2, 0));
  final manager = ObstacleManager();
  final spawner = ObstacleSpawner(
    cameraSystem: camera,
    difficultyScaler: scaler,
    zoneManager: zone,
    manager: manager,
    playWidth: _playWidth,
    viewportHeight: _viewportHeight,
    rng: math.Random(seed),
  );
  return (
    spawner: spawner,
    manager: manager,
    camera: camera,
    zone: zone,
    scaler: scaler,
  );
}

void main() {
  group('ObstacleSpawner', () {
    test('spawns obstacles up to the lookahead and stops', () {
      final h = _build();
      h.spawner.spawnUntil(2000);
      expect(h.manager.activeCount, greaterThan(0));
      // Every spawn lands at or before the lookahead.
      for (final o in h.manager.activeObstacles) {
        expect(o.position.y <= 2000 + 50, isTrue,
            reason: 'obstacle at ${o.position.y} past lookahead 2000');
      }
      // Cursor advanced past the lookahead.
      expect(h.spawner.nextSpawnY, greaterThan(2000));
    });

    test('subsequent calls only emit obstacles below the new lookahead', () {
      final h = _build();
      h.spawner.spawnUntil(1500);
      final firstBatchCount = h.manager.activeCount;
      final cursor1 = h.spawner.nextSpawnY;

      h.spawner.spawnUntil(1500);
      // Already past 1500, so nothing new spawned.
      expect(h.manager.activeCount, equals(firstBatchCount));
      expect(h.spawner.nextSpawnY, equals(cursor1));

      h.spawner.spawnUntil(3000);
      expect(h.manager.activeCount, greaterThan(firstBatchCount));
    });

    test('every gap wall has gap >= 60px (the hard floor)', () {
      // Advance into a deep cycle so DifficultyScaler tries to push the
      // gap below 60. The clamp must hold.
      final h = _build(seed: 2, depthMeters: 4500);
      // Force the cycle multiplier high enough that raw gap goes negative.
      h.zone.update(50000);

      h.spawner.spawnUntil(20000);
      final walls =
          h.manager.activeObstacles.whereType<GapWall>().toList();
      expect(walls, isNotEmpty);
      for (final w in walls) {
        expect(w.gapWidth, greaterThanOrEqualTo(GapWall.minGapWidth));
      }
    });

    test('no two gap walls within 300px of each other', () {
      // Run several different seeds — if the rule held under any
      // construction, ordinary RNG would still produce both adjacent
      // gap walls and gaps where the rule actually fires.
      for (int seed = 0; seed < 8; seed++) {
        final h = _build(seed: seed);
        h.spawner.spawnUntil(8000);
        final wallYs = h.manager.activeObstacles
            .whereType<GapWall>()
            .map((w) => w.position.y)
            .toList()
          ..sort();
        for (int i = 1; i < wallYs.length; i++) {
          final delta = wallYs[i] - wallYs[i - 1];
          expect(delta, greaterThanOrEqualTo(300),
              reason: 'seed=$seed gap walls at ${wallYs[i - 1]} & ${wallYs[i]}');
        }
      }
    });

    test('zones produce zone-appropriate hazards', () {
      // Stratosphere can produce LightningBolt but not Jellyfish.
      final strat = _build(seed: 11, depthMeters: 0);
      strat.spawner.spawnUntil(8000);
      final stratHasLightning =
          strat.manager.activeObstacles.any((o) => o is LightningBolt);
      final stratHasJellyfish =
          strat.manager.activeObstacles.any((o) => o is Jellyfish);
      expect(stratHasLightning, isTrue);
      expect(stratHasJellyfish, isFalse);

      // Deep Ocean can produce Jellyfish but not LavaJet.
      final ocean = _build(seed: 13, depthMeters: 3500);
      ocean.spawner.spawnUntil(20000);
      final oceanHasJelly =
          ocean.manager.activeObstacles.any((o) => o is Jellyfish);
      final oceanHasLava =
          ocean.manager.activeObstacles.any((o) => o is LavaJet);
      expect(oceanHasJelly, isTrue);
      expect(oceanHasLava, isFalse);

      // Core can produce LavaJet but not LightningBolt.
      final core = _build(seed: 17, depthMeters: 4500);
      core.spawner.spawnUntil(20000);
      final coreHasLava =
          core.manager.activeObstacles.any((o) => o is LavaJet);
      final coreHasLightning =
          core.manager.activeObstacles.any((o) => o is LightningBolt);
      expect(coreHasLava, isTrue);
      expect(coreHasLightning, isFalse);
    });

    test('spacing between successive spawns honors the floor', () {
      final h = _build(seed: 3);
      h.spawner.spawnUntil(6000);
      final ys = h.manager.activeObstacles.map((o) => o.position.y).toList()
        ..sort();
      for (int i = 1; i < ys.length; i++) {
        expect(ys[i] - ys[i - 1],
            greaterThanOrEqualTo(ObstacleSpawner.minSpawnSpacing - 0.001));
      }
    });

    test('reset() clears spawn cursor and gap-wall memory', () {
      final h = _build();
      h.spawner.spawnUntil(3000);
      expect(h.spawner.nextSpawnY, greaterThan(_viewportHeight));
      h.spawner.reset();
      expect(h.spawner.nextSpawnY, equals(_viewportHeight));
      expect(h.spawner.lastGapWallY, lessThan(-1e8));
    });
  });

  group('ObstacleManager', () {
    test('add() fires the spawn hook and tracks the obstacle', () {
      final spawned = <GameObstacle>[];
      final mgr = ObstacleManager(onSpawn: spawned.add);
      final p = StaticPlatform(
        obstacleId: 'a',
        worldPosition: Vector2(100, 100),
        zone: Zone.defaultCycle.first,
      );
      mgr.add(p);
      expect(spawned, contains(p));
      expect(mgr.activeCount, equals(1));
      expect(mgr.activeObstacles, contains(p));
    });

    test('add() is idempotent for the same instance', () {
      final mgr = ObstacleManager();
      final p = StaticPlatform(
        obstacleId: 'a',
        worldPosition: Vector2(100, 100),
        zone: Zone.defaultCycle.first,
      );
      mgr.add(p);
      mgr.add(p);
      expect(mgr.activeCount, equals(1));
    });

    test('pruneOffscreen removes obstacles 200px above viewport', () {
      final detached = <GameObstacle>[];
      final mgr = ObstacleManager(onDespawn: detached.add);
      // Three obstacles at world Y = 0, 500, 1000.
      final low = StaticPlatform(
        obstacleId: 'low',
        worldPosition: Vector2(100, 0),
        zone: Zone.defaultCycle.first,
      );
      final mid = StaticPlatform(
        obstacleId: 'mid',
        worldPosition: Vector2(100, 500),
        zone: Zone.defaultCycle.first,
      );
      final high = StaticPlatform(
        obstacleId: 'high',
        worldPosition: Vector2(100, 1000),
        zone: Zone.defaultCycle.first,
      );
      mgr.add(low);
      mgr.add(mid);
      mgr.add(high);

      // Viewport top at y=300. Threshold = 300 - 200 = 100. The "low"
      // obstacle at y=0 has bottomY=10 < 100 → pruned. Others stay.
      mgr.pruneOffscreen(300);
      expect(mgr.activeCount, equals(2));
      expect(detached, contains(low));
      expect(detached, isNot(contains(mid)));
      expect(detached, isNot(contains(high)));
    });

    test('clear() detaches every active obstacle', () {
      final detached = <GameObstacle>[];
      final mgr = ObstacleManager(onDespawn: detached.add);
      for (int i = 0; i < 5; i++) {
        mgr.add(StaticPlatform(
          obstacleId: 'p$i',
          worldPosition: Vector2(100, i * 100.0),
          zone: Zone.defaultCycle.first,
        ));
      }
      mgr.clear();
      expect(mgr.activeCount, equals(0));
      expect(detached.length, equals(5));
    });
  });

  group('Obstacle hit effects', () {
    test('static platform deals damage', () {
      final p = StaticPlatform(
        obstacleId: 'a',
        worldPosition: Vector2(100, 100),
        zone: Zone.defaultCycle.first,
      );
      expect(p.onPlayerHit(), equals(ObstacleHitEffect.damage));
    });

    test('breakable platform damages once then returns none', () {
      final p = BreakablePlatform(
        obstacleId: 'b',
        worldPosition: Vector2(100, 100),
        zone: Zone.defaultCycle.first,
      );
      expect(p.onPlayerHit(), equals(ObstacleHitEffect.damage));
      expect(p.onPlayerHit(), equals(ObstacleHitEffect.none));
    });

    test('breakable platform fully crumbles after 0.5s', () {
      final p = BreakablePlatform(
        obstacleId: 'b',
        worldPosition: Vector2(100, 100),
        zone: Zone.defaultCycle.first,
      );
      p.onPlayerHit();
      expect(p.isGone, isFalse);
      // Walk update in fixed steps without going through Flame's
      // mountedness-checking onLoad path: BreakablePlatform.update only
      // touches its own crumble state.
      for (int i = 0; i < 60; i++) {
        p.update(1 / 60);
      }
      expect(p.crumbleProgress, closeTo(1.0, 0.05));
      expect(p.isGone, isTrue);
    });

    test('speed gate is a one-shot boost', () {
      final g = SpeedGate(
        obstacleId: 'g',
        worldPosition: Vector2(100, 100),
      );
      expect(g.onPlayerHit(), equals(ObstacleHitEffect.boost));
      expect(g.isConsumed, isTrue);
      expect(g.onPlayerHit(), equals(ObstacleHitEffect.none));
    });

    test('jellyfish stuns and rearms with cooldown', () {
      final j = Jellyfish(
        obstacleId: 'j',
        worldPosition: Vector2(100, 100),
        phase: 0,
      );
      expect(j.onPlayerHit(), equals(ObstacleHitEffect.stun));
      // Immediately again should be no-op due to rearm cooldown.
      expect(j.onPlayerHit(), equals(ObstacleHitEffect.none));
      // Step long enough for rearm.
      for (int i = 0; i < 80; i++) {
        j.update(1 / 60);
      }
      expect(j.onPlayerHit(), equals(ObstacleHitEffect.stun));
    });

    test('lightning is lethal only when active', () {
      final bolt = LightningBolt(
        obstacleId: 'l',
        worldPosition: Vector2(100, 100),
        initialPhase: 0,
      );
      expect(bolt.isActive, isTrue);
      expect(bolt.onPlayerHit(), equals(ObstacleHitEffect.kill));
      // Advance past flashDuration into cooldown.
      for (int i = 0; i < 30; i++) {
        bolt.update(1 / 60);
      }
      expect(bolt.isActive, isFalse);
      // intersects() short-circuits during cooldown so the player can't
      // even contact-trigger onPlayerHit. Verify intersect returns false.
      expect(
        bolt.intersects(const Rect.fromLTWH(95, 100, 20, 20)),
        isFalse,
      );
    });

    test('stalactite triggers when player is within 200px horizontal', () {
      final s = Stalactite(
        obstacleId: 's',
        worldPosition: Vector2(200, 100),
      );
      expect(s.isFalling, isFalse);

      // 250px away — no trigger.
      s.considerTrigger(Vector2(450, 50));
      expect(s.isFalling, isFalse);

      // 100px away — triggers.
      s.considerTrigger(Vector2(300, 50));
      expect(s.isFalling, isTrue);

      // Idempotent after triggered.
      s.considerTrigger(Vector2(0, 0));
      expect(s.isFalling, isTrue);
    });

    test('moving block reverses at patrol bounds', () {
      final b = MovingBlock(
        obstacleId: 'm',
        worldPosition: Vector2(50, 100),
        zone: Zone.defaultCycle.first,
        minX: 30,
        maxX: 200,
        initialSpeed: -200,
      );
      // Walk forward — block should hit minX edge and flip sign.
      for (int i = 0; i < 60; i++) {
        b.update(1 / 60);
      }
      expect(b.speedX, greaterThan(0),
          reason: 'block should reverse off the minX wall');
      expect(b.position.x, greaterThanOrEqualTo(30));
    });

    test('magnet pull is zero outside radius and nonzero inside', () {
      final m = MagnetObstacle(
        obstacleId: 'mag',
        worldPosition: Vector2(200, 200),
        zone: Zone.defaultCycle.first,
      );
      // 1000px away — outside.
      final far = m.pullForceOn(Vector2(1200, 200));
      expect(far.length, equals(0));
      // 50px away — inside.
      final near = m.pullForceOn(Vector2(150, 200));
      expect(near.length, greaterThan(0));
      // Force points toward the magnet center.
      expect(near.x, greaterThan(0));
    });

    test('rotating obstacle update advances rotation', () {
      final r = RotatingObstacle(
        obstacleId: 'r',
        worldPosition: Vector2(100, 100),
        zone: Zone.defaultCycle.first,
        armCount: 3,
        angularSpeed: 2.0,
      );
      final before = r.rotation;
      r.update(0.5);
      // 2 rad/s * 0.5 s = 1 rad of rotation.
      expect(r.rotation - before, closeTo(1.0, 0.01));
    });

    test('wrecking ball position swings around its anchor', () {
      final w = WreckingBall(
        obstacleId: 'w',
        anchorPosition: Vector2(200, 100),
        initialPhase: 0,
      );
      final p0 = w.position.clone();
      for (int i = 0; i < 30; i++) {
        w.update(1 / 60);
      }
      expect(w.position, isNot(equals(p0)));
      // Distance from anchor should remain ~chain length.
      final d = (w.position - Vector2(200, 100)).length;
      expect(d, closeTo(WreckingBall.chainLength, 1.0));
    });

    test('lava jet only damages while firing', () {
      final j = LavaJet(
        obstacleId: 'lj',
        worldPosition: Vector2(200, 200),
        initialPhase: 0,
      );
      expect(j.isFiring, isTrue);
      // The cone covers a vertical strip near the vent — verify a rect
      // inside the cone hits while firing.
      const hitRect = Rect.fromLTWH(180, 100, 20, 20);
      expect(j.intersects(hitRect), isTrue);

      // Advance into cooldown.
      for (int i = 0; i < 90; i++) {
        j.update(1 / 60);
      }
      expect(j.isFiring, isFalse);
      expect(j.intersects(hitRect), isFalse);
    });
  });

  group('CollisionSystem.queryPlayerHits', () {
    test('returns only obstacles whose intersects() returns true', () {
      final cs = CollisionSystem();
      final hit = StaticPlatform(
        obstacleId: 'hit',
        worldPosition: Vector2(100, 100),
        zone: Zone.defaultCycle.first,
        width: 100,
      );
      final miss = StaticPlatform(
        obstacleId: 'miss',
        worldPosition: Vector2(400, 400),
        zone: Zone.defaultCycle.first,
        width: 100,
      );
      // Player rect overlapping the first platform only.
      final result = cs.queryPlayerHits(
        const Rect.fromLTWH(80, 90, 30, 30),
        [hit, miss],
      );
      expect(result, contains(hit));
      expect(result, isNot(contains(miss)));
    });

    test('uses GapWall.intersects so the gap is open to the player', () {
      final cs = CollisionSystem();
      final wall = GapWall(
        obstacleId: 'gap',
        centerY: 100,
        playWidth: 414,
        gapCenterX: 207,
        rawGapWidth: 120,
        zone: Zone.defaultCycle.first,
      );
      // Player passing through the gap — no hit even though the wall's
      // bounding box spans the full width.
      final inGap = cs.queryPlayerHits(
        const Rect.fromLTWH(190, 95, 34, 30),
        [wall],
      );
      expect(inGap, isEmpty);
      // Player against the left wall — hit.
      final onWall = cs.queryPlayerHits(
        const Rect.fromLTWH(20, 95, 34, 30),
        [wall],
      );
      expect(onWall, contains(wall));
    });
  });
}
