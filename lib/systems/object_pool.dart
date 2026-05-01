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

import '../components/coin.dart';
import '../components/obstacle.dart';
import '../components/particle.dart';

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

  final List<T> _free = [];
  int _outstanding = 0;

  ObjectPool({
    required this.factory,
    int initialSize = 0,
    this.maxSize = 1024,
    this.onAcquire,
    this.onRelease,
  }) {
    for (int i = 0; i < initialSize; i++) {
      _free.add(factory());
    }
  }

  /// Hand out an object — reuses a free one if any, otherwise builds new.
  T acquire() {
    final T obj;
    if (_free.isNotEmpty) {
      obj = _free.removeLast();
    } else {
      obj = factory();
    }
    _outstanding++;
    onAcquire?.call(obj);
    return obj;
  }

  /// Return [obj] to the pool. Drops it if we're already at [maxSize].
  void release(T obj) {
    if (_outstanding > 0) _outstanding--;
    onRelease?.call(obj);
    if (_free.length < maxSize) {
      _free.add(obj);
    }
  }

  /// Drain the free list. Doesn't touch outstanding instances.
  void clear() => _free.clear();

  int get freeCount => _free.length;
  int get outstandingCount => _outstanding;
}

/// Pre-configured pool for pluggable obstacle instances.
class ObstaclePool extends ObjectPool<Obstacle> {
  ObstaclePool({super.initialSize = 32, super.maxSize = 128})
      : super(
          factory: Obstacle.new,
          onAcquire: _resetObstacle,
        );

  static void _resetObstacle(Obstacle o) => o.reset();
}

/// Pre-configured pool for transient particles (death, sparks, dust).
class ParticlePool extends ObjectPool<Particle> {
  ParticlePool({super.initialSize = 64, super.maxSize = 256})
      : super(
          factory: Particle.new,
          onAcquire: _resetParticle,
        );

  static void _resetParticle(Particle p) => p.reset();
}

/// Pre-configured pool for collectible coins.
class CoinPool extends ObjectPool<Coin> {
  CoinPool({super.initialSize = 16, super.maxSize = 96})
      : super(
          factory: Coin.new,
          onAcquire: _resetCoin,
        );

  static void _resetCoin(Coin c) => c.reset();
}
