// Phase-15 zone-transition edge cases.
//
// zone_manager_test already covers the canonical transitions. This
// file fills the gaps the spec called out:
//   * onZoneEnter fires exactly once per crossing (not on every
//     fresh update at the same depth),
//   * isInTransition is on for the deep 200m of every zone and off
//     for the 800m above it,
//   * cycleMultiplier stacks deterministically across 3 cycles
//     (1.0 → 1.2 → 1.4 → 1.6).

import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/models/zone.dart';
import 'package:freefall/systems/zone_manager.dart';

void main() {
  group('Zone transition firing', () {
    test('onZoneEnter fires exactly once per zone crossing', () {
      final fired = <ZoneType>[];
      final zm = ZoneManager(onZoneEnter: fired.add);

      // First update at depth 0 — the player enters Stratosphere.
      zm.update(0);
      // Subsequent updates inside the same zone shouldn't re-fire.
      zm.update(50);
      zm.update(100);
      zm.update(999);
      expect(fired, [ZoneType.stratosphere]);

      // Cross into City — exactly one new fire.
      zm.update(1001);
      zm.update(1500);
      expect(fired, [ZoneType.stratosphere, ZoneType.city]);
    });

    test('onZoneEnter fires once per zone across a full cycle', () {
      final fired = <ZoneType>[];
      final zm = ZoneManager(onZoneEnter: fired.add);
      zm.update(0); // Stratosphere
      zm.update(1500); // City
      zm.update(2500); // Underground
      zm.update(3500); // Deep Ocean
      zm.update(4500); // Core
      expect(fired, [
        ZoneType.stratosphere,
        ZoneType.city,
        ZoneType.underground,
        ZoneType.deepOcean,
        ZoneType.core,
      ]);
    });
  });

  group('200m transition window', () {
    test('isInTransition is off in the first 800m of every zone', () {
      final zm = ZoneManager();
      // Sample 100m, 400m, 700m of Stratosphere — all below the
      // transition threshold.
      for (final d in [100, 400, 799]) {
        zm.update(d.toDouble());
        expect(zm.isInTransition, isFalse,
            reason: '${d}m: should not be in transition yet');
      }
    });

    test('isInTransition flips on at endDepth - 200m for each zone', () {
      final zm = ZoneManager();
      for (final z in Zone.defaultCycle) {
        // 1m before the 200m window: still not in transition.
        zm.update(z.endDepth - Zone.transitionDepth - 1);
        expect(zm.isInTransition, isFalse,
            reason: 'just before ${z.name} transition');

        // First meter of the window: transition is on.
        zm.update(z.endDepth - Zone.transitionDepth);
        expect(zm.isInTransition, isTrue,
            reason: 'edge of ${z.name} transition');

        // Mid-window: still on.
        zm.update(z.endDepth - 50);
        expect(zm.isInTransition, isTrue,
            reason: 'mid-${z.name} transition');
      }
    });
  });

  group('Cycle multiplier across 3 cycles', () {
    test('multiplier ticks up exactly 0.2 per full cycle', () {
      final zm = ZoneManager();
      expect(zm.currentCycleMultiplier, 1.0);

      // First full cycle traversal (5000m crossed).
      zm.update(Zone.cycleDepth);
      expect(zm.currentCycleMultiplier, closeTo(1.2, 1e-9));

      // Second.
      zm.update(Zone.cycleDepth * 2);
      expect(zm.currentCycleMultiplier, closeTo(1.4, 1e-9));

      // Third.
      zm.update(Zone.cycleDepth * 3);
      expect(zm.currentCycleMultiplier, closeTo(1.6, 1e-9));
    });

    test('multiplier is stable inside a cycle', () {
      final zm = ZoneManager();
      // Cross the first full cycle so the multiplier ticks up.
      zm.update(Zone.cycleDepth);
      // Walk forward inside the second cycle — multiplier shouldn't
      // move until we cross [cycleDepth * 2].
      for (final d in [5100, 6000, 7500, 9000, 9900]) {
        zm.update(d.toDouble());
        expect(zm.currentCycleMultiplier, closeTo(1.2, 1e-9),
            reason: 'depth ${d}m should still report 1.2');
      }
    });

    test('reset() returns the multiplier to 1.0', () {
      final zm = ZoneManager();
      zm.update(Zone.cycleDepth * 2);
      expect(zm.currentCycleMultiplier, closeTo(1.4, 1e-9));
      zm.reset();
      expect(zm.currentCycleMultiplier, 1.0);
    });
  });
}
