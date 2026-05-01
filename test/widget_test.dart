// Phase-1 smoke tests for the core engine pieces.
//
// We don't pump the full FreefallGame widget here — booting Flame +
// trying to subscribe to sensors_plus inside a unit test is fragile.
// Instead we test the deterministic logic directly.

import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/components/coin.dart';
import 'package:freefall/components/obstacle.dart';
import 'package:freefall/components/particle.dart';
import 'package:freefall/game/game_loop.dart';
import 'package:freefall/systems/camera_system.dart';
import 'package:freefall/systems/coin_system.dart';
import 'package:freefall/systems/collision_system.dart';
import 'package:freefall/systems/gravity_system.dart';
import 'package:freefall/systems/input_system.dart';
import 'package:freefall/systems/object_pool.dart';
import 'package:freefall/systems/obstacle_system.dart';
import 'package:freefall/systems/particle_system.dart';
import 'package:freefall/systems/player_system.dart';

void main() {
  group('GravitySystem', () {
    test('accelerates downward and reaches a drag-bounded steady state', () {
      final g = GravitySystem();
      var v = Vector2.zero();
      // 200 frames at 1/60s is well past the time constant of the drag.
      for (int i = 0; i < 200; i++) {
        v = g.applyGravity(v, 1 / 60);
      }
      // Steady-state: gravity * dt == v * drag, so
      // v == (800/60) / 0.02 ≈ 667 px/s at 60 Hz. The 1200 px/s
      // terminalVelocity is a safety cap that doesn't engage during
      // normal falling.
      expect(v.y, greaterThan(550));
      expect(v.y, lessThan(800));
      expect(v.y, lessThanOrEqualTo(GravitySystem.terminalVelocity));
    });

    test('terminal velocity caps absurd input speeds', () {
      final g = GravitySystem();
      final v = g.applyGravity(Vector2(0, 5000), 1 / 60);
      expect(v.y, lessThanOrEqualTo(GravitySystem.terminalVelocity));
    });

    test('does not mutate the input vector', () {
      final g = GravitySystem();
      final v = Vector2(0, 100);
      final out = g.applyGravity(v, 1 / 60);
      expect(v.y, 100);
      expect(out.y, isNot(100));
    });
  });

  group('CameraSystem', () {
    test('starts at base speed and ramps every 500m', () {
      final c = CameraSystem();
      expect(c.currentSpeed, CameraSystem.baseSpeed);

      // Step 1 second at base speed: 200 px/s = 20m. Not enough to ramp.
      c.update(1.0);
      expect(c.currentSpeed, CameraSystem.baseSpeed);

      // Force depth past 500m by accumulating 25 seconds at base speed.
      // That's 5000 px == 500m exactly, just past the first step.
      for (int i = 0; i < 25 * 60; i++) {
        c.update(1 / 60);
      }
      expect(c.currentDepthMeters, greaterThan(500));
      expect(c.currentSpeed, greaterThan(CameraSystem.baseSpeed));
    });

    test('caps at maxSpeed', () {
      final c = CameraSystem();
      // 60 seconds is enough to hit max with the upper-bound logic.
      for (int i = 0; i < 60 * 60 * 10; i++) {
        c.update(1 / 60);
      }
      expect(c.currentSpeed, lessThanOrEqualTo(CameraSystem.maxSpeed));
    });
  });

  group('CollisionSystem', () {
    test('queryRect returns overlapping objects only', () {
      final cs = CollisionSystem();
      cs.insertObject('a', const Rect.fromLTWH(0, 0, 50, 50));
      cs.insertObject('b', const Rect.fromLTWH(200, 200, 50, 50));

      final hits = cs.queryRect(const Rect.fromLTWH(10, 10, 10, 10));
      expect(hits, contains('a'));
      expect(hits, isNot(contains('b')));
    });

    test('removeObject clears it from every cell', () {
      final cs = CollisionSystem();
      cs.insertObject('a', const Rect.fromLTWH(0, 0, 250, 250));
      expect(cs.queryRect(const Rect.fromLTWH(150, 150, 10, 10)), contains('a'));
      cs.removeObject('a');
      expect(cs.queryRect(const Rect.fromLTWH(150, 150, 10, 10)), isEmpty);
    });

    test('clearAndRebuild swaps in fresh state', () {
      final cs = CollisionSystem();
      cs.insertObject('a', const Rect.fromLTWH(0, 0, 50, 50));
      cs.clearAndRebuild({
        'b': const Rect.fromLTWH(200, 200, 50, 50),
      });
      expect(cs.queryRect(const Rect.fromLTWH(0, 0, 60, 60)), isEmpty);
      expect(
        cs.queryRect(const Rect.fromLTWH(210, 210, 10, 10)),
        contains('b'),
      );
    });
  });

  group('ObjectPool', () {
    test('reuses released objects', () {
      final pool = ObjectPool<Coin>(factory: Coin.new, initialSize: 2);
      final a = pool.acquire();
      final b = pool.acquire();
      pool.release(a);
      final c = pool.acquire();
      expect(identical(a, c) || identical(b, c), isTrue);
    });

    test('respects maxSize when releasing', () {
      final pool = ObjectPool<Coin>(factory: Coin.new, maxSize: 1);
      final a = pool.acquire();
      final b = pool.acquire();
      pool.release(a);
      pool.release(b); // dropped on the floor
      expect(pool.freeCount, 1);
    });

    test('typed pools wire factory + reset', () {
      final op = ObstaclePool();
      final o = op.acquire();
      expect(o, isA<Obstacle>());
      o.id = 'foo';
      op.release(o);
      // After release+reacquire, onAcquire's reset should have wiped state.
      final o2 = op.acquire();
      expect(o2.id, isEmpty);

      final pp = ParticlePool();
      expect(pp.acquire(), isA<Particle>());

      final cp = CoinPool();
      expect(cp.acquire(), isA<Coin>());
    });
  });

  group('GameLoop', () {
    test('runs N fixed steps for an N/60s tick', () {
      final loop = GameLoop.standard(
        input: InputSystem(),
        gravity: GravitySystem(),
        camera: CameraSystem(),
        collision: CollisionSystem(),
        player: PlayerSystem(),
        obstacle: ObstacleSystem(),
        coin: CoinSystem(),
        particle: ParticleSystem(),
      );
      loop.tick(1.0); // 60 steps' worth of time
      // Spiral-of-death cap is 5 — and a 1.0s tick is well past that.
      expect(loop.totalSteps, GameLoop.maxStepsPerFrame);

      final loop2 = GameLoop.standard(
        input: InputSystem(),
        gravity: GravitySystem(),
        camera: CameraSystem(),
        collision: CollisionSystem(),
        player: PlayerSystem(),
        obstacle: ObstacleSystem(),
        coin: CoinSystem(),
        particle: ParticleSystem(),
      );
      // 3 frames at exactly 1/60 should yield exactly 3 sim steps.
      loop2.tick(1 / 60);
      loop2.tick(1 / 60);
      loop2.tick(1 / 60);
      expect(loop2.totalSteps, 3);
    });

    test('registers all 8 canonical systems', () {
      final loop = GameLoop.standard(
        input: InputSystem(),
        gravity: GravitySystem(),
        camera: CameraSystem(),
        collision: CollisionSystem(),
        player: PlayerSystem(),
        obstacle: ObstacleSystem(),
        coin: CoinSystem(),
        particle: ParticleSystem(),
      );
      expect(loop.systemCount, 8);
    });
  });
}
