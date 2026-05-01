// screens/game_screen.dart
//
// Flutter shell that hosts the FreefallGame instance and the two
// gameplay overlays:
//
//  * PauseScreen — shown on back-button press while alive. Routes to
//    Resume / Restart / Settings / Quit.
//  * RunSummaryScreen — shown the moment the player dies. Resolves the
//    run's RunStats, persists lifetime counters via StatsRepository,
//    and offers Revive / Play Again / 2× coins.
//
// The FreefallGame instance is built once in initState and reused
// across runs (Player.respawn + game.restartRun rebuild the world
// without rebuilding Flame). Engine pause/resume goes through
// game.pauseEngine / resumeEngine so physics also stops.

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../app/app_routes.dart';
import '../components/achievement_popup.dart';
import '../game/freefall_game.dart';
import '../models/achievement.dart';
import '../models/player_skin.dart';
import '../services/google_play_games_stub.dart';
import '../systems/achievement_manager.dart';
import 'pause_screen.dart';
import 'run_summary_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final FreefallGame _game;
  final AchievementPopupController _popupController =
      AchievementPopupController();

  bool _paused = false;
  bool _showSummary = false;

  /// Cached so we can re-wire achievement callbacks once dependencies
  /// resolve in didChangeDependencies (the first build is when
  /// AppDependencies is reachable).
  AchievementManager? _achievementManager;

  /// Phase 13: equipped skin pulled from the StoreRepository. Used to
  /// tint the share-image orb. Defaults to the default skin so the
  /// summary screen renders even before the async lookup lands.
  SkinId _equippedSkinForShare = SkinId.defaultOrb;

  @override
  void initState() {
    super.initState();
    _game = FreefallGame();
    // Wire the run-end hook now so death triggers the summary even
    // if it lands before the first build (e.g. a debug warp-to-death).
    _game.onRunEnded = _onRunEnded;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Wire the achievement manager into the game's signal hooks once
    // the InheritedWidget is available. didChangeDependencies fires
    // before the first build, so the player will see popups even on
    // their very first run.
    final deps = AppDependencies.of(context);
    final mgr = deps.achievementManager;
    if (identical(mgr, _achievementManager)) return;
    _achievementManager = mgr;
    mgr.onAchievementUnlocked = _onAchievementUnlocked;
    mgr.onRunStarted();
    _game.achievementManager = mgr;
    _game.ghostRunner = deps.ghostRunner;
    _game.audio = deps.audioService;
    // Mirror the latest settings into the audio service so a player
    // who muted between runs doesn't hear the next session.
    deps.audioService.syncFromSettings(deps.settings);
    deps.ghostRunner.onRunStarted();
    // Phase 13: snapshot the equipped skin once for the share card.
    // Async — fire-and-forget; defaults stand in until the lookup
    // resolves.
    _resolveEquippedSkin(deps);
  }

  Future<void> _resolveEquippedSkin(AppDependencies deps) async {
    final skin = await deps.storeRepo.getEquippedSkin();
    if (!mounted) return;
    setState(() => _equippedSkinForShare = skin);
  }

  void _onAchievementUnlocked(Achievement ach) {
    _popupController.enqueue(ach);
  }

  // ---- pause flow ---------------------------------------------------------

  void _setPaused(bool paused) {
    setState(() {
      _paused = paused;
      if (paused) {
        _game.pauseEngine();
      } else if (!_showSummary) {
        // Don't resume if the summary is up — that's a different state.
        _game.resumeEngine();
      }
    });
  }

  Future<bool> _handleBackPressed() async {
    if (_showSummary) {
      // While the summary is up, back == quit to menu.
      return true;
    }
    if (_paused) return true; // already paused — allow exit.
    _setPaused(true);
    return false;
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).pushNamed(AppRoutes.settings);
    if (!mounted) return;
    // After returning from Settings, stay paused — the player will
    // tap Resume explicitly.
  }

  // ---- run flow -----------------------------------------------------------

  void _onRunEnded() {
    if (!mounted) return;
    setState(() => _showSummary = true);
    // Pause the engine so the death animation freezes behind the
    // summary card; the player resumes a fresh run via Play Again.
    _game.pauseEngine();
    // Fire-and-forget the lifetime stats persistence so the summary
    // shows the resolved isNewHighScore flag.
    _persistRunStats();
  }

  Future<void> _persistRunStats() async {
    final deps = AppDependencies.of(context);
    final raw = _game.scoreManager.snapshot(isNewHighScore: false);
    final resolved = await deps.statsRepo.updateAfterRun(raw);
    // Phase 10: feed the resolved run into the achievement manager so
    // lifetime + best-of-run unlocks can fire from the summary screen.
    // Persisted by syncExternals so coin/near-miss totals stay current.
    await deps.achievementManager.updateFromRunStats(resolved, deps.statsRepo);
    final coinBalance = await deps.coinRepo.getLifetimeEarned();
    final streak = await deps.loginRepo.getConsecutiveDays();
    await deps.achievementManager.syncExternals(
      lifetimeCoins: coinBalance,
      consecutiveDays: streak,
    );
    // Phase 10: persist the new best-run ghost iff the score beat the
    // previous best.
    await deps.ghostRunner.maybeSaveBestRun(resolved.score);
    // Phase 13: submit both score and depth to their respective Play
    // Games / Game Center leaderboards. The service no-ops when the
    // user is offline / not signed in so this stays fire-and-forget.
    await deps.gameServices.submitScore(
      leaderboardId: GooglePlayGamesService.bestScoreLeaderboardId,
      score: resolved.score,
    );
    await deps.gameServices.submitDepthScore(resolved.depthMeters);
    // Phase 11: stop the in-game music and play the new-high fanfare
    // if the run beat the previous record. We stop music regardless
    // so the summary screen isn't drowned out by a zone loop.
    await deps.audioService.stopMusic();
    if (resolved.isNewHighScore) {
      deps.audioService.playNewHighScore();
    }
    // Phase 12: poke the interstitial counter. The service handles
    // the every-3rd-game-over pacing + the no-ads short-circuit, so
    // the call site stays a one-liner.
    await deps.adService.showInterstitialAd();
    if (!mounted) return;
    setState(() {
      // Stash the resolved stats so the summary widget rebuilds with
      // the correct isNewHighScore flag.
      _resolvedStats = resolved;
    });
  }

  /// Resolved run stats from StatsRepository. Null until the async
  /// update lands — we render a thin loading scrim in the meantime.
  dynamic _resolvedStats;

  void _restartRun() {
    setState(() {
      _showSummary = false;
      _paused = false;
      _resolvedStats = null;
    });
    _achievementManager?.onRunStarted();
    _game.restartRun();
    _game.resumeEngine();
  }

  @override
  void dispose() {
    _popupController.dispose();
    super.dispose();
  }

  void _quitToMenu() {
    Navigator.of(context).maybePop();
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);
    return PopScope(
      canPop: _paused || _showSummary,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _handleBackPressed();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            GameWidget<FreefallGame>(game: _game),
            if (_paused && !_showSummary)
              PauseScreen(
                onResume: () => _setPaused(false),
                onRestart: _restartRun,
                onOpenSettings: _openSettings,
                onQuit: _quitToMenu,
              ),
            if (_showSummary)
              RunSummaryScreen(
                stats: _resolvedStats ??
                    _game.scoreManager.snapshot(isNewHighScore: false),
                adService: deps.adService,
                coinRepo: deps.coinRepo,
                shareService: deps.shareService,
                equippedSkin: _equippedSkinForShare,
                onPlayAgain: _restartRun,
                onRevive: () {
                  // Phase-9 minimal revive: restart the run. A "true"
                  // revive that resumes mid-fall lands when the live
                  // continue-from-checkpoint state machine ships.
                  _restartRun();
                },
              ),
            // Phase 10: achievement popup overlay rides above the
            // game canvas but below pause/summary so unlocks stay
            // visible mid-run and freeze in place when the game is
            // paused.
            AchievementPopupOverlay(controller: _popupController),
          ],
        ),
      ),
    );
  }
}
