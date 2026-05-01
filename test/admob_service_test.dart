// Phase-12 AdMob service tests.
//
// We can't drive real google_mobile_ads from a unit test (the platform
// plugin requires a host activity / ViewController). Instead we use
// [RecordingAdmobService] from the production code — same class
// hierarchy, same counters, but [presentInterstitial] /
// [presentRewardedAd] are overridden to bump local counters.
//
// What we verify:
//   * `runEndedCount` increments on every `showInterstitialAd` call,
//   * an interstitial is presented exactly every Nth call,
//   * the no-ads flag short-circuits the show but still increments
//     the counter (pacing stays consistent if the player ever
//     refunds the no-ads IAP),
//   * a successful rewarded watch credits coins through
//     [AdRewardRepository] and respects the daily cap,
//   * an abandoned rewarded watch reports failure and credits
//     nothing,
//   * test ad-unit ids are the AdMob test ids spec'd in Phase 12.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freefall/repositories/ad_reward_repository.dart';
import 'package:freefall/repositories/daily_login_repository.dart';
import 'package:freefall/services/ad_service.dart';
import 'package:freefall/services/admob_service.dart';
import 'package:freefall/services/settings_service.dart';

Future<SettingsService> _settings({bool noAds = false}) async {
  SharedPreferences.setMockInitialValues({
    SettingsService.noAdsKey: noAds,
  });
  final s = SettingsService();
  await s.load();
  return s;
}

AdRewardRepository _adRepo({
  DateTime Function()? now,
  InMemoryLoginStorage? storage,
}) {
  return AdRewardRepository(
    storage: storage ?? InMemoryLoginStorage(),
    now: now ?? () => DateTime(2026, 5, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Interstitial pacing', () {
    test('runEndedCount increments on every showInterstitialAd call',
        () async {
      final svc = RecordingAdmobService(
        rewardRepo: _adRepo(),
        settings: await _settings(),
      );
      for (var i = 0; i < 10; i++) {
        await svc.showInterstitialAd();
      }
      expect(svc.runEndedCount, 10);
    });

    test('interstitial fires exactly every 3rd run', () async {
      final svc = RecordingAdmobService(
        rewardRepo: _adRepo(),
        settings: await _settings(),
      );
      // 1, 2: silent. 3: present. 4, 5: silent. 6: present. ... so on.
      for (var i = 0; i < 9; i++) {
        await svc.showInterstitialAd();
      }
      expect(svc.interstitialPresentations, 3);
    });

    test('no-ads flag suppresses presentations but counter advances',
        () async {
      final settings = await _settings(noAds: true);
      final svc = RecordingAdmobService(
        rewardRepo: _adRepo(),
        settings: settings,
      );
      for (var i = 0; i < 9; i++) {
        await svc.showInterstitialAd();
      }
      expect(svc.interstitialPresentations, 0,
          reason: 'no-ads should suppress every interstitial');
      expect(svc.runEndedCount, 9,
          reason: 'pacing counter still advances so refunds restore '
              'the rhythm at the right offset');
    });

    test('flipping no-ads off mid-session restores presentations',
        () async {
      final settings = await _settings(noAds: true);
      final svc = RecordingAdmobService(
        rewardRepo: _adRepo(),
        settings: settings,
      );
      // Three quiet "deaths" while no-ads is on.
      await svc.showInterstitialAd();
      await svc.showInterstitialAd();
      await svc.showInterstitialAd();
      expect(svc.interstitialPresentations, 0);

      // User refunded — no-ads off. Next 3rd-run should fire.
      await settings.setNoAdsPurchased(false);
      await svc.showInterstitialAd();
      await svc.showInterstitialAd();
      await svc.showInterstitialAd();
      expect(svc.interstitialPresentations, 1,
          reason: 'next multiple-of-3 run-end should fire once no-ads '
              'is disabled again');
    });
  });

  group('Rewarded ad', () {
    test('successful watch credits coins through the reward repo',
        () async {
      final repo = _adRepo();
      final svc = RecordingAdmobService(
        rewardRepo: repo,
        settings: await _settings(),
      );
      var credited = 0;
      var failureCount = 0;
      final outcome = await svc.showRewardedAd(
        onRewarded: (coins) => credited = coins,
        onFailed: () => failureCount++,
      );
      expect(outcome, AdRewardOutcome.granted);
      expect(credited, AdRewardRepository.coinsPerReward);
      expect(failureCount, 0);
      expect(svc.rewardedPresentations, 1);
      expect(await repo.getRemainingAdRewards(),
          AdRewardRepository.dailyLimit - 1);
    });

    test('abandoned watch reports failed + credits nothing', () async {
      final repo = _adRepo();
      final svc = RecordingAdmobService(
        rewardRepo: repo,
        settings: await _settings(),
        scriptedRewardedOutcome: RewardedPresentation.abandoned,
      );
      var credited = 0;
      var failureCount = 0;
      final outcome = await svc.showRewardedAd(
        onRewarded: (coins) => credited = coins,
        onFailed: () => failureCount++,
      );
      expect(outcome, AdRewardOutcome.failed);
      expect(credited, 0);
      expect(failureCount, 1);
      expect(await repo.getRemainingAdRewards(),
          AdRewardRepository.dailyLimit);
    });

    test(
        'unavailable presentation falls back to the simulated path '
        '(testForcedOutcome.granted still credits)', () async {
      final repo = _adRepo();
      final svc = RecordingAdmobService(
        rewardRepo: repo,
        settings: await _settings(),
        scriptedRewardedOutcome: RewardedPresentation.unavailable,
      );
      // No real ad → fall back to base AdService simulation.
      svc.testForcedOutcome = AdRewardOutcome.granted;
      var credited = 0;
      final outcome = await svc.showRewardedAd(
        onRewarded: (coins) => credited = coins,
        onFailed: () {},
      );
      expect(outcome, AdRewardOutcome.granted);
      expect(credited, AdRewardRepository.coinsPerReward);
    });

    test('daily cap stops further rewarded watches', () async {
      final repo = _adRepo();
      final svc = RecordingAdmobService(
        rewardRepo: repo,
        settings: await _settings(),
      );
      // Burn through the cap.
      for (var i = 0; i < AdRewardRepository.dailyLimit; i++) {
        await svc.showRewardedAd(onRewarded: (_) {}, onFailed: () {});
      }
      var failCount = 0;
      final outcome = await svc.showRewardedAd(
        onRewarded: (_) {},
        onFailed: () => failCount++,
      );
      expect(outcome, AdRewardOutcome.unavailable);
      expect(failCount, 1);
    });
  });

  group('Test ad unit ids', () {
    test('use the spec\'d AdMob test ids', () {
      expect(AdmobService.testRewardedAdUnitId,
          'ca-app-pub-3940256099942544/5224354917');
      expect(AdmobService.testInterstitialAdUnitId,
          'ca-app-pub-3940256099942544/1033173712');
    });

    test('default constructor wires the test ids', () async {
      final svc = RecordingAdmobService(
        rewardRepo: _adRepo(),
        settings: await _settings(),
      );
      expect(svc.rewardedAdUnitId, AdmobService.testRewardedAdUnitId);
      expect(svc.interstitialAdUnitId,
          AdmobService.testInterstitialAdUnitId);
    });

    test('interstitial frequency is 3', () {
      expect(AdmobService.interstitialFrequency, 3);
    });
  });
}
