// services/admob_service.dart
//
// Phase 12 real AdMob implementation. Extends the Phase-7
// [AdService] surface so existing callers (run_summary_screen,
// daily_login_screen) keep working — only the wiring at AppRoot
// changes from `AdService(...)` to `AdmobService(...)`.
//
// Behavior layered on top of the base class:
//   * Preloads a rewarded ad + interstitial on construction so the
//     first show feels instant.
//   * `showRewardedAd` consults the loaded RewardedAd; if present,
//     shows it and credits coins through [AdRewardRepository] like
//     the stub did. If load failed or no ad is queued, falls back
//     to the base class' simulated outcome so testing/dev still
//     works.
//   * `showInterstitialAd` keeps a `_runEndedCount` counter — every
//     third game-over presents the interstitial. The no-ads IAP
//     short-circuits the show (counter still increments so the
//     pacing stays consistent if the user later refunds).
//   * Failed loads schedule a retry 60s later; consecutive failures
//     don't stack (we only schedule when nothing is in flight).
//
// Defensive: every `google_mobile_ads` call sits inside a try/catch.
// The AdMob plugin throws on platforms without native bindings (web,
// CI) — we swallow those and log in debug so the rest of the app
// keeps working.
//
// Test seam: `presentRewardedAd` and `presentInterstitial` are
// `@protected` virtuals. Tests subclass and count invocations,
// without requiring a real Mobile Ads SDK.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';

/// Outcome of an internal `presentRewardedAd` call. Lets the base
/// class' [showRewardedAd] decide whether to credit coins.
enum RewardedPresentation {
  /// User watched the ad to completion; coins should be granted.
  earned,

  /// Ad was loaded and shown but the user dismissed before the reward
  /// event fired. No coins.
  abandoned,

  /// No ad was queued, or the platform plugin couldn't present it.
  /// Caller decides whether to fall back to the simulated outcome.
  unavailable,
}

class AdmobService extends AdService {
  /// AdMob test ad unit ids — safe for dev builds. Production replaces
  /// these via build-time injection (an env-flagged constructor would
  /// land in Phase 13).
  static const String testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String testInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';

  /// Show an interstitial every Nth game-over. The classic mobile
  /// arcade pacing — frequent enough to monetize, rare enough not to
  /// burn the player out.
  static const int interstitialFrequency = 3;

  /// Cool-off after a load failure before we retry. Long enough that
  /// a flaky network or temporary outage doesn't burn battery on
  /// constant retries.
  static const Duration retryDelay = Duration(seconds: 60);

  /// Override for the rewarded ad unit id (production / staging).
  final String rewardedAdUnitId;

  /// Override for the interstitial ad unit id.
  final String interstitialAdUnitId;

  AdmobService({
    required super.rewardRepo,
    required super.settings,
    this.rewardedAdUnitId = testRewardedAdUnitId,
    this.interstitialAdUnitId = testInterstitialAdUnitId,
  });

  // ---- public state -------------------------------------------------------

  /// Number of game-overs observed since launch. Increments inside
  /// [showInterstitialAd] regardless of whether an ad was actually
  /// shown so pacing stays predictable across no-ads / load-failed
  /// states.
  int _runEndedCount = 0;
  int get runEndedCount => _runEndedCount;

  /// True iff a rewarded ad is currently loaded and ready to show.
  bool get isRewardedReady => _rewardedAd != null;

  /// True iff an interstitial is loaded and ready to show.
  bool get isInterstitialReady => _interstitialAd != null;

  // ---- internals ---------------------------------------------------------

  RewardedAd? _rewardedAd;
  InterstitialAd? _interstitialAd;
  bool _rewardedLoading = false;
  bool _interstitialLoading = false;
  Timer? _rewardedRetry;
  Timer? _interstitialRetry;

  /// Track whether we've already initialized MobileAds. Idempotent —
  /// `MobileAds.instance.initialize()` returns a cached future after
  /// the first call but we guard so [loadAds] reads cleanly.
  bool _mobileAdsInitialized = false;

  // ---- public API --------------------------------------------------------

  /// Initialize the Mobile Ads SDK and preload one rewarded + one
  /// interstitial. Call once at app start. Subsequent calls are
  /// no-ops — the SDK init is cached and pre-loads only fire when no
  /// ad is currently queued.
  Future<void> loadAds() async {
    await _initMobileAds();
    _loadRewardedAd();
    _loadInterstitialAd();
  }

  @override
  Future<AdRewardOutcome> showRewardedAd({
    required void Function(int coins) onRewarded,
    required void Function() onFailed,
  }) async {
    if (!await canShowRewardedAd()) {
      onFailed();
      return AdRewardOutcome.unavailable;
    }
    final presentation = await presentRewardedAd();
    switch (presentation) {
      case RewardedPresentation.earned:
        final recorded = await rewardRepo.recordAdReward();
        if (!recorded) {
          // Race: cap was hit between canShowRewardedAd and now.
          onFailed();
          return AdRewardOutcome.unavailable;
        }
        onRewarded(rewardRepo.getCoinsForAdReward());
        return AdRewardOutcome.granted;
      case RewardedPresentation.abandoned:
        onFailed();
        return AdRewardOutcome.failed;
      case RewardedPresentation.unavailable:
        // Phase-7 simulator path: when no real ad is loaded the base
        // class' default [showRewardedAd] (or its testForcedOutcome)
        // governs the result. Surface that to the caller so
        // dev/headless builds keep flowing.
        return super.showRewardedAd(
          onRewarded: onRewarded,
          onFailed: onFailed,
        );
    }
  }

  @override
  Future<void> showInterstitialAd() async {
    _runEndedCount++;
    if (isNoAdsActive) return;
    if (_runEndedCount % interstitialFrequency != 0) return;
    await presentInterstitial();
  }

  /// Drop everything in flight. Called from a hot-reload path or when
  /// switching ad services in dev.
  void dispose() {
    _rewardedRetry?.cancel();
    _interstitialRetry?.cancel();
    _rewardedRetry = null;
    _interstitialRetry = null;
    try {
      _rewardedAd?.dispose();
      _interstitialAd?.dispose();
    } catch (_) {
      // dispose() can throw on platforms without native plugin support.
      // Swallow — there's nothing we can do about it here.
    }
    _rewardedAd = null;
    _interstitialAd = null;
  }

  // ---- presentation hooks (test seam) ------------------------------------

  /// Show the loaded rewarded ad. Returns [RewardedPresentation]
  /// describing what happened. Tests override to return canned
  /// values without touching the Mobile Ads SDK.
  @protected
  Future<RewardedPresentation> presentRewardedAd() async {
    final ad = _rewardedAd;
    if (ad == null) return RewardedPresentation.unavailable;
    final completer = Completer<RewardedPresentation>();
    _rewardedAd = null; // ad is single-shot — clear before showing.

    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (_) {
        if (!completer.isCompleted) {
          completer.complete(RewardedPresentation.abandoned);
        }
        try {
          ad.dispose();
        } catch (_) {/* see dispose() */}
        _loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (_, __) {
        if (!completer.isCompleted) {
          completer.complete(RewardedPresentation.unavailable);
        }
        try {
          ad.dispose();
        } catch (_) {/* see dispose() */}
        _loadRewardedAd();
      },
    );

    try {
      await ad.show(onUserEarnedReward: (_, __) {
        if (!completer.isCompleted) {
          completer.complete(RewardedPresentation.earned);
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[AdmobService] show rewarded skipped: $e');
      if (!completer.isCompleted) {
        completer.complete(RewardedPresentation.unavailable);
      }
    }
    return completer.future;
  }

  /// Show the loaded interstitial. No-op + reload on failure.
  @protected
  Future<void> presentInterstitial() async {
    final ad = _interstitialAd;
    if (ad == null) return;
    _interstitialAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (_) {
        try {
          ad.dispose();
        } catch (_) {/* see dispose() */}
        _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (_, __) {
        try {
          ad.dispose();
        } catch (_) {/* see dispose() */}
        _loadInterstitialAd();
      },
    );
    try {
      await ad.show();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AdmobService] show interstitial skipped: $e');
      }
    }
  }

  // ---- load pipeline -----------------------------------------------------

  Future<void> _initMobileAds() async {
    if (_mobileAdsInitialized) return;
    try {
      await MobileAds.instance.initialize();
      _mobileAdsInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AdmobService] MobileAds init skipped: $e');
      }
    }
  }

  void _loadRewardedAd() {
    if (_rewardedLoading || _rewardedAd != null) return;
    _rewardedLoading = true;
    try {
      RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedLoading = false;
            _rewardedAd = ad;
          },
          onAdFailedToLoad: (error) {
            _rewardedLoading = false;
            _rewardedAd = null;
            _scheduleRewardedRetry();
            if (kDebugMode) {
              debugPrint('[AdmobService] rewarded load failed: $error');
            }
          },
        ),
      );
    } catch (e) {
      _rewardedLoading = false;
      _scheduleRewardedRetry();
      if (kDebugMode) {
        debugPrint('[AdmobService] rewarded load threw: $e');
      }
    }
  }

  void _loadInterstitialAd() {
    if (_interstitialLoading || _interstitialAd != null) return;
    _interstitialLoading = true;
    try {
      InterstitialAd.load(
        adUnitId: interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialLoading = false;
            _interstitialAd = ad;
          },
          onAdFailedToLoad: (error) {
            _interstitialLoading = false;
            _interstitialAd = null;
            _scheduleInterstitialRetry();
            if (kDebugMode) {
              debugPrint('[AdmobService] interstitial load failed: $error');
            }
          },
        ),
      );
    } catch (e) {
      _interstitialLoading = false;
      _scheduleInterstitialRetry();
      if (kDebugMode) {
        debugPrint('[AdmobService] interstitial load threw: $e');
      }
    }
  }

  void _scheduleRewardedRetry() {
    _rewardedRetry?.cancel();
    _rewardedRetry = Timer(retryDelay, _loadRewardedAd);
  }

  void _scheduleInterstitialRetry() {
    _interstitialRetry?.cancel();
    _interstitialRetry = Timer(retryDelay, _loadInterstitialAd);
  }
}

/// Test-friendly subclass that records every interstitial / rewarded
/// presentation without touching the Mobile Ads SDK. Concrete in this
/// file so callers can drop it into a test without redeclaring the
/// hook fields each time.
class RecordingAdmobService extends AdmobService {
  RecordingAdmobService({
    required super.rewardRepo,
    required super.settings,
    this.scriptedRewardedOutcome = RewardedPresentation.earned,
  });

  /// Outcome [presentRewardedAd] returns. Defaults to earned so tests
  /// don't have to set it for the happy path.
  RewardedPresentation scriptedRewardedOutcome;

  int interstitialPresentations = 0;
  int rewardedPresentations = 0;

  @override
  Future<void> presentInterstitial() async {
    interstitialPresentations++;
  }

  @override
  Future<RewardedPresentation> presentRewardedAd() async {
    rewardedPresentations++;
    return scriptedRewardedOutcome;
  }
}
