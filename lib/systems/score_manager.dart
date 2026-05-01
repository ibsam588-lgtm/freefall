// systems/score_manager.dart
//
// Authoritative scoring + combo state. Owns:
//   * cumulative score (depth tick + bonuses + gem pickups),
//   * combo counter and 5-second timeout,
//   * best-of-run tallies for the summary screen.
//
// Inputs from the rest of the system:
//   * onDepthTick(double meters): called by the host with the current
//     depth in meters; the manager bills the *delta* since the last
//     tick at 1pt/m × scoreMultiplier × comboMultiplier.
//   * onNearMiss / onZoneComplete / onSpeedGate: bonus point hooks.
//   * onCoinCollected / onGemCollected: tally + apply gem score.
//   * onPlayerHit: reset combo and timer (no score change).
//
// Multiplier composition: every score-awarding event multiplies the
// base value by (powerupManager.scoreMultiplier × combo multiplier).
// Coin multiplier from combo (5+ = 2x, 10+ = 3x) is exposed as a
// getter — the host applies it when crediting coins.
//
// ScoreManager is a GameSystem so it ticks the combo timer on the
// fixed-step bus. It does NOT poll depth — the host calls
// onDepthTick each step with the camera's depth reading.

import '../models/run_stats.dart';
import 'powerup_manager.dart';
import 'system_base.dart';

class ScoreManager implements GameSystem {
  /// Combo expires this many seconds after the last near-miss event.
  static const double comboTimeoutSeconds = 5;

  /// Score gained per near-miss (before multipliers).
  static const int nearMissBonus = 50;

  /// Score gained when the player descends into a fresh zone.
  static const int zoneCompletionBonus = 500;

  /// Score gained when the player flies through a speed gate.
  static const int speedGateBonus = 100;

  /// Combo count → score multiplier. Boundaries match the spec.
  static int scoreMultiplierForCombo(int combo) {
    if (combo >= 15) return 10;
    if (combo >= 10) return 8;
    if (combo >= 7) return 6;
    if (combo >= 5) return 4;
    if (combo >= 3) return 3;
    if (combo >= 2) return 2;
    return 1;
  }

  /// Combo count → coin multiplier. Spec: 5+ = 2x, 10+ = 3x.
  static int coinMultiplierForCombo(int combo) {
    if (combo >= 10) return 3;
    if (combo >= 5) return 2;
    return 1;
  }

  /// Optional source for the powerup-driven score multiplier (the
  /// scoreMultiplier powerup, separate from combo).
  PowerupManager? powerupManager;

  /// Optional callback fired whenever the combo counter increments.
  /// The host wires this to the on-screen ComboDisplay.
  void Function(int newCombo)? onComboChanged;

  /// Optional callback fired when the combo resets to zero. Same
  /// wiring as [onComboChanged] — kept separate so the display can
  /// fade out instead of redrawing a "x0".
  void Function()? onComboReset;

  int _score = 0;
  int _combo = 0;
  int _bestCombo = 0;
  double _comboTimer = 0;

  // Maximum depth ever billed this run. Doubles as the floor for the
  // next [onDepthTick] delta — going up doesn't refund or re-bill.
  double _maxDepthMeters = 0;

  // Run-summary tallies — accrue across the run, reset on [reset].
  int _nearMisses = 0;
  int _coinsEarned = 0;
  int _gemsCollected = 0;

  ScoreManager({this.powerupManager});

  // ---- public read-only state ---------------------------------------------

  int get score => _score;
  int get combo => _combo;
  int get bestCombo => _bestCombo;
  double get comboTimeRemaining => _comboTimer;
  bool get hasActiveCombo => _combo > 0;
  int get currentScoreMultiplier => scoreMultiplierForCombo(_combo);
  int get currentCoinMultiplier => coinMultiplierForCombo(_combo);

  /// Run-summary counters, used by [snapshot] when the run ends.
  int get nearMisses => _nearMisses;
  int get coinsEarned => _coinsEarned;
  int get gemsCollected => _gemsCollected;
  double get maxDepthMeters => _maxDepthMeters;

  /// Build the read-only snapshot consumed by the summary screen + the
  /// stats repository. [isNewHighScore] is decided by the caller (it's
  /// the only field that depends on previously-persisted state).
  RunStats snapshot({required bool isNewHighScore}) {
    return RunStats(
      score: _score,
      depthMeters: _maxDepthMeters,
      coinsEarned: _coinsEarned,
      gemsCollected: _gemsCollected,
      nearMisses: _nearMisses,
      bestCombo: _bestCombo,
      isNewHighScore: isNewHighScore,
    );
  }

  // ---- score sources -------------------------------------------------------

  /// Bill the meter-delta between this depth reading and the player's
  /// previous max depth. Going up doesn't refund or re-bill — only
  /// fresh ground past the all-time max is scored. Keeps score
  /// monotonic if the host ever rewinds.
  void onDepthTick(double depthMeters) {
    if (depthMeters <= _maxDepthMeters) return;
    final delta = depthMeters - _maxDepthMeters;
    _maxDepthMeters = depthMeters;
    _score += (delta * _composedMultiplier).round();
  }

  /// Near-miss: bumps combo first, then awards +50pts at the *new*
  /// combo's multiplier. Refreshes the 5s timer.
  ///
  /// Increment-then-award order matters: the player feels rewarded for
  /// reaching a new combo tier on the same event that pushed them
  /// across the boundary.
  void onNearMiss() {
    _combo++;
    if (_combo > _bestCombo) _bestCombo = _combo;
    _comboTimer = comboTimeoutSeconds;
    _nearMisses++;
    _score += (nearMissBonus * _composedMultiplier).round();
    onComboChanged?.call(_combo);
  }

  /// Zone completion: +500pts (multiplied). Does NOT change combo.
  void onZoneComplete() {
    _score += (zoneCompletionBonus * _composedMultiplier).round();
  }

  /// Speed gate: +100pts (multiplied). Does NOT change combo.
  void onSpeedGate() {
    _score += (speedGateBonus * _composedMultiplier).round();
  }

  /// Gem collection: + (gemValue × multipliers). Increments gem tally.
  void onGemCollected(int gemValue) {
    _score += (gemValue * _composedMultiplier).round();
    _gemsCollected++;
  }

  /// Coin collection bookkeeping. Score is NOT awarded (coins go to the
  /// currency balance instead) but the run tally moves so the summary
  /// reads correctly. Caller is responsible for applying
  /// [currentCoinMultiplier] when crediting actual currency.
  void onCoinCollected({int count = 1}) {
    _coinsEarned += count;
  }

  /// Player hit: combo collapses, timer cleared. No score deduction —
  /// damage feels less punishing if it doesn't also rip points away.
  void onPlayerHit() {
    if (_combo == 0) return;
    _combo = 0;
    _comboTimer = 0;
    onComboReset?.call();
  }

  /// Force everything back to zero for a new run.
  void reset() {
    _score = 0;
    _combo = 0;
    _bestCombo = 0;
    _comboTimer = 0;
    _maxDepthMeters = 0;
    _nearMisses = 0;
    _coinsEarned = 0;
    _gemsCollected = 0;
  }

  @override
  void update(double dt) {
    if (_comboTimer <= 0) return;
    _comboTimer -= dt;
    if (_comboTimer <= 0) {
      _comboTimer = 0;
      _combo = 0;
      onComboReset?.call();
    }
  }

  // ---- internals -----------------------------------------------------------

  /// Composed multiplier applied to every score-awarding event:
  ///   powerup score multiplier × combo's score multiplier.
  /// Returned as a double so callers can round once at the end.
  double get _composedMultiplier {
    final powerup = powerupManager?.scoreMultiplier ?? 1.0;
    return powerup * scoreMultiplierForCombo(_combo);
  }
}
