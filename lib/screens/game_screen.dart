// screens/game_screen.dart
//
// Flutter shell that hosts the FreefallGame instance and the two
// gameplay overlays:
//
//  * PauseScreen — shown on back-button press while alive.
//  * RunSummaryScreen — shown after crash effects play out.
//
// Crash impact effects (screen flash, camera shake, BOOM text) are
// Flutter-level overlays — they sit on top of the GameWidget so no
// Flame changes are needed.
//
// Equipped skin/trail are applied to the player once the game has
// finished its async onLoad via game.whenLoaded.

import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../app/app_routes.dart';
import '../components/achievement_popup.dart';
import '../game/freefall_game.dart';
import '../models/achievement.dart';
import '../models/player_skin.dart';
import '../models/trail_effect.dart';
import '../services/google_play_games_stub.dart';
import '../systems/achievement_manager.dart';
import 'pause_screen.dart';
import 'run_summary_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  late final FreefallGame _game;
  final AchievementPopupController _popupController =
      AchievementPopupController();

  // ---- crash-effect state -------------------------------------------------

  late final AnimationController _flashController;
  Timer? _shakeTimer;
  Offset _shakeOffset = Offset.zero;
  bool _showBoom = false;

  // ---- screen state -------------------------------------------------------

  bool _paused = false;
  bool _showSummary = false;

  AchievementManager? _achievementManager;
  SkinId _equippedSkinForShare = SkinId.defaultOrb;

  @override
  void initState() {
    super.initState();
    _game = FreefallGame();
    _game.onRunEnded = _onRunEnded;

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deps = AppDependencies.of(context);
    final mgr = deps.achievementManager;
    if (identical(mgr, _achievementManager)) return;
    _achievementManager = mgr;
    mgr.onAchievementUnlocked = _onAchievementUnlocked;
    mgr.onRunStarted();
    _game.achievementManager = mgr;
    _game.ghostRunner = deps.ghostRunner;
    _game.audio = deps.audioService;
    _game.performanceMonitor = deps.performanceMonitor;
    _game.analytics = deps.analytics;
    deps.audioService.syncFromSettings(deps.settings);
    deps.ghostRunner.onRunStarted();
    _resolveEquippedCosmetics(deps);
  }

  /// Read the equipped skin + trail and apply them to the player once
  /// the game's async onLoad has completed.
  Future<void> _resolveEquippedCosmetics(AppDependencies deps) async {
    final skinId = await deps.storeRepo.getEquippedSkin();
    final trailId = await deps.storeRepo.getEquippedTrail();
    if (!mounted) return;
    setState(() => _equippedSkinForShare = skinId);
    await _game.whenLoaded;
    if (!mounted) return;
    _game.player.setSkin(PlayerSkin.byId(skinId));
    _game.player.setTrail(TrailEffect.byId(trailId));
  }

  void _onAchievementUnlocked(Achievement ach) {
    _popupController.enqueue(ach);
  }

  // ---- crash effects -------------------------------------------------------

  void _startCrashEffects() {
    if (!mounted) return;

    // White screen flash that fades over 350 ms.
    _flashController.forward(from: 0);

    // Camera shake: random offset decaying to zero over ~500 ms.
    int frames = 0;
    const int maxFrames = 15;
    final rng = math.Random();
    _shakeTimer?.cancel();
    _shakeTimer = Timer.periodic(const Duration(milliseconds: 33), (t) {
      if (!mounted || frames >= maxFrames) {
        t.cancel();
        if (mounted) setState(() => _shakeOffset = Offset.zero);
        return;
      }
      frames++;
      final decay = 1 - frames / maxFrames;
      setState(() {
        _shakeOffset = Offset(
          (rng.nextDouble() - 0.5) * 14 * decay,
          (rng.nextDouble() - 0.5) * 8 * decay,
        );
      });
    });

    // "BOOM!" text visible for 500 ms.
    setState(() => _showBoom = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showBoom = false);
    });
  }

  // ---- pause flow ---------------------------------------------------------

  void _setPaused(bool paused) {
    setState(() {
      _paused = paused;
      if (paused) {
        _game.pauseEngine();
      } else if (!_showSummary) {
        _game.resumeEngine();
      }
    });
  }

  Future<bool> _handleBackPressed() async {
    if (_showSummary) return true;
    if (_paused) return true;
    _setPaused(true);
    return false;
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).pushNamed(AppRoutes.settings);
  }

  // ---- run flow -----------------------------------------------------------

  void _onRunEnded() {
    if (!mounted) return;
    _startCrashEffects();
    _persistRunStats();
    // Show summary after crash effects have played.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _showSummary = true);
      _game.pauseEngine();
    });
  }

  Future<void> _persistRunStats() async {
    final deps = AppDependencies.of(context);
    final raw = _game.scoreManager.snapshot(isNewHighScore: false);
    final resolved = await deps.statsRepo.updateAfterRun(raw);
    await deps.achievementManager.updateFromRunStats(resolved, deps.statsRepo);
    final coinBalance = await deps.coinRepo.getLifetimeEarned();
    final streak = await deps.loginRepo.getConsecutiveDays();
    await deps.achievementManager.syncExternals(
      lifetimeCoins: coinBalance,
      consecutiveDays: streak,
    );
    await deps.ghostRunner.maybeSaveBestRun(resolved.score);
    await deps.gameServices.submitScore(
      leaderboardId: GooglePlayGamesService.bestScoreLeaderboardId,
      score: resolved.score,
    );
    await deps.gameServices.submitDepthScore(resolved.depthMeters);
    await deps.audioService.stopMusic();
    if (resolved.isNewHighScore) {
      deps.audioService.playNewHighScore();
    }
    await deps.adService.showInterstitialAd();
    await deps.analytics.logRunCompleted(resolved);
    if (!mounted) return;
    setState(() => _resolvedStats = resolved);
  }

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
    // Re-apply equipped cosmetics for the new run.
    final deps = AppDependencies.of(context);
    _resolveEquippedCosmetics(deps);
  }

  @override
  void dispose() {
    _flashController.dispose();
    _shakeTimer?.cancel();
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
        if (!didPop) await _handleBackPressed();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Game canvas with camera-shake offset.
            Transform.translate(
              offset: _shakeOffset,
              child: GameWidget<FreefallGame>(game: _game),
            ),

            // Screen flash — white overlay animating from opacity 0.7 to 0.
            if (_flashController.isAnimating || _flashController.value > 0)
              AnimatedBuilder(
                animation: _flashController,
                builder: (_, __) => IgnorePointer(
                  child: Container(
                    color: Colors.white.withValues(
                      alpha: (1 - _flashController.value) * 0.7,
                    ),
                  ),
                ),
              ),

            // BOOM text.
            if (_showBoom)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Text(
                      'BOOM!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        shadows: [
                          Shadow(
                              color: Color(0xFFFF4500), blurRadius: 24),
                          Shadow(
                              color: Color(0xFFFFD700), blurRadius: 48),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

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
                onRevive: _restartRun,
              ),

            AchievementPopupOverlay(controller: _popupController),
          ],
        ),
      ),
    );
  }
}
