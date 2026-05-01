// services/firebase_service.dart
//
// Phase 14 Firebase bootstrap. main.dart used to call
// `Firebase.initializeApp` directly — that worked for Phase 1, but
// once Analytics + Crashlytics layered on top we need a single place
// that:
//   1. boots Firebase.initializeApp,
//   2. wires Crashlytics' Flutter / async error handlers,
//   3. flips analytics-collection on for production builds,
//   4. swallows the "missing google-services.json" failure mode so
//      `flutter run` keeps working on a fresh checkout.
//
// Returns a [FirebaseBootstrapResult] describing what actually
// initialized — main.dart uses that to decide whether to construct
// the real Analytics / Crashlytics services or stay on the null
// implementations.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'analytics_service.dart';
import 'crashlytics_service.dart';
import 'firebase_analytics_service.dart';

/// Resolution of [FirebaseService.initialize]. Both fields are
/// non-null — the caller decides whether to wire the real or null
/// backend by checking [didInitialize].
class FirebaseBootstrapResult {
  /// True iff `Firebase.initializeApp` succeeded. False on a build
  /// without google-services.json / GoogleService-Info.plist.
  final bool didInitialize;

  /// Analytics backend to wire into AppDependencies. Real impl on
  /// success, null impl on fallback.
  final AnalyticsService analytics;

  /// Crashlytics backend, same pattern as [analytics].
  final CrashlyticsService crashlytics;

  const FirebaseBootstrapResult({
    required this.didInitialize,
    required this.analytics,
    required this.crashlytics,
  });
}

class FirebaseService {
  /// Boot Firebase + downstream telemetry. Idempotent only for the
  /// caller — `Firebase.initializeApp` itself isn't safe to call
  /// twice; main.dart only calls this once.
  static Future<FirebaseBootstrapResult> initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[FirebaseService] initializeApp skipped: $e\n$st');
      }
      return const FirebaseBootstrapResult(
        didInitialize: false,
        analytics: AnalyticsService(),
        crashlytics: CrashlyticsService(),
      );
    }

    // Firebase booted — wire the real Analytics + Crashlytics.
    final analytics = FirebaseAnalyticsService();
    final crashlytics = FirebaseCrashlyticsService();
    try {
      await crashlytics.initialize();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FirebaseService] crashlytics.initialize: $e');
      }
    }

    return FirebaseBootstrapResult(
      didInitialize: true,
      analytics: analytics,
      crashlytics: crashlytics,
    );
  }
}
