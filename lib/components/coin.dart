// components/coin.dart
//
// Phase 1 minimal data carrier for CoinPool. Phase 2 will give this
// rendering, pickup magnetism, and a collect animation.

import 'package:flame/components.dart';

class Coin {
  String id = '';
  final Vector2 position = Vector2.zero();
  bool active = false;

  /// Coin denomination — small/medium/large pickups will use this.
  int value = 1;

  Coin();

  void reset() {
    id = '';
    position.setZero();
    active = false;
    value = 1;
  }
}
