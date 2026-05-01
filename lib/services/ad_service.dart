// services/ad_service.dart
//
// Phase-7 stub for the ad layer. The real AdMob integration lands in
// Phase 12; this file gives the rest of the app a stable interface so
// daily-login + run-summary screens can wire their "watch an ad" CTAs
// without the GMA SDK in scope.
//
// Behavior:
//   * `canShowRewardedAd()` reports whether a rewarded ad is available
//     today (daily-cap aware) and not gated by the no-ads IAP.
//   * `showRewardedAd` simulates a successful watch by default; a test
//     hook lets unit tests force a failure path.
//   * `showInterstitialAd` is a no-op placeholder that returns
//     immediately.
//
// The service is intentionally a plain class (not a singleton) so each
// call site can inject a fake. AppRoot constructs the production
// instance once in main.dart.

import '../repositories/ad_reward_repository.dart';
import 'settings_service.dart';

/// What happened on a [showRewardedAd] attempt. The screen branches
/// on this — credit coins on [granted], surface a snack on [failed],
/// no-op on [unavailable].
enum AdRewardOutcome { granted, failed, unavailable }

class AdService {
  /// Repo-of-record for the daily-cap counter.
  final AdRewardRepository rewardRepo;

  /// Source of truth for the no-ads IAP flag. The IAP layer flips it.
  final SettingsService settings;

  /// Test hook: if non-null, [showRewardedAd] resolves to this outcome
  /// instead of the (presumed-success) default. Lets unit tests
  /// exercise the failure path without rigging up a fake AdMob.
  AdRewardOutcome? testForcedOutcome;

  AdService({
    required this.rewardRepo,
    required this.settings,
  });

  /// True when the no-ads IAP has been purchased. Interstitials become
  /// no-ops; rewarded ads still show (the no-ads flag covers
  /// interruption ads only — the user can still opt into rewarded views
  /// for coins).
  bool get isNoAdsActive => settings.noAdsPurchased;

  /// Quick can-we-show check used by the UI to enable/disable buttons.
  /// Hits the daily-cap and the no-ads flag.
  Future<bool> canShowRewardedAd() async {
    return rewardRepo.canRewardToday();
  }

  /// Attempt to show a rewarded ad. The real implementation will be
  /// async/callback-driven; we mirror that shape here so the rest of
  /// the app doesn't churn when AdMob is wired up.
  ///
  /// Calls [onRewarded] with the credited coins on success; calls
  /// [onFailed] otherwise. Returns the [AdRewardOutcome] for callers
  /// that need a single async result instead of two callbacks.
  Future<AdRewardOutcome> showRewardedAd({
    required void Function(int coins) onRewarded,
    required void Function() onFailed,
  }) async {
    if (!await canShowRewardedAd()) {
      onFailed();
      return AdRewardOutcome.unavailable;
    }
    final outcome = testForcedOutcome ?? AdRewardOutcome.granted;
    if (outcome == AdRewardOutcome.granted) {
      final recorded = await rewardRepo.recordAdReward();
      if (!recorded) {
        // Race: cap was hit between canShowRewardedAd and now.
        onFailed();
        return AdRewardOutcome.unavailable;
      }
      onRewarded(rewardRepo.getCoinsForAdReward());
      return AdRewardOutcome.granted;
    }
    onFailed();
    return outcome;
  }

  /// Phase-12 interstitial hook. No-op on this stub.
  Future<void> showInterstitialAd() async {
    if (isNoAdsActive) return;
    // Real impl: wait for ad load, call show(). Stub returns immediately.
  }
}
