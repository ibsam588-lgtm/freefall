// services/analytics_service.dart
//
// Phase 14 analytics facade. Wraps `firebase_analytics` with the
// same null-default + real-subclass pattern Phase 11/13 used: the
// base class is a concrete no-op so callers can hold an
// AnalyticsService reference without caring whether Firebase booted.
//
// Event taxonomy (kept short — every name lands in the Firebase
// dashboard where they're easier to read short):
//   * run_completed: per-run summary
//   * iap_purchase: a real money purchase succeeded
//   * achievement_unlocked: in-app unlock fired
//   * zone_reached: first time per run
//   * ad_watched: rewarded or interstitial completed
//   * store_opened: store tab tapped
//   * daily_login: streak claim
//
// Every method `try`s on the platform call so a missing
// google-services.json never escalates into a crash. The base class
// no-ops when no real backend is wired — same code path on every
// surface.

import '../models/run_stats.dart';
import '../models/zone.dart';

class AnalyticsService {
  const AnalyticsService();

  /// Fired once per completed run with the resolved [RunStats].
  Future<void> logRunCompleted(RunStats stats) async {}

  /// Fired on a successful IAP. [price] in USD-equivalent dollars
  /// (e.g. 2.99) — Firebase aggregates currency separately.
  Future<void> logPurchase(String productId, double price) async {}

  /// Fired the first time an achievement unlocks.
  Future<void> logAchievementUnlocked(String achievementId) async {}

  /// Fired when the player crosses into a new zone.
  Future<void> logZoneReached(ZoneType zone) async {}

  /// Fired when the player finishes watching an ad. [adType] is one
  /// of "rewarded" / "interstitial".
  Future<void> logAdWatched(String adType) async {}

  /// Fired when the store tab opens — used for funnel analysis.
  Future<void> logStoreOpened() async {}

  /// Fired on a successful daily-login claim. [streakDay] is 1..7.
  Future<void> logDailyLogin(int streakDay) async {}

  /// Set a user-scoped property. Useful for cohort splits in the
  /// dashboard ("equipped_skin", "current_zone").
  Future<void> setUserProperty(String name, String value) async {}

  /// Set the player's anonymized id. Drives session attribution in
  /// dashboards. Phase 14 leaves this no-op on the base class.
  Future<void> setUserId(String? userId) async {}
}

/// Test-friendly subclass that captures every call. Concrete in this
/// file so other code can drop it into a unit test without redeclaring
/// every method.
class RecordingAnalyticsService extends AnalyticsService {
  RecordingAnalyticsService() : super();

  final List<RunStats> runs = [];
  final List<({String productId, double price})> purchases = [];
  final List<String> achievementUnlocks = [];
  final List<ZoneType> zonesReached = [];
  final List<String> adWatches = [];
  int storeOpens = 0;
  final List<int> dailyLogins = [];
  final Map<String, String> userProps = {};
  String? userId;

  @override
  Future<void> logRunCompleted(RunStats stats) async {
    runs.add(stats);
  }

  @override
  Future<void> logPurchase(String productId, double price) async {
    purchases.add((productId: productId, price: price));
  }

  @override
  Future<void> logAchievementUnlocked(String achievementId) async {
    achievementUnlocks.add(achievementId);
  }

  @override
  Future<void> logZoneReached(ZoneType zone) async {
    zonesReached.add(zone);
  }

  @override
  Future<void> logAdWatched(String adType) async {
    adWatches.add(adType);
  }

  @override
  Future<void> logStoreOpened() async {
    storeOpens++;
  }

  @override
  Future<void> logDailyLogin(int streakDay) async {
    dailyLogins.add(streakDay);
  }

  @override
  Future<void> setUserProperty(String name, String value) async {
    userProps[name] = value;
  }

  @override
  Future<void> setUserId(String? userId) async {
    this.userId = userId;
  }
}
