// systems/object_pool.dart
//
// Generic, allocation-bounded object pool used to recycle short-lived
// game objects (obstacles spawned each meter, hit/coin particles,
// pickup coins). Avoids per-frame heap churn and the GC pauses that
// come with it on lower-end Android devices.
//
// Usage:
//   final pool = ObjectPool<Coin>(factory: Coin.new, initialSize: 32);
//   final coin = pool.acquire()..position = ...;
//   ...
//   pool.release(coin);
//
// Phase 14 additions:
//   * [PoolStats] snapshot — surfaces active/idle/total counters that
//     the perf-monitor / debug overlay can read for diagnostics.
//   * [clearAll] — return every outstanding object to the free list
//     in one call (handy on scene reset / restartRun where the
//     manager has already lost the references).
//   * `totalCreated` tracks the lifetime allocation count — when a
//     pool's lifetime allocations exceed [maxSize] the first time we
//     warn in debug, signaling that the [initialSize] / [maxSize]
//     budget needs a bump.

import 'package:flutter/foundation.dart';

import '../components/coin.dart';
import '../components/obstacle.dart';
import '../components/particle.dart';

/// Read-only snapshot of pool state. Returned by [ObjectPool.stats].
/// Pure data so tests can compare directly.
class PoolStats {
  /// Outstanding instances — handed out by [ObjectPool.acquire] and
  /// not yet [ObjectPool.release]d.
  final int active;

  /// Free instances sitting in the pool, ready for the next acquire.
  final int idle;

  /// Lifetime count of [factory] calls. >maxSize means the pool was
  /// undersized at some point — the warning fires once when we cross.
  final int totalCreated;

  const PoolStats({
    required this.active,
    required this.idle,
    required this.totalCreated,
  });

  @override
  bool operator ==(Object other) =>
      other is PoolStats &&
      other.active == active &&
      other.idle == idle &&
      other.totalCreated == totalCreated;

  @override
  int get hashCode => Object.hash(active, idle, totalCreated);

  @override
  String toString() =>
      'PoolStats(active=$active, idle=$idle, totalCreated=$totalCreated)';
}

class ObjectPool<T> {
  /// Builds a fresh instance when the free list is empty.
  final T Function() factory;

  /// Optional reset hook called every time an object leaves the pool.
  /// Use to clear per-instance state without rebuilding the object.
  final void Function(T obj)? onAcquire;

  /// Optional teardown hook when an object returns to the pool.
  final void Function(T obj)? onRelease;

  /// Hard cap on idle objects retained. Above this, released objects
  /// are dropped on the floor (and let the GC reap them).
  final int maxSize;

  /// Optional human-readable name. Drives the oversized-pool warning
  /// message so a developer can grep to the right pool quickly.
  final String? debugName;

  final List<T> _free = [];
  int _outstanding = 0;
  int _totalCreated = 0;
  bool _oversizedWarned = false;

  /// Hold a list of every outstanding instance so [clearAll] can
  /// release them without the caller threading them back. Tracked
  /// separately from the free list — same object never sits in both.
  final List<T> _outstandingList = [];

  ObjectPool({
    required this.factory,
    int initialSize = 0,
    this.maxSize = 1024,
    this.onAcquire,
    this.onRelease,
    this.debugName,
  }) {
    for (int i = 0; i < initialSize; i++) {
      _free.add(_buildOne());
    }
  }

  /// Hand out an object — reuses a free one if any, otherwise builds new.
  T acquire() {
    final T obj;
    if (_free.isNotEmpty) {
      obj = _free.removeLast();
    } else {
      obj = _buildOne();
    }
    _outstanding++;
    _outstandingList.add(obj);
    onAcquire?.call(obj);
    return obj;
  }

  /// Return [obj] to the pool. Drops it if we're already at [maxSize].
  void release(T obj) {
    if (_outstanding > 0) _outstanding--;
    _outstandingList.remove(obj);
    onRelease?.call(obj);
    if (_free.length < maxSize) {
      _free.add(obj);
    }
  }

  /// Drain the free list. Doesn't touch outstanding instances.
  void clear() => _free.clear();

  /// Phase 14: return every outstanding instance to the pool. Use
  /// when the managers that held them have themselves been reset and
  /// the references are no longer reachable via the normal release
  /// path.
  void clearAll() {
    if (_outstandingList.isEmpty) return;
    // Copy because release() mutates _outstandingList.
    final pending = List<T>.from(_outstandingList);
    for (final obj in pending) {
      release(obj);
    }
  }

  int get freeCount => _free.length;
  int get outstandingCount => _outstanding;
  int get totalCreated => _totalCreated;

  /// Phase 14 diagnostic snapshot. Read by perf overlays + tests.
  PoolStats get stats => PoolStats(
        active: _outstanding,
        idle: _free.length,
        totalCreated: _totalCreated,
      );

  T _buildOne() {
    final obj = factory();
    _totalCreated++;
    if (!_oversizedWarned && _totalCreated > maxSize) {
      _oversizedWarned = true;
      if (kDebugMode) {
        final label = debugName ?? T.toString();
        debugPrint(
          '[ObjectPool] $label exceeded maxSize ($maxSize) — '
          'totalCreated=$_totalCreated. Consider raising the cap.',
        );
      }
    }
    return obj;
  }
}

/// Pre-configured pool for pluggable obstacle instances.
class ObstaclePool extends ObjectPool<Obstacle> {
  ObstaclePool({super.initialSize = 32, super.maxSize = 128})
      : super(
          factory: Obstacle.new,
          onAcquire: _resetObstacle,
          debugName: 'ObstaclePool',
        );

  static void _resetObstacle(Obstacle o) => o.reset();
}

/// Pre-configured pool for transient particles (death, sparks, dust).
class ParticlePool extends ObjectPool<Particle> {
  ParticlePool({super.initialSize = 64, super.maxSize = 256})
      : super(
          factory: Particle.new,
          onAcquire: _resetParticle,
          debugName: 'ParticlePool',
        );

  static void _resetParticle(Particle p) => p.reset();
}

/// Pre-configured pool for collectible coins.
class CoinPool extends ObjectPool<Coin> {
  CoinPool({super.initialSize = 16, super.maxSize = 96})
      : super(
          factory: Coin.new,
          onAcquire: _resetCoin,
          debugName: 'CoinPool',
        );

  static void _resetCoin(Coin c) => c.reset();
}
