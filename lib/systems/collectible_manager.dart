// systems/collectible_manager.dart
//
// Owns the live set of in-flight coins, gems, and powerups. The
// spawner produces them and hands them off via add*(); the manager
// attaches them to the visual scene (callbacks injected so it stays
// headless-testable), runs per-frame magnet-pull when the magnet
// powerup is active, performs pickup detection against the player's
// position, and prunes off-screen items.
//
// Pickup pipeline:
//   1. Iterate active items. If item is within [pickupRadius] of the
//      player, mark collected and call the registered callback (which
//      grants currency / score / powerup).
//   2. The CollectionFx record is appended (a tiny floating "+N" text
//      that the HUD consumes to draw briefly at the pickup point).
//   3. Item is removed from the active list and detached from the
//      world.
//
// Magnet behavior: when [PowerupManager.magnetRadius] > 0, every
// collectible within that radius is pulled toward the player with an
// ease-in factor proportional to closeness — items snap in fast as
// they approach pickup range.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../components/collectibles/coin.dart';
import '../components/collectibles/gem.dart';
import '../components/collectibles/powerup_item.dart';
import 'powerup_manager.dart';
import 'system_base.dart';

/// One floating-text effect spawned on a collectible pickup. The HUD
/// reads [activeCollectionFx] each frame and draws the still-alive ones.
class CollectionFx {
  final Vector2 position; // world space — HUD converts to screen
  final String text;
  final Color color;
  double remaining;
  final double total;

  CollectionFx({
    required this.position,
    required this.text,
    required this.color,
    required this.total,
  }) : remaining = total;

  /// 0..1 — 1 just spawned, 0 expired.
  double get lifeFraction => total <= 0 ? 0 : (remaining / total).clamp(0.0, 1.0);

  bool get isAlive => remaining > 0;
}

class CollectibleManager implements GameSystem {
  /// Pickup radius in world pixels. The player's own visual radius is
  /// 18; 26 here gives a small forgiveness buffer.
  static const double pickupRadius = 26;

  /// Off-screen buffer above the viewport before we recycle.
  static const double offscreenMargin = 200;

  /// Float text effect lifetime (seconds).
  static const double collectionFxDuration = 0.8;

  /// Magnet pull strength — each second, the collectible closes this
  /// fraction of the remaining distance to the player. Tuned so a coin
  /// at the edge of the magnet's 200px radius reaches the player in
  /// roughly 0.5s.
  static const double magnetPullPerSecond = 6.0;

  final void Function(PositionComponent c)? onAttach;
  final void Function(PositionComponent c)? onDetach;

  /// Optional reference for magnet-radius reads. The manager works
  /// without it (treats radius as 0), which keeps unit tests cheap.
  PowerupManager? powerupManager;

  /// Optional hook for pickup events. Called once per pickup, after the
  /// item has been removed from the active list.
  void Function(Coin coin)? onCoinCollected;
  void Function(Gem gem)? onGemCollected;
  void Function(PowerupItem powerup)? onPowerupCollected;

  final List<Coin> _coins = [];
  final List<Gem> _gems = [];
  final List<PowerupItem> _powerups = [];
  final List<CollectionFx> _fx = [];

  CollectibleManager({this.onAttach, this.onDetach});

  /// Live coin list. Read-only — mutate via [addCoin] / pickup pipeline.
  List<Coin> get activeCoins => List.unmodifiable(_coins);

  /// Live gem list.
  List<Gem> get activeGems => List.unmodifiable(_gems);

  /// Live powerup list.
  List<PowerupItem> get activePowerups => List.unmodifiable(_powerups);

  /// Active collection-effect overlays, drained as they expire.
  List<CollectionFx> get activeCollectionFx => List.unmodifiable(_fx);

  /// Total number of in-flight collectibles. Used by tests + HUD diag.
  int get activeCount => _coins.length + _gems.length + _powerups.length;

  void addCoin(Coin coin) {
    _coins.add(coin);
    onAttach?.call(coin);
  }

  void addGem(Gem gem) {
    _gems.add(gem);
    onAttach?.call(gem);
  }

  void addPowerup(PowerupItem powerup) {
    _powerups.add(powerup);
    onAttach?.call(powerup);
  }

  /// Wipe the world of collectibles (e.g. on player death / new run).
  void clear() {
    for (final c in _coins) {
      onDetach?.call(c);
    }
    _coins.clear();
    for (final g in _gems) {
      onDetach?.call(g);
    }
    _gems.clear();
    for (final p in _powerups) {
      onDetach?.call(p);
    }
    _powerups.clear();
    _fx.clear();
  }

  /// Public so tests can drive pickup detection without rigging Flame.
  void runPickupPass(Vector2 playerPos, double dt) {
    final magnetR = powerupManager?.magnetRadius ?? 0;

    _processList(_coins, playerPos, magnetR, dt, _onCoinPickup);
    _processList(_gems, playerPos, magnetR, dt, _onGemPickup);
    _processList(_powerups, playerPos, magnetR, dt, _onPowerupPickup);
  }

  void _onCoinPickup(Coin coin) {
    final mult = (powerupManager?.coinMultiplier ?? 1.0);
    final value = (coin.value * mult).round();
    _fx.add(CollectionFx(
      position: coin.position.clone(),
      text: '+$value',
      color: const Color(0xFFFFD700),
      total: collectionFxDuration,
    ));
    onCoinCollected?.call(coin);
  }

  void _onGemPickup(Gem gem) {
    final mult = (powerupManager?.scoreMultiplier ?? 1.0);
    final value = (gem.value * mult).round();
    _fx.add(CollectionFx(
      position: gem.position.clone(),
      text: '+$value',
      color: const Color(0xFFFFFFFF),
      total: collectionFxDuration,
    ));
    onGemCollected?.call(gem);
  }

  void _onPowerupPickup(PowerupItem powerup) {
    _fx.add(CollectionFx(
      position: powerup.position.clone(),
      text: powerup.powerupType.name.toUpperCase(),
      color: PowerupItem.accentFor(powerup.powerupType),
      total: collectionFxDuration,
    ));
    onPowerupCollected?.call(powerup);
    // Wire to the active manager if present so pickups always activate.
    powerupManager?.activatePowerup(powerup.powerupType);
  }

  /// Generic list pass — applied to coins/gems/powerups identically.
  void _processList<T extends PositionComponent>(
    List<T> list,
    Vector2 playerPos,
    double magnetR,
    double dt,
    void Function(T) onPickup,
  ) {
    for (int i = list.length - 1; i >= 0; i--) {
      final item = list[i];

      // Magnet pull — close a fraction of the gap each frame so it
      // looks "tractor-beamed" without overshooting.
      if (magnetR > 0) {
        final dx = playerPos.x - item.position.x;
        final dy = playerPos.y - item.position.y;
        final distSq = dx * dx + dy * dy;
        if (distSq < magnetR * magnetR) {
          final pullStep = (magnetPullPerSecond * dt).clamp(0.0, 1.0);
          item.position.x += dx * pullStep;
          item.position.y += dy * pullStep;
        }
      }

      // Pickup test — squared distance avoids a sqrt per item.
      final ddx = playerPos.x - item.position.x;
      final ddy = playerPos.y - item.position.y;
      if (ddx * ddx + ddy * ddy <= pickupRadius * pickupRadius) {
        // Mark collected so the renderer skips drawing it on the
        // current frame in case pruning is deferred.
        if (item is Coin) item.collected = true;
        if (item is Gem) item.collected = true;
        if (item is PowerupItem) item.collected = true;
        list.removeAt(i);
        onDetach?.call(item);
        onPickup(item);
      }
    }
  }

  /// Prune any collectible whose center has scrolled above the viewport
  /// top. Called by the host each frame after camera advance.
  void pruneOffscreen(double viewportTopY) {
    final threshold = viewportTopY - offscreenMargin;
    _pruneList(_coins, threshold);
    _pruneList(_gems, threshold);
    _pruneList(_powerups, threshold);
  }

  void _pruneList<T extends PositionComponent>(List<T> list, double threshold) {
    for (int i = list.length - 1; i >= 0; i--) {
      if (list[i].position.y < threshold) {
        final item = list[i];
        list.removeAt(i);
        onDetach?.call(item);
      }
    }
  }

  @override
  void update(double dt) {
    // Tick down the floating-text effects.
    for (final f in _fx) {
      f.remaining = math.max(0, f.remaining - dt);
    }
    _fx.removeWhere((f) => !f.isAlive);
  }
}
