// services/admob_service.dart
//
// Phase 12 real AdMob implementation. Extends the Phase-7
// [AdService] surface so existing callers (run_summary_screen,
// daily_login_screen) keep working — only the wiring at AppRoot
// changes from `AdService(...)` to `AdmobService(...)`.
//
// Behavior layered on top of the base class:
//   * Preloads a rewarded ad + interstitial + rewarded-interstitial on
//     construction so the first show feels instant.
//   * `showRewardedAd` consults the loaded RewardedAd; if present,
//     shows it and credits coins through [AdRewardRepository] like
//     the stub did. If load failed or no ad is queued, falls back
//     to the base class' simulated outcome so testing/dev still
//     works.
//   * `showInterstitialAd` keeps a `_runEndedCount` counter — every
//     third game-over presents the interstitial. The no-ads IAP
//     short-circuits the show (counter still increments so the
//     pacing stays consistent if the user later refunds).
//   * `showRewardedInterstitialAd` mirrors the rewarded path but for
//     the rewarded-interstitial format (interstitial that grants a
//     reward on completion).
//   * `createBannerAd` returns a configured BannerAd that callers can
//     mount via [AdWidget]. The service exposes the unit id; the
//     caller owns the size + lifecycle.
//
// Defensive: every `google_mobile_ads` call sits inside a try/catch.
// The AdMob plugin throws on platforms without native bindings (web,
// CI) — we swallow those and log in debug so the rest of the app
// keeps working.
//
// Test seam: `presentRewardedAd`, `presentInterstitial`, and
// `presentRewardedInterstitial` are `@protected` virtuals. Tests
// subclass and count invocations, without requiring a real Mobile
// Ads SDK.

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
  // ---- AdMob test ad unit ids (debug builds) ------------------------------
  // Safe for dev — Google guarantees these always fill with house ads.

  static const String testBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String testInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String testRewardedInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/5354046379';

  // ---- Production ad unit ids (release builds) ---------------------------
  // Tied to the Freefall AdMob app — do not edit without re-issuing in
  // the AdMob console.

  static const String prodAppId =
      'ca-app-pub-8127360916614638~4291290335';
  static const String prodBannerAdUnitId =
      'ca-app-pub-8127360916614638/2076190538';
  static const String prodInterstitialAdUnitId =
      'ca-app-pub-8127360916614638/2978208669';
  static const String prodRewardedAdUnitId =
      'ca-app-pub-8127360916614638/7303543045';
  static const String prodRewardedInterstitialAdUnitId =
      'ca-app-pub-8127360916614638/7959072600';

  /// Build-mode aware default ad unit ids. `kReleaseMode` is true in
  /// `flutter run --release` and any signed APK/AAB — debug + profile
  /// fall through to the test ids so a dev build never serves a real
  /// impression.
  static String get defaultBannerAdUnitId =>
      kReleaseMode ? prodBannerAdUnitId : testBannerAdUnitId;
  static String get defaultInterstitialAdUnitId =>
      kReleaseMode ? prodInterstitialAdUnitId : testInterstitialAdUnitId;
  static String get defaultRewardedAdUnitId =>
      kReleaseMode ? prodRewardedAdUnitId : testRewardedAdUnitId;
  static String get defaultRewardedInterstitialAdUnitId => kReleaseMode
      ? prodRewardedInterstitialAdUnitId
      : testRewardedInterstitialAdUnitId;

  /// Show an interstitial every Nth game-over. The classic mobile
  /// arcade pacing — frequent enough to monetize, rare enough not to
  /// burn the player out.
  static const int interstitialFrequency = 3;

  /// Cool-off after a load failure before we retry. Long enough that
  /// a flaky network or temporary outage doesn't burn battery on
  /// constant retries.
  static const Duration retryDelay = Duration(seconds: 60);

  /// Override for the banner ad unit id (production / staging).
  final String bannerAdUnitId;

  /// Override for the rewarded ad unit id (production / staging).
  final String rewardedAdUnitId;

  /// Override for the interstitial ad unit id.
  final String interstitialAdUnitId;

  /// Override for the rewarded-interstitial ad unit id.
  final String rewardedInterstitialAdUnitId;

  AdmobService({
    required super.rewardRepo,
    required super.settings,
    String? bannerAdUnitId,
    String? interstitialAdUnitId,
    String? rewardedAdUnitId,
    String? rewardedInterstitialAdUnitId,
  })  : bannerAdUnitId = bannerAdUnitId ?? defaultBannerAdUnitId,
        interstitialAdUnitId =
            interstitialAdUnitId ?? defaultInterstitialAdUnitId,
        rewardedAdUnitId = rewardedAdUnitId ?? defaultRewardedAdUnitId,
        rewardedInterstitialAdUnitId = rewardedInterstitialAdUnitId ??
            defaultRewardedInterstitialAdUnitId;

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

  /// True iff a rewarded-interstitial is loaded and ready to show.
  bool get isRewardedInterstitialReady => _rewardedInterstitialAd != null;

  // ---- internals ---------------------------------------------------------

  RewardedAd? _rewardedAd;
  InterstitialAd? _interstitialAd;
  RewardedInterstitialAd? _rewardedInterstitialAd;
  bool _rewardedLoading = false;
  bool _interstitialLoading = false;
  bool _rewardedInterstitialLoading = false;
  Timer? _rewardedRetry;
  Timer? _interstitialRetry;
  Timer? _rewardedInterstitialRetry;

  /// Track whether we've already initialized MobileAds. Idempotent —
  /// `MobileAds.instance.initialize()` returns a cached future after
  /// the first call but we guard so [loadAds] reads cleanly.
  bool _mobileAdsInitialized = false;

  // ---- public API --------------------------------------------------------

  /// Initialize the Mobile Ads SDK and preload one of each full-screen
  /// format. Banner ads are created on demand by callers (size +
  /// lifecycle belong to the host widget). Call once at app start;
  /// subsequent calls are no-ops.
  Future<void> loadAds() async {
    await _initMobileAds();
    _loadRewardedAd();
    _loadInterstitialAd();
    _loadRewardedInterstitialAd();
  }

  /// Build a [BannerAd] sized for the caller. The widget owns the
  /// returned ad's lifecycle — call `.load()` and `.dispose()` from
  /// the host widget. Returns null on platforms without native
  /// bindings so callers can fall back to a placeholder.
  BannerAd? createBannerAd({
    AdSize size = AdSize.banner,
    BannerAdListener? listener,
  }) {
    try {
      return BannerAd(
        adUnitId: bannerAdUnitId,
        size: size,
        request: const AdRequest(),
        listener: listener ??
            BannerAdListener(
              onAdFailedToLoad: (ad, error) {
                ad.dispose();
                if (kDebugMode) {
                  debugPrint('[AdmobService] banner load failed: $error');
                }
              },
            ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AdmobService] banner construction skipped: $e');
      }
      return null;
    }
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

  /// Present a rewarded-interstitial. Same contract as [showRewardedAd]
  /// but uses the rewarded-interstitial format (interstitial that
  /// grants a reward on completion). Honors the daily ad-reward cap
  /// and falls back to the simulated path when no ad is loaded.
  Future<AdRewardOutcome> showRewardedInterstitialAd({
    required void Function(int coins) onRewarded,
    required void Function() onFailed,
  }) async {
    if (!await canShowRewardedAd()) {
      onFailed();
      return AdRewardOutcome.unavailable;
    }
    final presentation = await presentRewardedInterstitial();
    switch (presentation) {
      case RewardedPresentation.earned:
        final recorded = await rewardRepo.recordAdReward();
        if (!recorded) {
          onFailed();
          return AdRewardOutcome.unavailable;
        }
        onRewarded(rewardRepo.getCoinsForAdReward());
        return AdRewardOutcome.granted;
      case RewardedPresentation.abandoned:
        onFailed();
        return AdRewardOutcome.failed;
      case RewardedPresentation.unavailable:
        return super.showRewardedAd(
          onRewarded: onRewarded,
          onFailed: onFailed,
        );
    }
  }

  /// Drop everything in flight. Called from a hot-reload path or when
  /// switching ad services in dev.
  void dispose() {
    _rewardedRetry?.cancel();
    _interstitialRetry?.cancel();
    _rewardedInterstitialRetry?.cancel();
    _rewardedRetry = null;
    _interstitialRetry = null;
    _rewardedInterstitialRetry = null;
    try {
      _rewardedAd?.dispose();
      _interstitialAd?.dispose();
      _rewardedInterstitialAd?.dispose();
    } catch (_) {
      // dispose() can throw on platforms without native plugin support.
      // Swallow — there's nothing we can do about it here.
    }
    _rewardedAd = null;
    _interstitialAd = null;
    _rewardedInterstitialAd = null;
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

  /// Show the loaded rewarded-interstitial. Mirrors [presentRewardedAd]
  /// but uses the [RewardedInterstitialAd] type from google_mobile_ads.
  @protected
  Future<RewardedPresentation> presentRewardedInterstitial() async {
    final ad = _rewardedInterstitialAd;
    if (ad == null) return RewardedPresentation.unavailable;
    final completer = Completer<RewardedPresentation>();
    _rewardedInterstitialAd = null;

    ad.fullScreenContentCallback =
        FullScreenContentCallback<RewardedInterstitialAd>(
      onAdDismissedFullScreenContent: (_) {
        if (!completer.isCompleted) {
          completer.complete(RewardedPresentation.abandoned);
        }
        try {
          ad.dispose();
        } catch (_) {/* see dispose() */}
        _loadRewardedInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (_, __) {
        if (!completer.isCompleted) {
          completer.complete(RewardedPresentation.unavailable);
        }
        try {
          ad.dispose();
        } catch (_) {/* see dispose() */}
        _loadRewardedInterstitialAd();
      },
    );

    try {
      await ad.show(onUserEarnedReward: (_, __) {
        if (!completer.isCompleted) {
          completer.complete(RewardedPresentation.earned);
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AdmobService] show rewarded-interstitial skipped: $e');
      }
      if (!completer.isCompleted) {
        completer.complete(RewardedPresentation.unavailable);
      }
    }
    return completer.future;
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

  void _loadRewardedInterstitialAd() {
    if (_rewardedInterstitialLoading || _rewardedInterstitialAd != null) {
      return;
    }
    _rewardedInterstitialLoading = true;
    try {
      RewardedInterstitialAd.load(
        adUnitId: rewardedInterstitialAdUnitId,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedInterstitialLoading = false;
            _rewardedInterstitialAd = ad;
          },
          onAdFailedToLoad: (error) {
            _rewardedInterstitialLoading = false;
            _rewardedInterstitialAd = null;
            _scheduleRewardedInterstitialRetry();
            if (kDebugMode) {
              debugPrint(
                  '[AdmobService] rewarded-interstitial load failed: $error');
            }
          },
        ),
      );
    } catch (e) {
      _rewardedInterstitialLoading = false;
      _scheduleRewardedInterstitialRetry();
      if (kDebugMode) {
        debugPrint('[AdmobService] rewarded-interstitial load threw: $e');
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

  void _scheduleRewardedInterstitialRetry() {
    _rewardedInterstitialRetry?.cancel();
    _rewardedInterstitialRetry =
        Timer(retryDelay, _loadRewardedInterstitialAd);
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
    this.scriptedRewardedInterstitialOutcome = RewardedPresentation.earned,
  });

  /// Outcome [presentRewardedAd] returns. Defaults to earned so tests
  /// don't have to set it for the happy path.
  RewardedPresentation scriptedRewardedOutcome;

  /// Outcome [presentRewardedInterstitial] returns. Defaults to earned.
  RewardedPresentation scriptedRewardedInterstitialOutcome;

  int interstitialPresentations = 0;
  int rewardedPresentations = 0;
  int rewardedInterstitialPresentations = 0;

  @override
  Future<void> presentInterstitial() async {
    interstitialPresentations++;
  }

  @override
  Future<RewardedPresentation> presentRewardedAd() async {
    rewardedPresentations++;
    return scriptedRewardedOutcome;
  }

  @override
  Future<RewardedPresentation> presentRewardedInterstitial() async {
    rewardedInterstitialPresentations++;
    return scriptedRewardedInterstitialOutcome;
  }
}
