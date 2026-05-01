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
import '../game/freefall_game.dart';
import 'pause_screen.dart';
import 'run_summary_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final FreefallGame _game;

  bool _paused = false;
  bool _showSummary = false;

  @override
  void initState() {
    super.initState();
    _game = FreefallGame();
    // Wire the run-end hook now so death triggers the summary even
    // if it lands before the first build (e.g. a debug warp-to-death).
    _game.onRunEnded = _onRunEnded;
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
    _game.restartRun();
    _game.resumeEngine();
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
                onPlayAgain: _restartRun,
                onRevive: () {
                  // Phase-9 minimal revive: restart the run. A "true"
                  // revive that resumes mid-fall lands when the live
                  // continue-from-checkpoint state machine ships.
                  _restartRun();
                },
              ),
          ],
        ),
      ),
    );
  }
}
