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
import 'services/audio_service.dart';
import 'services/audio_service_impl.dart';
import 'services/google_play_games_stub.dart';
import 'services/settings_service.dart';
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
  final adService = AdService(rewardRepo: adRewardRepo, settings: settings);

  final achievementManager = AchievementManager();
  await achievementManager.load();
  final ghostRunner = GhostRunner();
  await ghostRunner.load();
  const gameServices = GooglePlayGamesStub();

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
