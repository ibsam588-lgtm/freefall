// Phase-15 widget-test harness.
//
// Wraps a screen-under-test in a fully-stubbed [AppDependencies] so
// the widget can call `AppDependencies.of(context)` without the real
// platform plugins booting. Every service is the null backend or an
// in-memory fake — same pattern the unit-test suite uses.
//
// Returns a `Future<Widget>` because some constructors (SettingsService)
// need to await `load()` before the widget reads them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freefall/app/app_dependencies.dart';
import 'package:freefall/repositories/ad_reward_repository.dart';
import 'package:freefall/repositories/coin_repository.dart';
import 'package:freefall/repositories/daily_login_repository.dart';
import 'package:freefall/repositories/stats_repository.dart';
import 'package:freefall/repositories/store_repository.dart';
import 'package:freefall/services/ad_service.dart';
import 'package:freefall/services/analytics_service.dart';
import 'package:freefall/services/audio_service.dart';
import 'package:freefall/services/crashlytics_service.dart';
import 'package:freefall/services/google_play_games_stub.dart';
import 'package:freefall/services/iap_service.dart';
import 'package:freefall/services/settings_service.dart';
import 'package:freefall/services/share_service.dart';
import 'package:freefall/systems/achievement_manager.dart';
import 'package:freefall/systems/ghost_runner.dart';
import 'package:freefall/systems/performance_monitor.dart';

/// Bundle of test fakes — exposed so individual tests can poke them
/// (seed coins, force a login streak, etc.) without re-deriving them.
class WidgetTestEnv {
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

  WidgetTestEnv({
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
}

/// Build a minimal-but-complete [WidgetTestEnv]. [seedCoins] preloads
/// the coin balance so tests can verify currency UI without going
/// through addCoins.
Future<WidgetTestEnv> buildTestEnv({int seedCoins = 0}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsService();
  await settings.load();

  final coinStorage = InMemoryCoinStorage();
  if (seedCoins > 0) {
    coinStorage.seed(CoinRepository.balanceKey, '$seedCoins');
  }
  final coinRepo = CoinRepository(storage: coinStorage);

  // Seed the daily-login storage with "already claimed today" so the
  // login overlay doesn't auto-pop in tests that target the main
  // menu — an opaque modal would intercept all subsequent taps and
  // make button assertions fail with a hit-test warning.
  final loginStorage = InMemoryLoginStorage()
    ..seed(lastLogin: '2026-05-01', consecutiveDays: 1);
  final loginRepo = DailyLoginRepository(
    storage: loginStorage,
    now: () => DateTime(2026, 5, 1),
  );

  final storeRepo = StoreRepository(
    coinRepo: coinRepo,
    storage: InMemoryLoginStorage(),
  );

  final statsRepo = StatsRepository(storage: InMemoryStatsStorage());
  final adRewardRepo = AdRewardRepository(
    storage: InMemoryLoginStorage(),
    now: () => DateTime(2026, 5, 1),
  );
  final adService = AdService(
    rewardRepo: adRewardRepo,
    settings: settings,
  );

  final achievementManager = AchievementManager(
    storage: InMemoryLoginStorage(),
  );
  await achievementManager.load();

  final ghostRunner = GhostRunner(storage: InMemoryLoginStorage());
  await ghostRunner.load();

  const gameServices = GooglePlayGamesStub();
  final audioService = AudioService(
    soundEnabled: false,
    musicEnabled: false,
  );
  final iapService = IapService(
    coinRepo: coinRepo,
    storeRepo: storeRepo,
    settings: settings,
  );
  final shareService = ShareService();
  const analytics = AnalyticsService();
  const crashlytics = CrashlyticsService();
  final performanceMonitor = PerformanceMonitor();

  return WidgetTestEnv(
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
  );
}

/// Wrap [child] in an [AppDependencies] populated from [env] and a
/// [MaterialApp] so screens can navigate. Pass [observer] to capture
/// pushed routes.
Widget wrapWithDeps(
  Widget child,
  WidgetTestEnv env, {
  NavigatorObserver? observer,
  Map<String, WidgetBuilder> additionalRoutes = const {},
}) {
  return AppDependencies(
    settings: env.settings,
    coinRepo: env.coinRepo,
    loginRepo: env.loginRepo,
    storeRepo: env.storeRepo,
    statsRepo: env.statsRepo,
    adRewardRepo: env.adRewardRepo,
    adService: env.adService,
    achievementManager: env.achievementManager,
    ghostRunner: env.ghostRunner,
    gameServices: env.gameServices,
    audioService: env.audioService,
    iapService: env.iapService,
    shareService: env.shareService,
    analytics: env.analytics,
    crashlytics: env.crashlytics,
    performanceMonitor: env.performanceMonitor,
    child: MaterialApp(
      home: child,
      navigatorObservers: [if (observer != null) observer],
      routes: additionalRoutes,
    ),
  );
}

/// NavigatorObserver that captures every pushed route's name.
class RouteRecorder extends NavigatorObserver {
  final List<String?> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route.settings.name);
    super.didPush(route, previousRoute);
  }
}
