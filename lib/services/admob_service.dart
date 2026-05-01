// services/admob_service.dart
//
// Thin wrapper around google_mobile_ads. Holds the per-slot ad unit IDs
// and the load/show plumbing for banner, interstitial, and rewarded ads.
//
// IMPORTANT: every ad unit ID below is a TODO placeholder. Before shipping
// a release build, replace them with the real IDs from your AdMob console
// (apps.admob.com → Apps → [Freefall] → Ad units). Leaving placeholders in
// place will fail to load ads.

import 'dart:io' show Platform;

class AdMobService {
  AdMobService._();
  static final AdMobService instance = AdMobService._();

  // ---------- Banner ----------
  // Shown at the bottom of menu screens.
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      // TODO: Replace with your Android banner ad unit ID from AdMob Console.
      return 'TODO_ANDROID_BANNER_AD_UNIT_ID';
    }
    if (Platform.isIOS) {
      // TODO: Replace with your iOS banner ad unit ID from AdMob Console.
      return 'TODO_IOS_BANNER_AD_UNIT_ID';
    }
    throw UnsupportedError('Banner ads are not configured for this platform.');
  }

  // ---------- Interstitial ----------
  // Shown between runs (every Nth game-over) — not on the very first death.
  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      // TODO: Replace with your Android interstitial ad unit ID from AdMob Console.
      return 'TODO_ANDROID_INTERSTITIAL_AD_UNIT_ID';
    }
    if (Platform.isIOS) {
      // TODO: Replace with your iOS interstitial ad unit ID from AdMob Console.
      return 'TODO_IOS_INTERSTITIAL_AD_UNIT_ID';
    }
    throw UnsupportedError(
        'Interstitial ads are not configured for this platform.');
  }

  // ---------- Rewarded video ----------
  // Player-initiated: "watch ad to revive" and "watch ad to double coins".
  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      // TODO: Replace with your Android rewarded video ad unit ID from AdMob Console.
      return 'TODO_ANDROID_REWARDED_AD_UNIT_ID';
    }
    if (Platform.isIOS) {
      // TODO: Replace with your iOS rewarded video ad unit ID from AdMob Console.
      return 'TODO_IOS_REWARDED_AD_UNIT_ID';
    }
    throw UnsupportedError(
        'Rewarded ads are not configured for this platform.');
  }

  // ---------- Rewarded interstitial ----------
  // Optional: used for the "skip the ad and grab a smaller reward" flow.
  static String get rewardedInterstitialAdUnitId {
    if (Platform.isAndroid) {
      // TODO: Replace with your Android rewarded interstitial ad unit ID from AdMob Console.
      return 'TODO_ANDROID_REWARDED_INTERSTITIAL_AD_UNIT_ID';
    }
    if (Platform.isIOS) {
      // TODO: Replace with your iOS rewarded interstitial ad unit ID from AdMob Console.
      return 'TODO_IOS_REWARDED_INTERSTITIAL_AD_UNIT_ID';
    }
    throw UnsupportedError(
        'Rewarded interstitial ads are not configured for this platform.');
  }
}
