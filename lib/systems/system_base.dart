// systems/system_base.dart
//
// Common contract for every system that participates in the fixed-timestep
// update loop. The GameLoop walks a list of GameSystem instances each tick
// and calls update(dt) on each in registration order.
//
// Systems are deliberately split from rendering: they own simulation state
// only. Visuals are produced by Flame components (e.g. Player) reading from
// system state. This keeps physics deterministic and decoupled from frame
// timing variability.

abstract class GameSystem {
  /// Advance this system by exactly [dt] seconds.
  ///
  /// [dt] is the GameLoop's fixed timestep, not the raw frame delta — so
  /// implementations can assume it's stable (typically 1/60 s).
  void update(double dt);
}
