// services/crashlytics_service.dart
//
// Phase 14 crashlytics facade. Same pattern as [AnalyticsService]:
// the base class is a complete no-op. The real `firebase_crashlytics`
// implementation lives in [FirebaseCrashlyticsService] below — same
// file because the surface is small and the split-file pattern of
// Phase 13 was already overkill for the Play Games service.
//
// What lands in Crashlytics:
//   * uncaught Flutter framework errors (via [initialize] hooking
//     [FlutterError.onError] + [PlatformDispatcher.onError])
//   * logged messages around interesting events (zone change, IAP
//     attempt, ad load fail) — these become breadcrumbs on the next
//     real crash
//   * the player's resolved user id when sign-in lands

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashlyticsService {
  const CrashlyticsService();

  /// Hook the global Flutter / async error handlers so uncaught
  /// exceptions land in Crashlytics. Default no-op — the base class
  /// is the offline backend.
  Future<void> initialize() async {}

  /// Record a non-fatal exception. Default no-op.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {}

  /// Add a breadcrumb log line. Default no-op.
  Future<void> log(String message) async {}

  /// Set the player's id for crash attribution. Default no-op.
  Future<void> setUserId(String userId) async {}
}

/// Real `firebase_crashlytics` backend. Every plugin call sits
/// inside a try/catch — a missing google-services.json shouldn't
/// crash the boot path.
class FirebaseCrashlyticsService extends CrashlyticsService {
  /// Override for tests — defaults to the singleton.
  final FirebaseCrashlytics? _override;
  FirebaseCrashlytics get _crashlytics =>
      _override ?? FirebaseCrashlytics.instance;

  FirebaseCrashlyticsService({FirebaseCrashlytics? crashlytics})
      : _override = crashlytics,
        super();

  @override
  Future<void> initialize() async {
    try {
      // Catch synchronous Flutter framework errors (rendering,
      // gestures, build phase) and forward to Crashlytics.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        try {
          _crashlytics.recordFlutterError(details);
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                '[FirebaseCrashlyticsService] recordFlutterError: $e');
          }
        }
      };
      // Catch uncaught async errors that escape the zone.
      PlatformDispatcher.instance.onError = (error, stack) {
        try {
          _crashlytics.recordError(error, stack, fatal: true);
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                '[FirebaseCrashlyticsService] recordError(async): $e');
          }
        }
        return true;
      };
      await _crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseCrashlyticsService] initialize: $e');
      }
    }
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    try {
      await _crashlytics.recordError(error, stack, fatal: fatal);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseCrashlyticsService] recordError: $e');
      }
    }
  }

  @override
  Future<void> log(String message) async {
    try {
      await _crashlytics.log(message);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseCrashlyticsService] log: $e');
      }
    }
  }

  @override
  Future<void> setUserId(String userId) async {
    try {
      await _crashlytics.setUserIdentifier(userId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseCrashlyticsService] setUserId: $e');
      }
    }
  }
}
