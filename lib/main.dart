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

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
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
import 'services/audio_service.dart';
import 'services/audio_service_impl.dart';
import 'services/google_play_games_service.dart';
import 'services/google_play_games_stub.dart';
import 'services/iap_service.dart';
import 'services/settings_service.dart';
import 'services/share_service.dart';
import 'systems/achievement_manager.dart';
import 'systems/ghost_runner.dart';

Future<void> main() async {
  // Required before any platform-channel work (Firebase, orientation, etc.).
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  // WHY: try/catch — Firebase needs platform config files (google-services.json
  // on Android, GoogleService-Info.plist on iOS). Phase 1 ships without them
  // so devs can `flutter run` immediately; analytics/crashlytics get wired in
  // once provisioning happens.
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('Firebase init skipped (no config?): $e\n$st');
    }
  }

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
  );
  await achievementManager.load();

  // Phase 11: real flame_audio backend. Every primitive is wrapped in
  // try/catch so missing asset files (we ship without them) won't
  // crash the game. Initial flag state mirrors SettingsService.
  final AudioService audioService = FlameAudioService(
    soundEnabled: settings.soundEnabled,
    musicEnabled: settings.musicEnabled,
  );

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
