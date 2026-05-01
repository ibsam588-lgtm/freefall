// app/app_dependencies.dart
//
// Single InheritedWidget that exposes the long-lived repositories +
// services to every screen in the app. Lets `onGenerateRoute` build
// any screen by name without each route having to thread a 6-arg
// constructor list.
//
// Tests construct an [AppDependencies] directly with in-memory
// fakes; production builds it once in main.dart from the real
// SharedPreferences/secure-storage backed repos.

import 'package:flutter/widgets.dart';

import '../repositories/ad_reward_repository.dart';
import '../repositories/coin_repository.dart';
import '../repositories/daily_login_repository.dart';
import '../repositories/stats_repository.dart';
import '../repositories/store_repository.dart';
import '../services/ad_service.dart';
import '../services/audio_service.dart';
import '../services/google_play_games_stub.dart';
import '../services/iap_service.dart';
import '../services/settings_service.dart';
import '../systems/achievement_manager.dart';
import '../systems/ghost_runner.dart';

class AppDependencies extends InheritedWidget {
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

  const AppDependencies({
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
    required super.child,
  });

  /// Look up the AppDependencies above [context]. Throws (clear
  /// message) if the widget tree forgot to wrap a screen — caller's
  /// fault, not the user's, so a hard failure is correct.
  static AppDependencies of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<AppDependencies>();
    assert(result != null, 'AppDependencies missing — wrap MaterialApp in it.');
    return result!;
  }

  @override
  bool updateShouldNotify(AppDependencies oldWidget) {
    // Repos are immutable references for the life of the app — only
    // re-notify if the host swaps them, which it never does.
    return settings != oldWidget.settings ||
        coinRepo != oldWidget.coinRepo ||
        loginRepo != oldWidget.loginRepo ||
        storeRepo != oldWidget.storeRepo ||
        statsRepo != oldWidget.statsRepo ||
        adRewardRepo != oldWidget.adRewardRepo ||
        adService != oldWidget.adService ||
        achievementManager != oldWidget.achievementManager ||
        ghostRunner != oldWidget.ghostRunner ||
        gameServices != oldWidget.gameServices ||
        audioService != oldWidget.audioService ||
        iapService != oldWidget.iapService;
  }
}
