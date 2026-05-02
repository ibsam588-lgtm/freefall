// main.dart
//
// App entry point. Locks the device to portrait, attempts a Firebase
// init (gracefully no-ops without provisioning files), bootstraps
// every persistent store + service, and hands the tree off to the
// MaterialApp running through the named-route table from
// [AppRoutes.generateRoute].
//
// All long-lived dependencies are constructed once here and exposed
// to descendant screens via [AppDependencies] so route handlers don't
// have to thread typed args through RouteSettings.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_dependencies.dart';
import 'app/app_routes.dart';
import 'repositories/ad_reward_repository.dart';
import 'repositories/coin_repository.dart';
import 'repositories/daily_login_repository.dart';
import 'repositories/stats_repository.dart';
import 'repositories/store_repository.dart';
import 'services/ad_service.dart';
import 'services/admob_service.dart';
import 'services/analytics_service.dart';
import 'services/audio_service.dart';
import 'services/audio_service_impl.dart';
import 'services/crashlytics_service.dart';
import 'services/firebase_service.dart';
import 'services/google_play_games_service.dart';
import 'services/google_play_games_stub.dart';
import 'services/iap_service.dart';
import 'services/settings_service.dart';
import 'services/share_service.dart';
import 'systems/achievement_manager.dart';
import 'systems/ghost_runner.dart';
import 'systems/performance_monitor.dart';

Future<void> main() async {
  // Required before any platform-channel work (Firebase, orientation, etc.).
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  // Phase 14: Firebase bootstrap. Returns null-backed Analytics +
  // Crashlytics on a fresh checkout (missing google-services.json),
  // and the real Firebase-backed services once provisioning lands.
  // See android/SETUP.md for the file the platform expects.
  final firebase = await FirebaseService.initialize();
  final AnalyticsService analytics = firebase.analytics;
  final CrashlyticsService crashlytics = firebase.crashlytics;

  // Phase 7+8+9: prefetch user prefs and build the persistent stores.
  // Each repo caches its own SharedPreferences/secure-storage future
  // internally so the first read fills it — no need to await anything
  // beyond settings here.
  final settings = SettingsService();
  await settings.load();
  final coinRepo = CoinRepository();
  final loginRepo = DailyLoginRepository();
  final storeRepo = StoreRepository(coinRepo: coinRepo);
  final statsRepo = StatsRepository();
  final adRewardRepo = AdRewardRepository();
  // Phase 12: real AdMob backend (rewarded + interstitial preload).
  // Defensive — every google_mobile_ads call is wrapped in try/catch
  // inside the service so a missing native plugin doesn't crash boot.
  final AdService adService = AdmobService(
    rewardRepo: adRewardRepo,
    settings: settings,
    rewardedAdUnitId: AdmobService.prodRewardedAdUnitId,
    interstitialAdUnitId: AdmobService.prodInterstitialAdUnitId,
  );
  if (adService is AdmobService) {
    // Fire and forget — load up the first rewarded + interstitial in
    // the background so the first show feels instant.
    unawaited(adService.loadAds());
  }

  // Phase 12: in-app purchase facade. init() subscribes to the
  // platform purchase stream + queries product details. Defensive
  // internals — works even when no platform plugin is registered.
  final iapService = IapService(
    coinRepo: coinRepo,
    storeRepo: storeRepo,
    settings: settings,
  );
  unawaited(iapService.init());

  // Phase 13: real Play Games / Game Center backend. The plugin
  // tolerates platforms without native bindings (web, headless tests)
  // by surfacing errors through its async returns; we wrap it
  // defensively inside the service so a missing plugin gracefully
  // collapses to the no-op base class behavior.
  final GooglePlayGamesService gameServices = GamesServicesPlayGames();
  final ghostRunner = GhostRunner();
  await ghostRunner.load();
  final shareService = ShareService();
  final achievementManager = AchievementManager(
    gameServices: gameServices,
    analytics: analytics,
  );
  await achievementManager.load();

  // Phase 11: real flame_audio backend. Every primitive is wrapped in
  // try/catch so missing asset files (we ship without them) won't
  // crash the game. Initial flag state mirrors SettingsService.
  final AudioService audioService = FlameAudioService(
    soundEnabled: settings.soundEnabled,
    musicEnabled: settings.musicEnabled,
  );

  // Phase 14: rolling-frame perf monitor. Owned at app scope so the
  // running game can read it from update() and gameplay components
  // can poll it from render() without threading it through every
  // constructor.
  final performanceMonitor = PerformanceMonitor();

  runApp(FreefallApp(
    settings: settings,
    coinRepo: coinRepo,
    loginRepo: loginRepo,
    storeRepo: storeRepo,
    statsRepo: statsRepo,
    adRewardRepo: adRewardRepo,
    adService: adService,
    achievementManager: achievementManager,
    ghostRunner: ghostRunner,
    gameServices: gameServices,
    audioService: audioService,
    iapService: iapService,
    shareService: shareService,
    analytics: analytics,
    crashlytics: crashlytics,
    performanceMonitor: performanceMonitor,
  ));
}

class FreefallApp extends StatelessWidget {
  final SettingsService settings;
  final CoinRepository coinRepo;
  final DailyLoginRepository loginRepo;
  final StoreRepository storeRepo;
  final StatsRepository statsRepo;
  final AdRewardRepository adRewardRepo;
  final AdService adService;
  final AchievementManager achievementManager;
  final GhostRunner ghostRunner;
  final GooglePlayGamesService gameServices;
  final AudioService audioService;
  final IapService iapService;
  final ShareService shareService;
  final AnalyticsService analytics;
  final CrashlyticsService crashlytics;
  final PerformanceMonitor performanceMonitor;

  const FreefallApp({
    super.key,
    required this.settings,
    required this.coinRepo,
    required this.loginRepo,
    required this.storeRepo,
    required this.statsRepo,
    required this.adRewardRepo,
    required this.adService,
    required this.achievementManager,
    required this.ghostRunner,
    required this.gameServices,
    required this.audioService,
    required this.iapService,
    required this.shareService,
    required this.analytics,
    required this.crashlytics,
    required this.performanceMonitor,
  });

  @override
  Widget build(BuildContext context) {
    return AppDependencies(
      settings: settings,
      coinRepo: coinRepo,
      loginRepo: loginRepo,
      storeRepo: storeRepo,
      statsRepo: statsRepo,
      adRewardRepo: adRewardRepo,
      adService: adService,
      achievementManager: achievementManager,
      ghostRunner: ghostRunner,
      gameServices: gameServices,
      audioService: audioService,
      iapService: iapService,
      shareService: shareService,
      analytics: analytics,
      crashlytics: crashlytics,
      performanceMonitor: performanceMonitor,
      child: MaterialApp(
        title: 'Freefall',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        initialRoute: AppRoutes.menu,
        onGenerateRoute: AppRoutes.generateRoute,
      ),
    );
  }
}
