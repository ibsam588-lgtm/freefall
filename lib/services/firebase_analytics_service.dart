// services/firebase_analytics_service.dart
//
// Phase 14 real backend for [AnalyticsService]. Wraps
// `firebase_analytics`. The base class in [analytics_service.dart] is
// a complete no-op; this subclass overrides each method to call into
// Firebase, with try/catch on every call so a missing native plugin
// (web, headless tests, builds without google-services.json) silently
// degrades to the base class' no-op.
//
// Event names match Phase 14's spec one-for-one. Parameter shape
// matches Firebase's expectations (lowercase snake_case, primitives
// only) so the data lands in the dashboard without per-event mapping.

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import '../models/run_stats.dart';
import '../models/zone.dart';
import 'analytics_service.dart';

class FirebaseAnalyticsService extends AnalyticsService {
  /// Override for tests — defaults to [FirebaseAnalytics.instance].
  /// Looked up lazily so a caller that only exercises the no-op
  /// surface (or the base class) never triggers FirebaseAnalytics
  /// initialization.
  final FirebaseAnalytics? _override;
  FirebaseAnalytics get _analytics =>
      _override ?? FirebaseAnalytics.instance;

  FirebaseAnalyticsService({FirebaseAnalytics? analytics})
      : _override = analytics;

  @override
  Future<void> logRunCompleted(RunStats stats) async {
    await _safeLog('run_completed', {
      'score': stats.score,
      'depth_meters': stats.depthMeters.round(),
      'coins_earned': stats.coinsEarned,
      'gems_collected': stats.gemsCollected,
      'near_misses': stats.nearMisses,
      'best_combo': stats.bestCombo,
      'is_new_high_score': stats.isNewHighScore ? 1 : 0,
    });
  }

  @override
  Future<void> logPurchase(String productId, double price) async {
    await _safeLog('iap_purchase', {
      'product_id': productId,
      'price': price,
      'currency': 'USD',
    });
  }

  @override
  Future<void> logAchievementUnlocked(String achievementId) async {
    await _safeLog('achievement_unlocked', {
      'achievement_id': achievementId,
    });
  }

  @override
  Future<void> logZoneReached(ZoneType zone) async {
    await _safeLog('zone_reached', {'zone': zone.name});
  }

  @override
  Future<void> logAdWatched(String adType) async {
    await _safeLog('ad_watched', {'ad_type': adType});
  }

  @override
  Future<void> logStoreOpened() async {
    await _safeLog('store_opened', null);
  }

  @override
  Future<void> logDailyLogin(int streakDay) async {
    await _safeLog('daily_login', {'streak_day': streakDay});
  }

  @override
  Future<void> setUserProperty(String name, String value) async {
    try {
      await _analytics.setUserProperty(name: name, value: value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseAnalyticsService] setUserProperty: $e');
      }
    }
  }

  @override
  Future<void> setUserId(String? userId) async {
    try {
      await _analytics.setUserId(id: userId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseAnalyticsService] setUserId: $e');
      }
    }
  }

  Future<void> _safeLog(
    String name,
    Map<String, Object>? parameters,
  ) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseAnalyticsService] logEvent($name): $e');
      }
    }
  }
}
