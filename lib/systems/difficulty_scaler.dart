// systems/difficulty_scaler.dart
//
// Pure-function lookups that turn current depth + cycle multiplier into
// the four numbers that drive obstacle pressure: spawn rate, obstacle
// speed, gap width, and an integer "level" used by HUD and analytics.
//
// Lives outside the GameSystem fixed-step bus because every method is a
// stateless query — callers (ObstacleSystem in Phase 3) read the value
// they need each frame. ZoneManager is injected so the cycle multiplier
// can amplify all four knobs once depth wraps past 5000m.

import '../models/zone.dart';
import 'zone_manager.dart';

class DifficultyScaler {
  /// Source of the cycle multiplier. Required at construction time —
  /// there's no sensible "no zones" mode for difficulty.
  final ZoneManager zoneManager;

  // ---- spawn rate -------------------------------------------------------

  /// Obstacles per second on the first descent at depth 0.
  static const double baseSpawnRate = 1.5;

  /// Spawn rate added every [_spawnRateStepMeters] of descent, before the
  /// cycle multiplier is applied.
  static const double spawnRateIncrement = 0.1;

  /// Hard cap on per-second spawn rate. Above this the screen turns into
  /// a wall of obstacles and the game stops being readable.
  static const double maxSpawnRate = 4.0;

  // ---- obstacle speed ---------------------------------------------------

  static const double baseObstacleSpeed = 200; // px/s
  static const double obstacleSpeedIncrement = 15; // px/s per step
  static const double maxObstacleSpeed = 600; // px/s

  // ---- gap width --------------------------------------------------------

  static const double baseGapWidth = 200; // px
  static const double gapWidthDecrement = 5; // px per step
  static const double minGapWidth = 80; // px

  // ---- difficulty level -------------------------------------------------

  /// Total integer levels exposed to HUD/analytics. 0 at the start, 20
  /// at the bottom of one cycle (5000m). Multiplied by cycle multiplier
  /// then capped, so deeper cycles still sit at level 20.
  static const int maxDifficultyLevel = 20;

  /// All four scalars step every this-many meters. Tuned alongside
  /// CameraSystem's 500m speed-step cadence so difficulty bumps land
  /// at predictable depth markers.
  static const double _stepMeters = 500;

  DifficultyScaler({required this.zoneManager});

  /// Convenience: difficulty step count for a given depth. Internal —
  /// floor(depth / 500m). Negative depths clamp to 0.
  int _steps(double depthMeters) =>
      depthMeters <= 0 ? 0 : (depthMeters / _stepMeters).floor();

  /// Obstacles per second at [depthMeters], multiplied by the active
  /// cycle multiplier and clamped to [baseSpawnRate, maxSpawnRate].
  double obstacleSpawnRate(double depthMeters) {
    final raw = baseSpawnRate + spawnRateIncrement * _steps(depthMeters);
    final scaled = raw * zoneManager.currentCycleMultiplier;
    return scaled.clamp(baseSpawnRate, maxSpawnRate);
  }

  /// Obstacle world-space velocity at [depthMeters], in px/s.
  double obstacleSpeed(double depthMeters) {
    final raw =
        baseObstacleSpeed + obstacleSpeedIncrement * _steps(depthMeters);
    final scaled = raw * zoneManager.currentCycleMultiplier;
    return scaled.clamp(baseObstacleSpeed, maxObstacleSpeed);
  }

  /// Width of the navigable gap between hazards. Shrinks with depth and
  /// with cycle count; floored at [minGapWidth] so the player can always
  /// physically fit through.
  double gapWidth(double depthMeters) {
    final raw = baseGapWidth - gapWidthDecrement * _steps(depthMeters);
    // The cycle multiplier *narrows* the gap on later cycles, hence the
    // divide instead of multiply — a bigger multiplier == harder == less
    // room.
    final scaled = raw / zoneManager.currentCycleMultiplier;
    return scaled.clamp(minGapWidth, baseGapWidth);
  }

  /// Integer 0..20 difficulty bucket. Useful for HUD ramp visuals and
  /// for analytics telemetry that doesn't want continuous floats.
  int difficultyLevel(double depthMeters) {
    if (depthMeters <= 0) return 0;
    final raw = (depthMeters / Zone.cycleDepth) * maxDifficultyLevel;
    final scaled = raw * zoneManager.currentCycleMultiplier;
    final level = scaled.floor();
    if (level < 0) return 0;
    if (level > maxDifficultyLevel) return maxDifficultyLevel;
    return level;
  }
}
