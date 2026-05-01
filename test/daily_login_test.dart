// Phase-7 daily-login + ad-reward + coin-stream tests.
//
// All three pieces are storage-bound; we use the in-memory fakes so
// the suite stays fast and deterministic. Time-of-day is injected via
// a `now` clock so we can simulate a multi-day run in milliseconds.

import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/models/daily_login_bonus.dart';
import 'package:freefall/repositories/ad_reward_repository.dart';
import 'package:freefall/repositories/coin_repository.dart';
import 'package:freefall/repositories/daily_login_repository.dart';

DailyLoginRepository _loginRepo({
  required DateTime Function() now,
  InMemoryLoginStorage? storage,
}) {
  return DailyLoginRepository(
    storage: storage ?? InMemoryLoginStorage(),
    now: now,
  );
}

AdRewardRepository _adRepo({
  required DateTime Function() now,
  InMemoryLoginStorage? storage,
}) {
  return AdRewardRepository(
    storage: storage ?? InMemoryLoginStorage(),
    now: now,
  );
}

void main() {
  group('DailyLoginBonus table', () {
    test('matches the spec for all 7 days', () {
      const expected = [50, 100, 150, 200, 300, 500, 1000];
      for (int i = 0; i < expected.length; i++) {
        expect(DailyLoginBonus.forDay(i + 1), expected[i],
            reason: 'Day ${i + 1} should award ${expected[i]} coins');
      }
    });

    test('clamps day index above 7 to Day 7 reward', () {
      expect(DailyLoginBonus.forDay(8), 1000);
      expect(DailyLoginBonus.forDay(99), 1000);
    });

    test('clamps day index below 1 to Day 1 reward', () {
      expect(DailyLoginBonus.forDay(0), 50);
      expect(DailyLoginBonus.forDay(-3), 50);
    });
  });

  group('DailyLoginRepository state machine', () {
    test('first claim awards Day 1 (+50 coins)', () async {
      var clock = DateTime(2026, 5, 1);
      final repo = _loginRepo(now: () => clock);

      expect(await repo.getConsecutiveDays(), 0);
      expect(await repo.getLastLoginDate(), isNull);

      final result = await repo.recordLogin();
      expect(result.claimed, isTrue);
      expect(result.day, 1);
      expect(result.coins, 50);
      expect(await repo.getConsecutiveDays(), 1);
      expect(await repo.getLastLoginDate(), DateTime(2026, 5, 1));
    });

    test('second claim same day is rejected (no double-dip)', () async {
      var clock = DateTime(2026, 5, 1);
      final repo = _loginRepo(now: () => clock);
      await repo.recordLogin();

      final dup = await repo.recordLogin();
      expect(dup.claimed, isFalse);
      expect(dup.coins, 0);
      // Streak unchanged.
      expect(await repo.getConsecutiveDays(), 1);
    });

    test('consecutive days advance streak through Day 7', () async {
      var clock = DateTime(2026, 5, 1);
      final repo = _loginRepo(now: () => clock);

      const expected = [50, 100, 150, 200, 300, 500, 1000];
      for (int i = 0; i < 7; i++) {
        clock = DateTime(2026, 5, 1).add(Duration(days: i));
        final r = await repo.recordLogin();
        expect(r.claimed, isTrue);
        expect(r.day, i + 1);
        expect(r.coins, expected[i]);
        expect(await repo.getConsecutiveDays(), i + 1);
      }
    });

    test('Day 8 wraps back to Day 1 (the streak cycles)', () async {
      final storage = InMemoryLoginStorage();
      var clock = DateTime(2026, 5, 1);
      final repo = _loginRepo(now: () => clock, storage: storage);

      // Run through all 7 days.
      for (int i = 0; i < 7; i++) {
        clock = DateTime(2026, 5, 1).add(Duration(days: i));
        await repo.recordLogin();
      }
      // 8th consecutive day → Day 1 again.
      clock = DateTime(2026, 5, 8);
      final r = await repo.recordLogin();
      expect(r.day, 1);
      expect(r.coins, 50);
      expect(await repo.getConsecutiveDays(), 1);
    });

    test('missing a day resets streak to Day 1', () async {
      var clock = DateTime(2026, 5, 1);
      final repo = _loginRepo(now: () => clock);

      // Day 1, Day 2 in a row.
      await repo.recordLogin();
      clock = DateTime(2026, 5, 2);
      await repo.recordLogin();
      expect(await repo.getConsecutiveDays(), 2);

      // Skip May 3rd; come back on May 4th. Gap == 2 days → reset.
      clock = DateTime(2026, 5, 4);
      final r = await repo.recordLogin();
      expect(r.day, 1);
      expect(r.coins, 50);
      expect(await repo.getConsecutiveDays(), 1);
    });

    test('isClaimAvailable flips correctly across day boundaries', () async {
      var clock = DateTime(2026, 5, 1, 23, 59);
      final repo = _loginRepo(now: () => clock);

      expect(await repo.isClaimAvailable(), isTrue);
      await repo.recordLogin();
      expect(await repo.isClaimAvailable(), isFalse);

      // One minute later — same day, still false.
      clock = DateTime(2026, 5, 2, 0, 0);
      expect(await repo.isClaimAvailable(), isTrue);
    });

    test('getPendingReward previews without mutating state', () async {
      var clock = DateTime(2026, 5, 1);
      final repo = _loginRepo(now: () => clock);

      // Day 1 preview before any claim.
      expect(await repo.getPendingReward(), 50);
      expect(await repo.getConsecutiveDays(), 0);

      // After Day 1 claim + day-rollover, preview shows Day 2 reward.
      await repo.recordLogin();
      clock = DateTime(2026, 5, 2);
      expect(await repo.getPendingReward(), 100);
      expect(await repo.getConsecutiveDays(), 1);

      // Same-day re-check returns 0 (already claimed).
      await repo.recordLogin();
      expect(await repo.getPendingReward(), 0);
    });
  });

  group('AdRewardRepository daily cap', () {
    test('starts with full budget on a fresh install', () async {
      var clock = DateTime(2026, 5, 1);
      final repo = _adRepo(now: () => clock);
      expect(await repo.getRemainingAdRewards(), AdRewardRepository.dailyLimit);
      expect(await repo.canRewardToday(), isTrue);
    });

    test('records up to the daily limit then refuses further calls', () async {
      var clock = DateTime(2026, 5, 1);
      final repo = _adRepo(now: () => clock);

      for (int i = 0; i < AdRewardRepository.dailyLimit; i++) {
        expect(await repo.recordAdReward(), isTrue,
            reason: 'reward $i should land');
      }
      // 6th attempt — over the cap.
      expect(await repo.recordAdReward(), isFalse);
      expect(await repo.getRemainingAdRewards(), 0);
      expect(await repo.canRewardToday(), isFalse);
    });

    test('coins-per-reward is the spec value', () {
      final repo = _adRepo(now: DateTime.now);
      expect(repo.getCoinsForAdReward(), AdRewardRepository.coinsPerReward);
    });

    test('counter resets when the calendar day rolls over', () async {
      var clock = DateTime(2026, 5, 1);
      final repo = _adRepo(now: () => clock);

      // Burn through today's budget.
      for (int i = 0; i < AdRewardRepository.dailyLimit; i++) {
        await repo.recordAdReward();
      }
      expect(await repo.canRewardToday(), isFalse);

      // Tomorrow.
      clock = DateTime(2026, 5, 2);
      expect(await repo.canRewardToday(), isTrue);
      expect(await repo.getRemainingAdRewards(), AdRewardRepository.dailyLimit);
    });
  });

  group('CoinRepository balance stream', () {
    test('emits new balance after addCoins', () async {
      final repo = CoinRepository(storage: InMemoryCoinStorage());
      final received = <int>[];
      final sub = repo.balanceStream.listen(received.add);

      await repo.addCoins(50);
      await repo.addCoins(20);

      // Allow the broadcast to flush before snapshotting.
      await Future<void>.delayed(Duration.zero);

      expect(received, [50, 70]);
      await sub.cancel();
      await repo.dispose();
    });

    test('emits new balance after spendCoins', () async {
      final repo = CoinRepository(storage: InMemoryCoinStorage());
      await repo.addCoins(100);

      final received = <int>[];
      final sub = repo.balanceStream.listen(received.add);

      await repo.spendCoins(30);
      await Future<void>.delayed(Duration.zero);
      expect(received, [70]);
      await sub.cancel();
      await repo.dispose();
    });

    test('does not emit when amount is zero or negative', () async {
      final repo = CoinRepository(storage: InMemoryCoinStorage());
      final received = <int>[];
      final sub = repo.balanceStream.listen(received.add);

      await repo.addCoins(0);
      await repo.addCoins(-10);
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      await sub.cancel();
      await repo.dispose();
    });
  });
}
