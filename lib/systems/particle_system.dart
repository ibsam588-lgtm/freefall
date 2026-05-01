// systems/particle_system.dart
//
// Phase 1 placeholder. The Player owns its own death particles for now
// (they're tightly coupled to its render), but ambient particles —
// dust, sparks from environment hits, zone-transition flares — will
// live here in Phase 2 and pull instances from ParticlePool.

import 'system_base.dart';

class ParticleSystem implements GameSystem {
  @override
  void update(double dt) {
    // No-op until ambient particles ship.
  }
}
