// systems/collectible_spawner.dart
//
// Spawns coins, gems, and powerups into the world ahead of the player.
// The cadence is driven by camera position (look ahead two screens) so
// pickups are already in flight by the time the player gets close.
//
// Spawn pattern:
//   * Coins march downward in clusters of 3–6 along a smoothly curving
//     "likely path" the player would naturally trace.
//   * Coin tier is a weighted random per coin: 1% diamond, 5% gold,
//     20% silver, rest bronze.
//   * Gems sprinkle in randomly — roughly one gem every 8 coins.
//   * Powerups spawn singularly every 800–1200m (random).
//   * Near-miss coin spawn: when the player passes within 30px of an
//     obstacle, dropAtNearMiss() emits 3 bronze coins behind them. This
//     is reactive, called by the obstacle pipeline, not from update().
//
// The spawner doesn't own coin/gem/powerup objects. It hands them off
// to CollectibleManager which attaches them to the world and handles
// pickup detection.

import 'dart:math' as math;

import 'package:flame/components.dart';

import '../components/collectibles/coin.dart';
import '../components/collectibles/gem.dart';
import '../components/collectibles/powerup_item.dart';
import '../models/collectible.dart';
import 'camera_system.dart';
import 'collectible_manager.dart';
import 'system_base.dart';

class CollectibleSpawner implements GameSystem {
  /// Lookahead in screens — must match ObstacleSpawner's so coins land
  /// in the same forward-prepared band as obstacles.
  static const double spawnAheadScreens = 2.0;

  /// Vertical distance between coins in a cluster.
  static const double coinClusterSpacing = 30;

  /// Min/max coins in a single cluster.
  static const int minClusterSize = 3;
  static const int maxClusterSize = 6;

  /// Vertical gap between successive coin clusters.
  static const double clusterGap = 140;

  /// Probability that a coin slot is upgraded to a gem instead.
  /// 1/8 = ~one gem per cluster of 8 coins on average.
  static const double gemFromCoinChance = 1.0 / 8.0;

  /// Coin tier weights (must sum to 100).
  static const double diamondPct = 0.01;
  static const double goldPct = 0.05;
  static const double silverPct = 0.20;
  // Bronze is 1 - sum of above = 0.74.

  /// Powerup spawn cadence — one powerup every [minPowerupGap]..[maxPowerupGap]
  /// pixels of world Y descent.
  static const double minPowerupGap = 8000; // 800m at 10 px/m
  static const double maxPowerupGap = 12000; // 1200m

  /// Near-miss reward count.
  static const int nearMissCoinCount = 3;

  /// Margins from the play column edges for any spawned coin / gem /
  /// powerup, so they never sit half off-screen.
  static const double sideMargin = 40;

  final CameraSystem cameraSystem;
  final CollectibleManager manager;
  final double playWidth;
  final double viewportHeight;
  final math.Random rng;

  /// World Y where the next coin cluster center will be placed.
  double _nextClusterY;

  /// World Y of the next powerup spawn.
  double _nextPowerupY;

  /// Center X used by the *current* cluster — the path drifts smoothly
  /// across clusters so a cluster doesn't snap to a new column.
  double _pathCenterX;

  int _idCounter = 0;

  CollectibleSpawner({
    required this.cameraSystem,
    required this.manager,
    required this.playWidth,
    required this.viewportHeight,
    math.Random? rng,
    double? initialNextClusterY,
    double? initialNextPowerupY,
    double? initialPathCenterX,
  })  : rng = rng ?? math.Random(),
        _nextClusterY = initialNextClusterY ?? viewportHeight,
        _nextPowerupY =
            initialNextPowerupY ?? viewportHeight + minPowerupGap,
        _pathCenterX = initialPathCenterX ?? playWidth / 2;

  double get nextClusterY => _nextClusterY;
  double get nextPowerupY => _nextPowerupY;

  /// Reset for a new run. Mirrors ObstacleSpawner.reset.
  void reset() {
    _nextClusterY = viewportHeight;
    _nextPowerupY = viewportHeight + minPowerupGap;
    _pathCenterX = playWidth / 2;
    _idCounter = 0;
  }

  @override
  void update(double dt) {
    final viewportTopY =
        cameraSystem.playerWorldPosition.y - viewportHeight / 2;
    final lookaheadY = viewportTopY + viewportHeight * (1 + spawnAheadScreens);
    spawnUntil(lookaheadY);
  }

  /// Public so tests can drive spawning without rigging the camera.
  void spawnUntil(double lookaheadY) {
    while (_nextClusterY <= lookaheadY) {
      _spawnCluster(_nextClusterY);
      _nextClusterY += clusterGap;
    }
    while (_nextPowerupY <= lookaheadY) {
      _spawnPowerup(_nextPowerupY);
      _nextPowerupY +=
          minPowerupGap + rng.nextDouble() * (maxPowerupGap - minPowerupGap);
    }
  }

  /// Spawn 3 bronze coins at [around] (the player position when the
  /// near-miss was detected). Public hook for the obstacle pipeline.
  void dropAtNearMiss(Vector2 around) {
    for (int i = 0; i < nearMissCoinCount; i++) {
      final offsetX = (rng.nextDouble() - 0.5) * 50;
      final offsetY = -10.0 - i * 18; // spawn just behind the player
      final pos = Vector2(
        (around.x + offsetX).clamp(sideMargin, playWidth - sideMargin),
        around.y + offsetY,
      );
      final coin = Coin(
        collectibleId: _allocId('coin'),
        coinType: CoinType.bronze,
        worldPosition: pos,
        phaseOffset: rng.nextDouble() * math.pi * 2,
      );
      manager.addCoin(coin);
    }
  }

  void _spawnCluster(double centerY) {
    // Drift the path center by up to 60px per cluster so coins read as
    // a meandering arc, not a column. Clamp to play column.
    _pathCenterX += (rng.nextDouble() - 0.5) * 120;
    _pathCenterX = _pathCenterX.clamp(sideMargin + 20, playWidth - sideMargin - 20);

    final size = minClusterSize +
        rng.nextInt(maxClusterSize - minClusterSize + 1);
    final firstY = centerY - (size - 1) * coinClusterSpacing / 2;
    for (int i = 0; i < size; i++) {
      final y = firstY + i * coinClusterSpacing;
      // Small per-coin sin offset so the cluster reads as an arc.
      final dx = math.sin(i * 0.7) * 18;
      final x = (_pathCenterX + dx)
          .clamp(sideMargin, playWidth - sideMargin)
          .toDouble();

      // Decide gem-or-coin per slot.
      if (rng.nextDouble() < gemFromCoinChance) {
        final gem = Gem(
          collectibleId: _allocId('gem'),
          gemType: _rollGemType(),
          worldPosition: Vector2(x, y),
        );
        manager.addGem(gem);
      } else {
        final coin = Coin(
          collectibleId: _allocId('coin'),
          coinType: _rollCoinType(),
          worldPosition: Vector2(x, y),
          phaseOffset: rng.nextDouble() * math.pi * 2,
        );
        manager.addCoin(coin);
      }
    }
  }

  void _spawnPowerup(double atY) {
    final type = PowerupType.values[rng.nextInt(PowerupType.values.length)];
    final x = sideMargin + rng.nextDouble() * (playWidth - sideMargin * 2);
    final p = PowerupItem(
      collectibleId: _allocId('powerup'),
      powerupType: type,
      worldPosition: Vector2(x, atY),
    );
    manager.addPowerup(p);
  }

  /// Weighted coin tier roll — 1% diamond, 5% gold, 20% silver, rest bronze.
  CoinType _rollCoinType() {
    final r = rng.nextDouble();
    if (r < diamondPct) return CoinType.diamond;
    if (r < diamondPct + goldPct) return CoinType.gold;
    if (r < diamondPct + goldPct + silverPct) return CoinType.silver;
    return CoinType.bronze;
  }

  /// Gem tiers are biased toward bronze, with rare gold drops.
  GemType _rollGemType() {
    final r = rng.nextDouble();
    if (r < 0.10) return GemType.gold;
    if (r < 0.35) return GemType.silver;
    return GemType.bronze;
  }

  String _allocId(String kind) {
    _idCounter++;
    return '$kind-c$_idCounter';
  }
}
