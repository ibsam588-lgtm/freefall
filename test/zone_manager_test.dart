// Phase-2 zone & difficulty tests.
//
// ZoneManager is intentionally a non-Flame, depth-pumped state machine,
// which makes it ideal to unit test directly. We exercise:
//   * depth → zone resolution, including wrap-around past 5000m,
//   * the deep-edge transition slice,
//   * cycle multiplier bumps,
//   * onZoneEnter callback edges,
//   * DifficultyScaler bounds at depth 0, mid, and far past the cap.

import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/models/zone.dart';
import 'package:freefall/systems/difficulty_scaler.dart';
import 'package:freefall/systems/zone_manager.dart';

void main() {
  group('ZoneManager', () {
    test('returns the correct zone at canonical depths', () {
      final zm = ZoneManager();
      zm.update(0);
      expect(zm.currentZone.type, ZoneType.stratosphere);

      zm.update(500);
      expect(zm.currentZone.type, ZoneType.stratosphere);

      zm.update(1000);
      expect(zm.currentZone.type, ZoneType.city);

      zm.update(2500);
      expect(zm.currentZone.type, ZoneType.underground);

      zm.update(3500);
      expect(zm.currentZone.type, ZoneType.deepOcean);

      zm.update(4999);
      expect(zm.currentZone.type, ZoneType.core);
    });

    test('wraps back to Stratosphere after the cycle ends', () {
      final zm = ZoneManager();
      zm.update(5000);
      expect(zm.currentZone.type, ZoneType.stratosphere);

      zm.update(6500);
      expect(zm.currentZone.type, ZoneType.city);

      zm.update(9999);
      expect(zm.currentZone.type, ZoneType.core);
    });

    test('isInTransition flips on within 200m of the deep edge', () {
      final zm = ZoneManager();
      zm.update(700);
      expect(zm.isInTransition, isFalse);

      zm.update(799);
      expect(zm.isInTransition, isFalse);

      zm.update(800);
      expect(zm.isInTransition, isTrue);

      zm.update(999);
      expect(zm.isInTransition, isTrue);

      // Crossing into the next zone resets to false (we're now at the
      // shallow edge of City, far from its deep edge).
      zm.update(1100);
      expect(zm.isInTransition, isFalse);
    });

    test('transition flag works for every zone in the cycle', () {
      final zm = ZoneManager();
      // 800m, 1800m, 2800m, 3800m, 4800m all sit in their zone's
      // transition slice; the meter just before each does not.
      for (final edge in [800.0, 1800.0, 2800.0, 3800.0, 4800.0]) {
        zm.update(edge - 0.5);
        expect(zm.isInTransition, isFalse, reason: 'pre-edge at $edge');
        zm.update(edge);
        expect(zm.isInTransition, isTrue, reason: 'edge at $edge');
      }
    });

    test('zoneFraction goes 0..1 across each zone', () {
      final zm = ZoneManager();
      zm.update(0);
      expect(zm.zoneFraction(0), 0.0);

      zm.update(500);
      expect(zm.zoneFraction(500), closeTo(0.5, 1e-9));

      // 1000m is the boundary: it's the START of zone 2, fraction 0.
      zm.update(1000);
      expect(zm.zoneFraction(1000), closeTo(0.0, 1e-9));

      zm.update(1750);
      expect(zm.zoneFraction(1750), closeTo(0.75, 1e-9));
    });

    test('cycleMultiplier increases by 0.2 every 5000m', () {
      final zm = ZoneManager();
      expect(zm.currentCycleMultiplier, 1.0);

      zm.update(4999);
      expect(zm.currentCycleMultiplier, 1.0);

      zm.update(5000);
      expect(zm.currentCycleMultiplier, closeTo(1.2, 1e-9));

      zm.update(10000);
      expect(zm.currentCycleMultiplier, closeTo(1.4, 1e-9));

      zm.update(15000);
      expect(zm.currentCycleMultiplier, closeTo(1.6, 1e-9));
    });

    test('onZoneEnter fires once per crossing in order', () {
      final entries = <ZoneType>[];
      final zm = ZoneManager(onZoneEnter: entries.add);

      // First update enters the starting zone.
      zm.update(0);
      expect(entries, [ZoneType.stratosphere]);

      // Repeated updates inside the same zone don't re-fire.
      zm.update(500);
      zm.update(900);
      expect(entries, [ZoneType.stratosphere]);

      // Crossing into each subsequent zone fires exactly once.
      zm.update(1500);
      zm.update(2500);
      zm.update(3500);
      zm.update(4500);
      expect(entries, [
        ZoneType.stratosphere,
        ZoneType.city,
        ZoneType.underground,
        ZoneType.deepOcean,
        ZoneType.core,
      ]);

      // Wrapping back into Stratosphere also fires.
      zm.update(5500);
      expect(entries.last, ZoneType.stratosphere);
    });

    test('reset clears state', () {
      final zm = ZoneManager();
      zm.update(5500);
      expect(zm.completedCycles, 1);
      zm.reset();
      expect(zm.completedCycles, 0);
      expect(zm.currentDepthMeters, 0);
      expect(zm.currentCycleMultiplier, 1.0);
    });
  });

  group('DifficultyScaler bounds', () {
    DifficultyScaler newScaler({double atDepth = 0}) {
      final zm = ZoneManager();
      zm.update(atDepth);
      return DifficultyScaler(zoneManager: zm);
    }

    test('spawn rate sits in [base, max]', () {
      final s = newScaler();
      expect(s.obstacleSpawnRate(0), DifficultyScaler.baseSpawnRate);
      expect(s.obstacleSpawnRate(1000),
          inInclusiveRange(DifficultyScaler.baseSpawnRate,
              DifficultyScaler.maxSpawnRate));
      // Far past the cap.
      expect(s.obstacleSpawnRate(50000), DifficultyScaler.maxSpawnRate);
    });

    test('obstacle speed sits in [base, max]', () {
      final s = newScaler();
      expect(s.obstacleSpeed(0), DifficultyScaler.baseObstacleSpeed);
      expect(s.obstacleSpeed(50000), DifficultyScaler.maxObstacleSpeed);

      final mid = s.obstacleSpeed(2500);
      expect(
          mid,
          inInclusiveRange(
              DifficultyScaler.baseObstacleSpeed,
              DifficultyScaler.maxObstacleSpeed));
    });

    test('gap width sits in [min, base]', () {
      final s = newScaler();
      expect(s.gapWidth(0), DifficultyScaler.baseGapWidth);
      expect(s.gapWidth(50000), DifficultyScaler.minGapWidth);
      expect(
          s.gapWidth(2500),
          inInclusiveRange(
              DifficultyScaler.minGapWidth,
              DifficultyScaler.baseGapWidth));
    });

    test('difficulty level sits in [0, 20]', () {
      final s = newScaler();
      expect(s.difficultyLevel(0), 0);
      expect(s.difficultyLevel(50000), DifficultyScaler.maxDifficultyLevel);
      expect(s.difficultyLevel(2500),
          inInclusiveRange(0, DifficultyScaler.maxDifficultyLevel));
    });

    test('cycle multiplier amplifies spawn rate and speed', () {
      // First-cycle reading at a depth that's well clear of caps.
      final zm = ZoneManager();
      final s = DifficultyScaler(zoneManager: zm);
      zm.update(500); // 1 step worth of difficulty
      final firstSpawn = s.obstacleSpawnRate(500);
      final firstSpeed = s.obstacleSpeed(500);

      // Push into the second cycle and check the amplification at the
      // matching in-cycle depth (5500m == 500m offset, mult == 1.2).
      zm.update(5500);
      final secondSpawn = s.obstacleSpawnRate(5500);
      final secondSpeed = s.obstacleSpeed(5500);

      expect(secondSpawn, greaterThan(firstSpawn));
      expect(secondSpeed, greaterThan(firstSpeed));
      expect(zm.currentCycleMultiplier, closeTo(1.2, 1e-9));
    });

    test('gap shrinks (or holds at min) on later cycles', () {
      final zm = ZoneManager();
      final s = DifficultyScaler(zoneManager: zm);
      zm.update(500);
      final first = s.gapWidth(500);
      zm.update(5500);
      final second = s.gapWidth(5500);
      expect(second, lessThanOrEqualTo(first));
      expect(second, greaterThanOrEqualTo(DifficultyScaler.minGapWidth));
    });
  });
}
