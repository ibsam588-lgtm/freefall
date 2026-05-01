// app/app_routes.dart
//
// Centralized route table. Names + onGenerateRoute live here so
// screens can navigate by string and analytics can report stable
// route names instead of widget identities.
//
// Each screen pulls its dependencies from [AppDependencies.of] —
// no typed args have to flow through RouteSettings.

import 'package:flutter/material.dart';

import '../screens/achievements_screen.dart';
import '../screens/game_screen.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/main_menu_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stats_screen.dart';
import '../screens/store_screen.dart';
import 'app_dependencies.dart';

class AppRoutes {
  static const String menu = '/';
  static const String game = '/game';
  static const String store = '/store';
  static const String stats = '/stats';
  static const String settings = '/settings';
  static const String leaderboard = '/leaderboard';
  static const String achievements = '/achievements';

  /// Hook for `MaterialApp.onGenerateRoute`. Returns null for unknown
  /// names so the framework's own `onUnknownRoute` can take over.
  static Route<dynamic>? generateRoute(RouteSettings settings) {
    return switch (settings.name) {
      menu => MaterialPageRoute<void>(
          settings: settings,
          builder: (ctx) {
            final deps = AppDependencies.of(ctx);
            return MainMenuScreen(
              coinRepo: deps.coinRepo,
              loginRepo: deps.loginRepo,
              storeRepo: deps.storeRepo,
              settings: deps.settings,
            );
          },
        ),
      game => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const GameScreen(),
        ),
      store => MaterialPageRoute<void>(
          settings: settings,
          builder: (ctx) {
            final deps = AppDependencies.of(ctx);
            return StoreScreen(
              coinRepo: deps.coinRepo,
              storeRepo: deps.storeRepo,
              iapService: deps.iapService,
            );
          },
        ),
      stats => MaterialPageRoute<void>(
          settings: settings,
          builder: (ctx) {
            final deps = AppDependencies.of(ctx);
            return StatsScreen(
              statsRepo: deps.statsRepo,
              storeRepo: deps.storeRepo,
              coinRepo: deps.coinRepo,
            );
          },
        ),
      AppRoutes.settings => MaterialPageRoute<void>(
          settings: settings,
          builder: (ctx) {
            final deps = AppDependencies.of(ctx);
            return SettingsScreen(
              settings: deps.settings,
              audioService: deps.audioService,
            );
          },
        ),
      leaderboard => MaterialPageRoute<void>(
          settings: settings,
          builder: (ctx) => LeaderboardScreen(
            gameServices: AppDependencies.of(ctx).gameServices,
          ),
        ),
      achievements => MaterialPageRoute<void>(
          settings: settings,
          builder: (ctx) => AchievementsScreen(
            achievementManager: AppDependencies.of(ctx).achievementManager,
          ),
        ),
      _ => null,
    };
  }
}
