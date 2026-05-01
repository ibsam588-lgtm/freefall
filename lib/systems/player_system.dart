// systems/player_system.dart
//
// Phase 1 placeholder for player-level concerns that don't belong
// inside the Player component itself: power-up timers, score multipliers,
// streak tracking, etc. The Player component handles its own physics
// and rendering; this system lives in the dispatch order so future
// gameplay state has an obvious home.

import 'system_base.dart';

class PlayerSystem implements GameSystem {
  @override
  void update(double dt) {
    // No-op until power-ups / multipliers ship.
  }
}
