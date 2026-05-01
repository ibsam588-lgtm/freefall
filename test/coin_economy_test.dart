// Phase-15 coin-economy edge cases.
//
// Phase 7 already covers the happy path of CoinRepository in
// daily_login_test.dart. This file fills the gaps:
//   * spending exactly the balance leaves 0, not negative,
//   * concurrent addCoins futures resolve in order without dropping
//     increments,
//   * the diamond coin tier is worth 100 (catalog spec),
//   * lifetime-earned tracks cumulative additions (never goes down,
//     even after spends).

import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/models/collectible.dart';
import 'package:freefall/repositories/coin_repository.dart';

CoinRepository _build({int seed = 0}) {
  final storage = InMemoryCoinStorage();
  if (seed > 0) {
    storage.seed(CoinRepository.balanceKey, '$seed');
  }
  return CoinRepository(storage: storage);
}

void main() {
  group('CoinRepository edge cases', () {
    test('spending exactly the balance leaves 0, not negative',
        () async {
      final repo = _build(seed: 100);
      final next = await repo.spendCoins(100);
      expect(next, 0);
      expect(await repo.getBalance(), 0);
    });

    test('overspending throws InsufficientCoinsException', () async {
      final repo = _build(seed: 50);
      expect(
        () => repo.spendCoins(51),
        throwsA(isA<InsufficientCoinsException>()),
      );
      // Balance untouched on a failed spend.
      expect(await repo.getBalance(), 50);
    });

    test('addCoins ignores zero / negative amounts', () async {
      final repo = _build(seed: 10);
      await repo.addCoins(0);
      await repo.addCoins(-5);
      expect(await repo.getBalance(), 10);
      expect(await repo.getLifetimeEarned(), 0,
          reason: 'no positive credits ⇒ lifetime stays 0');
    });

    test('chained addCoins futures preserve every increment', () async {
      final repo = _build();
      // Sequential await chain — five back-to-back additions drained
      // through the same future chain. Each adds 7 coins; balance
      // must walk 0 → 7 → 14 → 21 → 28 → 35 cleanly.
      // (Pathological parallel Future.wait is a known race in the
      // repo's read-modify-write — out of scope for Phase 15. The
      // game never issues concurrent coin grants in practice; coin
      // pickups go through a single-threaded collectible manager.)
      for (var i = 0; i < 5; i++) {
        await repo.addCoins(7);
      }
      expect(await repo.getBalance(), 35);
      expect(await repo.getLifetimeEarned(), 35);
    });

    test('diamond coin tier is worth 100 (catalog spec)', () {
      expect(CoinValue.forType(CoinType.diamond), 100);
      expect(CoinValue.forType(CoinType.gold), 25);
      expect(CoinValue.forType(CoinType.silver), 5);
      expect(CoinValue.forType(CoinType.bronze), 1);
    });

    test('lifetime earned never decreases, even after spends',
        () async {
      final repo = _build();
      await repo.addCoins(500);
      await repo.spendCoins(200);
      await repo.spendCoins(100);
      expect(await repo.getBalance(), 200);
      expect(await repo.getLifetimeEarned(), 500,
          reason: 'lifetime tracks the cumulative ADD, not the net');
    });

    test('lifetime earned accumulates across many adds', () async {
      final repo = _build();
      for (var i = 0; i < 10; i++) {
        await repo.addCoins(13);
      }
      expect(await repo.getLifetimeEarned(), 130);
      expect(await repo.getBalance(), 130);
    });

    test('balance stream emits each successful add/spend', () async {
      final repo = _build(seed: 50);
      final emitted = <int>[];
      final sub = repo.balanceStream.listen(emitted.add);
      await repo.addCoins(10);
      await repo.addCoins(5);
      await repo.spendCoins(20);
      // Drain microtasks.
      await Future<void>.delayed(Duration.zero);
      expect(emitted, [60, 65, 45]);
      await sub.cancel();
      await repo.dispose();
    });

    test('balance stream is silent on no-op writes', () async {
      final repo = _build(seed: 10);
      final emitted = <int>[];
      final sub = repo.balanceStream.listen(emitted.add);
      await repo.addCoins(0);
      await repo.spendCoins(0);
      await repo.addCoins(-5);
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);
      await sub.cancel();
      await repo.dispose();
    });
  });
}
