// systems/obstacle_spawner.dart
//
// Procedurally spawns obstacles ahead of the player. The spawner is
// driven by the camera's current world position and speed — at each
// tick we look ahead two screens, advance an internal "next spawn Y"
// cursor, and pick zone-appropriate obstacle types until the cursor
// passes the lookahead line.
//
// Two structural rules the unit tests enforce:
//   1. Gap walls never appear within [minGapWallSeparation]px of each
//      other in world Y, so the player can always recover after one.
//   2. Gap widths come from DifficultyScaler but are clamped against
//      [GapWall.minGapWidth] (60px) so the orb can physically fit.
//
// The spawner doesn't own the visual scene — it just hands obstacles
// to ObstacleManager.add(). ObstacleManager attaches them to Flame,
// or in tests, just collects them in its active list.

import 'dart:math' as math;

import 'package:flame/components.dart';

import '../components/hazards/jellyfish.dart';
import '../components/hazards/lava_jet.dart';
import '../components/hazards/lightning_bolt.dart';
import '../components/hazards/stalactite.dart';
import '../components/hazards/wrecking_ball.dart';
import '../components/obstacles/breakable_platform.dart';
import '../components/obstacles/game_obstacle.dart';
import '../components/obstacles/gap_wall.dart';
import '../components/obstacles/magnet_obstacle.dart';
import '../components/obstacles/moving_block.dart';
import '../components/obstacles/rotating_obstacle.dart';
import '../components/obstacles/speed_gate.dart';
import '../components/obstacles/static_platform.dart';
import '../models/zone.dart';
import 'camera_system.dart';
import 'difficulty_scaler.dart';
import 'obstacle_manager.dart';
import 'system_base.dart';
import 'zone_manager.dart';

/// Discrete obstacle kinds the spawner can emit. Used for the per-zone
/// allowlists below; concrete construction lives in [_construct].
enum ObstacleKind {
  staticPlatform,
  gapWall,
  movingBlock,
  rotatingObstacle,
  breakablePlatform,
  magnetObstacle,
  speedGate,
  lightningBolt,
  wreckingBall,
  stalactite,
  jellyfish,
  lavaJet,
}

/// A weighted entry in a zone's spawn pool.
class _Weighted {
  final ObstacleKind kind;
  final double weight;
  const _Weighted(this.kind, this.weight);
}

class ObstacleSpawner implements GameSystem {
  /// Lookahead in screens — we want obstacles already in the world by
  /// the time the player gets close enough to react to them.
  static const double spawnAheadScreens = 2.0;

  /// Hard floor on world-Y separation between consecutive gap walls.
  /// Keeps the player from being boxed between two un-recoverable walls.
  static const double minGapWallSeparation = 300;

  /// Minimum spacing between any two spawns. Prevents the cursor from
  /// stacking obstacles into the same depth band when the difficulty
  /// curve briefly pushes spawn rate against camera speed.
  static const double minSpawnSpacing = 80;

  /// World-Y of the camera viewport's top edge. The host updates this
  /// each frame so the spawner can compute a lookahead line.
  final CameraSystem cameraSystem;

  /// Source of difficulty knobs (gap width comes from here).
  final DifficultyScaler difficultyScaler;

  /// Zone lookup: drives the per-zone obstacle allowlist.
  final ZoneManager zoneManager;

  /// Where new obstacles land.
  final ObstacleManager manager;

  /// Logical play-column width. GapWall needs this for its layout.
  final double playWidth;

  /// Logical viewport height — used to compute the lookahead distance.
  final double viewportHeight;

  /// RNG. Tests inject a seeded one for deterministic spawn sequences.
  final math.Random rng;

  /// World-Y where the next obstacle will be placed. Marches downward
  /// as we spawn. Initialized to be just below the starting viewport
  /// so the first batch of obstacles is already in flight at game start.
  double _nextSpawnY;

  /// World-Y of the most recently spawned gap wall. Used for the
  /// minGapWallSeparation rule.
  double _lastGapWallY = -1e9;

  /// Running count of lightning bolts spawned in this run. Used by the
  /// lightning pattern rule below — every spawn is placed in the next
  /// column of a deterministic 3-step cycle so the player can learn it
  /// instead of guessing.
  int _lightningSpawnCount = 0;

  int _idCounter = 0;

  /// Per-zone spawn allowlist with weights. Tuned so each zone has a
  /// recognizable signature: Stratosphere = lightning + open platforms,
  /// Core = lava jets + rotating arms, etc.
  static final Map<ZoneType, List<_Weighted>> _zonePool = {
    ZoneType.stratosphere: const [
      _Weighted(ObstacleKind.staticPlatform, 4),
      _Weighted(ObstacleKind.gapWall, 3),
      _Weighted(ObstacleKind.movingBlock, 2),
      _Weighted(ObstacleKind.rotatingObstacle, 1),
      _Weighted(ObstacleKind.lightningBolt, 2),
      _Weighted(ObstacleKind.speedGate, 1),
    ],
    ZoneType.city: const [
      _Weighted(ObstacleKind.staticPlatform, 3),
      _Weighted(ObstacleKind.gapWall, 3),
      _Weighted(ObstacleKind.movingBlock, 2),
      _Weighted(ObstacleKind.breakablePlatform, 2),
      _Weighted(ObstacleKind.magnetObstacle, 1),
      _Weighted(ObstacleKind.wreckingBall, 2),
      _Weighted(ObstacleKind.speedGate, 1),
    ],
    ZoneType.underground: const [
      _Weighted(ObstacleKind.staticPlatform, 3),
      _Weighted(ObstacleKind.gapWall, 3),
      _Weighted(ObstacleKind.breakablePlatform, 3),
      _Weighted(ObstacleKind.rotatingObstacle, 1),
      _Weighted(ObstacleKind.magnetObstacle, 1),
      _Weighted(ObstacleKind.stalactite, 2),
      _Weighted(ObstacleKind.speedGate, 1),
    ],
    ZoneType.deepOcean: const [
      _Weighted(ObstacleKind.gapWall, 3),
      _Weighted(ObstacleKind.movingBlock, 3),
      _Weighted(ObstacleKind.magnetObstacle, 2),
      _Weighted(ObstacleKind.jellyfish, 3),
      _Weighted(ObstacleKind.speedGate, 1),
    ],
    ZoneType.core: const [
      _Weighted(ObstacleKind.gapWall, 2),
      _Weighted(ObstacleKind.movingBlock, 2),
      _Weighted(ObstacleKind.rotatingObstacle, 3),
      _Weighted(ObstacleKind.magnetObstacle, 1),
      _Weighted(ObstacleKind.lavaJet, 3),
      _Weighted(ObstacleKind.speedGate, 1),
    ],
  };

  ObstacleSpawner({
    required this.cameraSystem,
    required this.difficultyScaler,
    required this.zoneManager,
    required this.manager,
    required this.playWidth,
    required this.viewportHeight,
    math.Random? rng,
    double? initialNextSpawnY,
  })  : rng = rng ?? math.Random(),
        _nextSpawnY = initialNextSpawnY ?? viewportHeight;

  double get nextSpawnY => _nextSpawnY;
  double get lastGapWallY => _lastGapWallY;

  /// Reset for a new run.
  void reset() {
    _nextSpawnY = viewportHeight;
    _lastGapWallY = -1e9;
    _lightningSpawnCount = 0;
    _idCounter = 0;
  }

  @override
  void update(double dt) {
    final viewportTopY =
        cameraSystem.playerWorldPosition.y - viewportHeight / 2;
    final lookaheadY = viewportTopY + viewportHeight * (1 + spawnAheadScreens);
    _spawnUntil(lookaheadY);
  }

  /// Public so tests can drive spawning without rigging up a CameraSystem.
  void spawnUntil(double lookaheadY) => _spawnUntil(lookaheadY);

  void _spawnUntil(double lookaheadY) {
    while (_nextSpawnY <= lookaheadY) {
      final spawnedKind = _spawnOne(_nextSpawnY);
      _nextSpawnY += _spacingForNext(spawnedKind);
    }
  }

  /// Picks a kind from the active zone's pool, builds the concrete
  /// obstacle, and registers it with the manager. Returns the kind
  /// actually spawned (used to compute next spacing).
  ObstacleKind _spawnOne(double atY) {
    final pool = _zonePool[zoneManager.currentZone.type] ??
        _zonePool[ZoneType.stratosphere]!;
    var kind = _pickWeighted(pool);

    // Enforce gap-wall separation: if we just placed a gap wall recently,
    // re-roll to a non-gap-wall pick. Up to 4 attempts so we never loop.
    if (kind == ObstacleKind.gapWall &&
        atY - _lastGapWallY < minGapWallSeparation) {
      for (int i = 0; i < 4; i++) {
        final candidate = _pickWeighted(pool);
        if (candidate != ObstacleKind.gapWall) {
          kind = candidate;
          break;
        }
      }
      // If after the retry budget we're still on a gap wall, swap it
      // for a static platform — guarantees the rule.
      if (kind == ObstacleKind.gapWall) kind = ObstacleKind.staticPlatform;
    }

    final obstacle = _construct(kind, atY);
    manager.add(obstacle);
    if (kind == ObstacleKind.gapWall) _lastGapWallY = atY;
    return kind;
  }

  /// Spacing in pixels between this obstacle and the next. Higher
  /// difficulty → tighter spacing; capped on the floor by [minSpawnSpacing].
  double _spacingForNext(ObstacleKind justSpawned) {
    final depth = zoneManager.currentDepthMeters;
    final ratePerSecond =
        difficultyScaler.obstacleSpawnRate(depth);
    final cameraPxPerSecond =
        cameraSystem.currentSpeed.clamp(50.0, double.infinity);
    final spacing = cameraPxPerSecond / ratePerSecond;
    return math.max(minSpawnSpacing, spacing);
  }

  ObstacleKind _pickWeighted(List<_Weighted> pool) {
    final total = pool.fold<double>(0, (a, w) => a + w.weight);
    var roll = rng.nextDouble() * total;
    for (final w in pool) {
      roll -= w.weight;
      if (roll <= 0) return w.kind;
    }
    return pool.last.kind;
  }

  GameObstacle _construct(ObstacleKind kind, double atY) {
    final id = _allocId(kind);
    final zone = zoneManager.currentZone;
    final pickX = _pickX();

    switch (kind) {
      case ObstacleKind.staticPlatform:
        return StaticPlatform(
          obstacleId: id,
          worldPosition: Vector2(pickX, atY),
          zone: zone,
          rng: rng,
        );
      case ObstacleKind.gapWall:
        final raw = difficultyScaler.gapWidth(zoneManager.currentDepthMeters);
        // Pick a gap center somewhere inside the column with margin so
        // the gap doesn't fall entirely off either edge.
        final gapW = math.max(GapWall.minGapWidth, raw);
        final centerX = (gapW / 2 + 20) +
            rng.nextDouble() * (playWidth - gapW - 40);
        return GapWall(
          obstacleId: id,
          centerY: atY,
          playWidth: playWidth,
          gapCenterX: centerX,
          rawGapWidth: raw,
          zone: zone,
        );
      case ObstacleKind.movingBlock:
        return MovingBlock(
          obstacleId: id,
          worldPosition: Vector2(pickX, atY),
          zone: zone,
          minX: 20,
          maxX: playWidth - 20,
          rng: rng,
        );
      case ObstacleKind.rotatingObstacle:
        return RotatingObstacle(
          obstacleId: id,
          worldPosition: Vector2(pickX, atY),
          zone: zone,
          rng: rng,
        );
      case ObstacleKind.breakablePlatform:
        return BreakablePlatform(
          obstacleId: id,
          worldPosition: Vector2(pickX, atY),
          zone: zone,
          rng: rng,
        );
      case ObstacleKind.magnetObstacle:
        return MagnetObstacle(
          obstacleId: id,
          worldPosition: Vector2(pickX, atY),
          zone: zone,
        );
      case ObstacleKind.speedGate:
        return SpeedGate(
          obstacleId: id,
          worldPosition: Vector2(pickX, atY),
        );
      case ObstacleKind.lightningBolt:
        // Lightning pattern (intentionally learnable):
        //   1. Each bolt lands in one of three fixed columns —
        //      left (1/4), center (1/2), or right (3/4) of the play
        //      column. The column cycles strictly L → C → R → L → …
        //      so a player who has seen two bolts can predict the next.
        //   2. The flash phase is locked to the column too: column 0
        //      flashes at phase 0 (active immediately), column 1 at
        //      flashDuration (just-cooled), column 2 mid-cooldown.
        //      That makes the rhythm "L flashes, C primes, R cools"
        //      and repeats — same shape every time, regardless of RNG.
        // Random per-bolt placement was the previous behavior; it
        // produced legal but unreadable thunderstorms.
        final col = _lightningSpawnCount % 3;
        _lightningSpawnCount++;
        final colX = playWidth * (0.25 + 0.25 * col);
        const cycle =
            LightningBolt.flashDuration + LightningBolt.cooldownDuration;
        final phase = (col / 3.0) * cycle;
        return LightningBolt(
          obstacleId: id,
          worldPosition: Vector2(colX, atY),
          initialPhase: phase,
        );
      case ObstacleKind.wreckingBall:
        return WreckingBall(
          obstacleId: id,
          // Anchor lives above the ball's spawn so the chain reads naturally.
          anchorPosition:
              Vector2(pickX, atY - 60),
          rng: rng,
        );
      case ObstacleKind.stalactite:
        return Stalactite(
          obstacleId: id,
          worldPosition: Vector2(pickX, atY),
        );
      case ObstacleKind.jellyfish:
        return Jellyfish(
          obstacleId: id,
          worldPosition: Vector2(pickX, atY),
          rng: rng,
        );
      case ObstacleKind.lavaJet:
        return LavaJet(
          obstacleId: id,
          worldPosition: Vector2(pickX, atY),
          rng: rng,
        );
    }
  }

  String _allocId(ObstacleKind kind) {
    _idCounter++;
    return '${kind.name}-$_idCounter';
  }

  double _pickX() {
    // Keep a 40px margin on either side so wide obstacles don't poke off
    // the play column.
    const margin = 40.0;
    return margin + rng.nextDouble() * (playWidth - margin * 2);
  }
}
