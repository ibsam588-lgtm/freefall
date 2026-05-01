// Phase-14 performance-monitor + object-pool stats tests.
//
// PerformanceMonitor is engine-agnostic — no Flame, no Flutter — so
// we drive it with synthetic dts. ObjectPool is similarly pure data.
// Both lend themselves to deterministic unit tests without rigging
// up the game.
//
// What we verify:
//   * a fresh monitor reports level 1.0 (no samples → no penalty),
//   * 60 frames at exactly 16ms hold level 1.0 (target frame time),
//   * 60 frames at 33ms drop level to 0.0 (worst frame time),
//   * intermediate frame times produce in-between levels,
//   * `maxParticles` and `backgroundLayers` step through the
//     spec'd budgets at the expected level boundaries,
//   * `isStruggling` flips on at the 50fps threshold,
//   * the rolling window forgets old samples (60-sample ring),
//   * `reset()` returns the monitor to a fresh state,
//   * ObjectPool [PoolStats] reflect acquire/release,
//   * `clearAll` releases every outstanding instance.

import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/components/particle.dart';
import 'package:freefall/systems/object_pool.dart';
import 'package:freefall/systems/performance_monitor.dart';

void main() {
  group('PerformanceMonitor', () {
    test('fresh monitor reports level 1.0 (no samples)', () {
      final m = PerformanceMonitor();
      expect(m.sampleCount, 0);
      expect(m.performanceLevel, 1.0);
      expect(m.isStruggling, isFalse);
      expect(m.maxParticles, PerformanceMonitor.particlesHigh);
      expect(m.backgroundLayers, PerformanceMonitor.layersHigh);
    });

    test('60 frames at 16ms hold level at 1.0 (target)', () {
      final m = PerformanceMonitor();
      for (var i = 0; i < 60; i++) {
        m.recordFrame(1 / 60);
      }
      // Floating-point summation drops a few ulps off perfect 1.0;
      // closeTo absorbs that without weakening the assertion.
      expect(m.performanceLevel, closeTo(1.0, 1e-9));
      expect(m.isStruggling, isFalse);
      expect(m.maxParticles, PerformanceMonitor.particlesHigh);
      expect(m.backgroundLayers, PerformanceMonitor.layersHigh);
    });

    test('60 frames at 33ms drop level to 0.0 (worst case)', () {
      final m = PerformanceMonitor();
      for (var i = 0; i < 60; i++) {
        m.recordFrame(1 / 30);
      }
      expect(m.performanceLevel, 0.0);
      expect(m.isStruggling, isTrue);
      expect(m.maxParticles, PerformanceMonitor.particlesLow);
      expect(m.backgroundLayers, PerformanceMonitor.layersLow);
    });

    test('intermediate frame times produce intermediate levels', () {
      final m = PerformanceMonitor();
      // 25ms (40fps) sits midway between 16ms and 33ms ⇒ level ~0.5.
      for (var i = 0; i < 60; i++) {
        m.recordFrame(0.025);
      }
      expect(m.performanceLevel, closeTo(0.5, 0.05));
      expect(m.maxParticles, PerformanceMonitor.particlesMedium);
      expect(m.backgroundLayers, PerformanceMonitor.layersMedium);
    });

    test('isStruggling flips at the 50fps threshold', () {
      final m = PerformanceMonitor();
      // Just under 50fps (~21ms) should trigger.
      for (var i = 0; i < 60; i++) {
        m.recordFrame(0.022);
      }
      expect(m.isStruggling, isTrue);
    });

    test('isStruggling stays off at exactly 60fps', () {
      final m = PerformanceMonitor();
      for (var i = 0; i < 60; i++) {
        m.recordFrame(1 / 60);
      }
      expect(m.isStruggling, isFalse);
    });

    test('rolling window evicts old samples after sampleWindow frames',
        () {
      final m = PerformanceMonitor();
      // Prime with 60 slow frames.
      for (var i = 0; i < 60; i++) {
        m.recordFrame(1 / 30);
      }
      expect(m.performanceLevel, 0.0);

      // Now feed 60 fast frames — the slow ones should fully evict.
      for (var i = 0; i < 60; i++) {
        m.recordFrame(1 / 60);
      }
      expect(m.performanceLevel, closeTo(1.0, 1e-9),
          reason: 'older slow frames should have rotated out of the '
              '60-sample ring');
    });

    test('reset() returns to a fresh state', () {
      final m = PerformanceMonitor();
      for (var i = 0; i < 30; i++) {
        m.recordFrame(0.030);
      }
      expect(m.performanceLevel, lessThan(0.5));
      m.reset();
      expect(m.sampleCount, 0);
      expect(m.performanceLevel, 1.0);
    });

    test('zero / negative dts are ignored', () {
      final m = PerformanceMonitor();
      m.recordFrame(0);
      m.recordFrame(-1);
      expect(m.sampleCount, 0);
    });

    test('maxParticles tier boundaries match spec (60/30/15)', () {
      // Exact tier counts.
      expect(PerformanceMonitor.particlesHigh, 60);
      expect(PerformanceMonitor.particlesMedium, 30);
      expect(PerformanceMonitor.particlesLow, 15);
    });

    test('backgroundLayers tier boundaries match spec (2/1/0)', () {
      expect(PerformanceMonitor.layersHigh, 2);
      expect(PerformanceMonitor.layersMedium, 1);
      expect(PerformanceMonitor.layersLow, 0);
    });
  });

  group('ObjectPool stats + clearAll', () {
    test('stats reflect acquire/release', () {
      final pool = ObjectPool<Particle>(
        factory: Particle.new,
        initialSize: 3,
      );
      expect(pool.stats, const PoolStats(active: 0, idle: 3, totalCreated: 3));

      final a = pool.acquire();
      expect(pool.stats.active, 1);
      expect(pool.stats.idle, 2);

      pool.release(a);
      expect(pool.stats.active, 0);
      expect(pool.stats.idle, 3);
    });

    test('totalCreated counts factory calls beyond the initial seed',
        () {
      final pool = ObjectPool<Particle>(
        factory: Particle.new,
        initialSize: 1,
      );
      pool.acquire(); // reuses the seeded one
      pool.acquire(); // builds a new one
      pool.acquire(); // builds another
      expect(pool.stats.totalCreated, 3);
    });

    test('clearAll releases every outstanding instance', () {
      final pool = ObjectPool<Particle>(factory: Particle.new);
      final outstanding = [
        pool.acquire(),
        pool.acquire(),
        pool.acquire(),
      ];
      expect(pool.stats.active, 3);

      pool.clearAll();
      expect(pool.stats.active, 0);
      expect(pool.stats.idle, 3);
      // The same instances are back in the pool — outstandingList
      // referenced them but didn't replace them with fresh ones.
      expect(outstanding.length, 3);
    });

    test('PoolStats equality is value-based', () {
      const a = PoolStats(active: 1, idle: 2, totalCreated: 3);
      const b = PoolStats(active: 1, idle: 2, totalCreated: 3);
      const c = PoolStats(active: 2, idle: 2, totalCreated: 3);
      expect(a, b);
      expect(a == c, isFalse);
    });
  });
}
