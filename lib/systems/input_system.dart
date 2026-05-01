// systems/input_system.dart
//
// Phase 1 placeholder. Future home for cross-cutting input dispatch
// (e.g. routing pause-button or HUD-button taps to the right consumer).
// In Phase 1 the Player reads sensors_plus directly and HUD buttons
// hit Flame's gesture detectors, so this system has nothing to do yet.

import 'system_base.dart';

class InputSystem implements GameSystem {
  @override
  void update(double dt) {
    // No-op until HUD/pause/share routing lands.
  }
}
