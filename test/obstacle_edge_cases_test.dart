// Phase-15 obstacle + object-pool edge cases.
//
// Already covered: obstacle_spawner_test exercises the spawner's
// distribution + zone gating; performance_monitor_test covers
// PoolStats. This file fills in:
//   * GapWall enforces the 60px minimum even when the spawner asks
//     for a tiny gap (extreme difficulty),
//   * an ObjectPool never hands out the same instance to two
//     concurrent acquires (the free list pops, the outstanding list
//     tracks),
//   * MagnetObstacle.pullForceOn caps at maxPullForce and falls off
//     linearly with distance, returning zero outside the radius,
//   * BreakablePlatform is a one-shot — the first hit triggers the
//     crumble and damages; later contacts return
//     ObstacleHitEffect.none even before the platform is fully gone.

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/components/obstacles/breakable_platform.dart';
import 'package:freefall/components/obstacles/game_obstacle.dart';
import 'package:freefall/components/obstacles/gap_wall.dart';
import 'package:freefall/components/obstacles/magnet_obstacle.dart';
import 'package:freefall/components/particle.dart';
import 'package:freefall/models/zone.dart';
import 'package:freefall/systems/object_pool.dart';

const Zone _zone = Zone(
  type: ZoneType.stratosphere,
  name: 'Stratosphere',
  topColor: Color(0xFF000000),
  bottomColor: Color(0xFF000000),
  accentColor: Color(0xFF000000),
  startDepth: 0,
  endDepth: 1000,
);

void main() {
  group('GapWall minimum width', () {
    test('clamps below 60px to 60px even at extreme difficulty', () {
      final wall = GapWall(
        obstacleId: 'test',
        centerY: 0,
        playWidth: 414,
        gapCenterX: 207,
        rawGapWidth: 10,
        zone: _zone,
      );
      expect(wall.gapWidth, GapWall.minGapWidth);
    });

    test('clamps a negative gap to 60px (defensive)', () {
      final wall = GapWall(
        obstacleId: 'test',
        centerY: 0,
        playWidth: 414,
        gapCenterX: 207,
        rawGapWidth: -50,
        zone: _zone,
      );
      expect(wall.gapWidth, GapWall.minGapWidth);
    });

    test('honors a generous gap above the floor', () {
      final wall = GapWall(
        obstacleId: 'test',
        centerY: 0,
        playWidth: 414,
        gapCenterX: 207,
        rawGapWidth: 200,
        zone: _zone,
      );
      expect(wall.gapWidth, 200);
    });

    test('a player-sized rect passes through a min-gap centered on '
        'the play column', () {
      final wall = GapWall(
        obstacleId: 'test',
        centerY: 0,
        playWidth: 414,
        gapCenterX: 207,
        rawGapWidth: 1, // floors to 60
        zone: _zone,
      );
      // Player AABB is 36x36 (Player.radius = 18). Centered in the gap.
      const playerRect =
          Rect.fromLTWH(207 - 18, -18, 36, 36);
      expect(wall.intersects(playerRect), isFalse,
          reason: '36px-wide player should clear a 60px gap');
    });

    test('the same player-sized rect is blocked at the wall edge', () {
      final wall = GapWall(
        obstacleId: 'test',
        centerY: 0,
        playWidth: 414,
        gapCenterX: 207,
        rawGapWidth: 1,
        zone: _zone,
      );
      // Far left of the play column — square in the wall.
      const playerRect = Rect.fromLTWH(0, -18, 36, 36);
      expect(wall.intersects(playerRect), isTrue);
    });
  });

  group('ObjectPool concurrency', () {
    test('two acquires return distinct instances', () {
      final pool = ObjectPool<Particle>(
        factory: Particle.new,
        initialSize: 2,
      );
      final a = pool.acquire();
      final b = pool.acquire();
      expect(identical(a, b), isFalse);
      expect(pool.stats.active, 2);
    });

    test('release-then-reacquire reuses the freshly-released instance',
        () {
      final pool = ObjectPool<Particle>(
        factory: Particle.new,
        initialSize: 1,
      );
      final a = pool.acquire();
      pool.release(a);
      final b = pool.acquire();
      expect(identical(a, b), isTrue,
          reason: 'pool should hand back the recycled instance, not '
              'allocate a fresh one');
      expect(pool.stats.totalCreated, 1);
    });

    test('high-water concurrency: 10 acquires beyond initialSize all '
        'return distinct instances', () {
      final pool = ObjectPool<Particle>(
        factory: Particle.new,
        initialSize: 2,
      );
      final acquired = <Particle>[];
      for (var i = 0; i < 10; i++) {
        acquired.add(pool.acquire());
      }
      expect(acquired.toSet().length, 10);
      expect(pool.stats.active, 10);
      expect(pool.stats.totalCreated, 10);
    });
  });

  group('MagnetObstacle pull force', () {
    test('returns zero when player is outside the pull radius', () {
      final magnet = MagnetObstacle(
        obstacleId: 'm',
        worldPosition: Vector2.zero(),
        zone: _zone,
      );
      // Far away — well outside the 150px radius.
      final force = magnet.pullForceOn(Vector2(500, 0));
      expect(force.length, 0.0);
    });

    test('caps at maxPullForce when player is at the magnet center',
        () {
      final magnet = MagnetObstacle(
        obstacleId: 'm',
        worldPosition: Vector2.zero(),
        zone: _zone,
      );
      // Just barely off the center so the normalize doesn't go NaN.
      final force = magnet.pullForceOn(Vector2(0.01, 0));
      expect(force.length, lessThanOrEqualTo(MagnetObstacle.maxPullForce));
      expect(force.length, greaterThan(MagnetObstacle.maxPullForce * 0.99));
    });

    test('falls off linearly with distance', () {
      final magnet = MagnetObstacle(
        obstacleId: 'm',
        worldPosition: Vector2.zero(),
        zone: _zone,
      );
      // At 75px (half-radius), expect roughly half the max pull.
      final mid = magnet.pullForceOn(Vector2(75, 0));
      expect(mid.length,
          closeTo(MagnetObstacle.maxPullForce * 0.5, 1.0));
      // At 150px (edge), force should be zero (the multiplier hits 0).
      final edge = magnet.pullForceOn(Vector2(149, 0));
      expect(edge.length, lessThan(MagnetObstacle.maxPullForce * 0.05));
    });
  });

  group('BreakablePlatform consume semantics', () {
    test('first hit damages and starts the crumble timer', () {
      final platform = BreakablePlatform(
        obstacleId: 'p',
        worldPosition: Vector2(100, 100),
        zone: _zone,
        width: 100,
      );
      expect(platform.crumbleProgress, 0);
      final effect = platform.onPlayerHit();
      expect(effect, ObstacleHitEffect.damage);
    });

    test('subsequent hits return none (one-shot consume)', () {
      final platform = BreakablePlatform(
        obstacleId: 'p',
        worldPosition: Vector2(100, 100),
        zone: _zone,
        width: 100,
      );
      // First hit: real damage.
      expect(platform.onPlayerHit(), ObstacleHitEffect.damage);
      // Second hit: none, even before the platform is fully gone.
      expect(platform.crumbleProgress, lessThan(1.0));
      expect(platform.onPlayerHit(), ObstacleHitEffect.none);
      // Third for good measure.
      expect(platform.onPlayerHit(), ObstacleHitEffect.none);
    });

    test('crumble progresses with dt and isGone flips at 1.0', () {
      final platform = BreakablePlatform(
        obstacleId: 'p',
        worldPosition: Vector2(100, 100),
        zone: _zone,
        width: 100,
      );
      platform.onPlayerHit();
      // Half a second matches the crumbleDuration constant.
      platform.update(BreakablePlatform.crumbleDuration);
      expect(platform.crumbleProgress, closeTo(1.0, 1e-9));
      expect(platform.isGone, isTrue);
    });

    test('a fully-gone platform reports no intersection', () {
      final platform = BreakablePlatform(
        obstacleId: 'p',
        worldPosition: Vector2(100, 100),
        zone: _zone,
        width: 100,
      );
      platform.onPlayerHit();
      platform.update(BreakablePlatform.crumbleDuration);
      const playerRect = Rect.fromLTWH(60, 90, 80, 20); // overlapping
      expect(platform.intersects(playerRect), isFalse);
    });
  });
}
