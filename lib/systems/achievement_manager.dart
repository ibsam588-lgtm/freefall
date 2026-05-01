// systems/achievement_manager.dart
//
// Phase 10 achievement state machine. Owns:
//   * the 20-row catalog of [Achievement]s,
//   * a set of unlocked ids (persisted),
//   * lifetime + best-of-run counters that feed each achievement's
//     [AchievementType] (also persisted),
//   * an in-memory per-run state struct so "X in one run" achievements
//     can fire mid-run instead of waiting for the summary screen.
//
// The manager is engine-agnostic: no Flame, no Flutter. Tests construct
// it with [InMemoryLoginStorage] and drive it through [onEvent] +
// [updateFromRunStats]. The host wires the unlock callback to the
// achievement popup queue and forwards in-game events.
//
// Persistence layout (on the [LoginStorage] backend):
//   * ach_unlocked        — \x1f-joined string of unlocked achievement ids
//   * ach_total_depth     — accumulated depth fallen across all runs (m)
//   * ach_best_combo      — best combo ever reached
//   * ach_best_gems_run   — most gems ever picked up in a single run
//   * ach_best_speedgates_run
//   * ach_best_zones_run  — most zones entered in a single run (max 5+)
//   * ach_best_zones_no_hit_run — most zones survived no-hit in a run
//   * ach_lightning_deaths
//   * ach_jellyfish_deaths
//   * ach_lava_deaths
//   * ach_reached_core    — 0/1
//   * ach_first_skin      — 0/1 (also derivable from StoreRepository)
//   * ach_upgrade_maxed   — 0/1 (any upgrade at max level)
//
// Lifetime coins / near-misses / consecutive login days are NOT
// persisted here — they live in the existing repos and are mirrored
// into the manager via [updateFromRunStats] / [syncExternals].

import 'dart:async';

import '../models/achievement.dart';
import '../models/run_stats.dart';
import '../repositories/daily_login_repository.dart';
import '../repositories/stats_repository.dart';
import '../services/analytics_service.dart';
import '../services/google_play_games_stub.dart';

/// Discriminator for in-run events fed into [AchievementManager.onEvent].
enum AchievementEventKind {
  /// A new combo count was reached. [AchievementEvent.value] is the
  /// fresh combo number (1, 2, 3, …).
  comboReached,

  /// A gem (any tier) was picked up.
  gemCollected,

  /// The player passed through a speed gate.
  speedGatePassed,

  /// The player took a non-fatal hit. Marks the current zone as "had
  /// a hit", so it won't count toward the no-hit zone achievements.
  playerHit,

  /// The player crossed into a zone. [AchievementEvent.value] is the
  /// zone index in the current cycle (0 = Stratosphere, 4 = Core).
  zoneEntered,

  /// The player bought any non-default skin (drives `first_skin`).
  skinPurchased,

  /// A powerup upgrade reached its catalog max level (drives
  /// `maxed_upgrade`).
  upgradeMaxed,

  /// The player died to a lightning bolt.
  killedByLightning,

  /// The player died after a jellyfish stun encounter.
  killedByJellyfish,

  /// The player died inside a lava jet's flame.
  killedByLavaJet,
}

class AchievementEvent {
  final AchievementEventKind kind;
  final int value;
  const AchievementEvent(this.kind, [this.value = 0]);
}

class AchievementManager {
  // ---- catalog ------------------------------------------------------------

  /// Phase 10 ships 20 achievements, all with coin reward 0. Future
  /// phases can opt in per-row.
  ///
  /// Phase 13 wires a [Achievement.playGamesId] per row so each
  /// in-app unlock mirrors to a Google Play Games / Game Center
  /// achievement. The CgkI_freefall_<id> placeholder format will be
  /// replaced by the real CgkI... ids once Play Console provisioning
  /// lands; the wire-up logic in [AchievementManager._checkAll] uses
  /// whatever value is set, so no other code changes when the real
  /// ids drop in.
  static const String _pgPrefix = 'CgkI_freefall_';

  static const List<Achievement> catalog = <Achievement>[
    Achievement(
      id: 'fall_10km',
      title: 'Skydiver',
      description: 'Fall 10,000m total.',
      targetValue: 10000,
      type: AchievementType.totalDepth,
      playGamesId: '${_pgPrefix}fall_10km',
    ),
    Achievement(
      id: 'fall_50km',
      title: 'Stratonaut',
      description: 'Fall 50,000m total.',
      targetValue: 50000,
      type: AchievementType.totalDepth,
      playGamesId: '${_pgPrefix}fall_50km',
    ),
    Achievement(
      id: 'fall_100km',
      title: 'Centurion',
      description: 'Fall 100,000m total.',
      targetValue: 100000,
      type: AchievementType.totalDepth,
      playGamesId: '${_pgPrefix}fall_100km',
    ),
    Achievement(
      id: 'survive_3zones',
      title: 'Untouchable',
      description: 'Survive 3 zones without being hit in one run.',
      targetValue: 3,
      type: AchievementType.zoneCompleteNoHit,
      playGamesId: '${_pgPrefix}survive_3zones',
    ),
    Achievement(
      id: 'combo_10',
      title: 'Combo King',
      description: 'Reach a 10x combo.',
      targetValue: 10,
      type: AchievementType.comboReached,
      playGamesId: '${_pgPrefix}combo_10',
    ),
    Achievement(
      id: 'gems_100_run',
      title: 'Gem Hoarder',
      description: 'Collect 100 gems in one run.',
      targetValue: 100,
      type: AchievementType.gemsInRun,
      playGamesId: '${_pgPrefix}gems_100_run',
    ),
    Achievement(
      id: 'first_skin',
      title: 'Drip Check',
      description: 'Buy your first cosmetic skin.',
      targetValue: 1,
      type: AchievementType.firstSkinBought,
      playGamesId: '${_pgPrefix}first_skin',
    ),
    Achievement(
      id: 'maxed_upgrade',
      title: 'Maxed Out',
      description: 'Max out any powerup upgrade.',
      targetValue: 1,
      type: AchievementType.upgradeMaxed,
      playGamesId: '${_pgPrefix}maxed_upgrade',
    ),
    Achievement(
      id: 'reach_core',
      title: 'To the Core',
      description: 'Reach the Core zone.',
      targetValue: 1,
      type: AchievementType.reachedCore,
      playGamesId: '${_pgPrefix}reach_core',
    ),
    Achievement(
      id: 'lightning_death',
      title: 'Conductor',
      description: 'Die to a lightning bolt.',
      targetValue: 1,
      type: AchievementType.lightningDeaths,
      playGamesId: '${_pgPrefix}lightning_death',
    ),
    Achievement(
      id: 'jellyfish_death',
      title: 'Stunned Silly',
      description: 'Die to a jellyfish.',
      targetValue: 1,
      type: AchievementType.jellyfishDeaths,
      playGamesId: '${_pgPrefix}jellyfish_death',
    ),
    Achievement(
      id: 'lava_death',
      title: 'Burned Out',
      description: 'Die to a lava jet.',
      targetValue: 1,
      type: AchievementType.lavaDeaths,
      playGamesId: '${_pgPrefix}lava_death',
    ),
    Achievement(
      id: 'coins_1000',
      title: 'Pocket Change',
      description: 'Earn 1,000 coins lifetime.',
      targetValue: 1000,
      type: AchievementType.lifetimeCoins,
      playGamesId: '${_pgPrefix}coins_1000',
    ),
    Achievement(
      id: 'coins_10000',
      title: 'High Roller',
      description: 'Earn 10,000 coins lifetime.',
      targetValue: 10000,
      type: AchievementType.lifetimeCoins,
      playGamesId: '${_pgPrefix}coins_10000',
    ),
    Achievement(
      id: 'near_miss_100',
      title: 'Daredevil',
      description: 'Pull off 100 near-misses lifetime.',
      targetValue: 100,
      type: AchievementType.nearMissesTotal,
      playGamesId: '${_pgPrefix}near_miss_100',
    ),
    Achievement(
      id: 'speed_gates_5',
      title: 'Speed Demon',
      description: 'Pass 5 speed gates in one run.',
      targetValue: 5,
      type: AchievementType.speedGatesInRun,
      playGamesId: '${_pgPrefix}speed_gates_5',
    ),
    Achievement(
      id: 'streak_7',
      title: 'Loyal Faller',
      description: 'Log in 7 consecutive days.',
      targetValue: 7,
      type: AchievementType.consecutiveDays,
      playGamesId: '${_pgPrefix}streak_7',
    ),
    Achievement(
      id: 'all_zones',
      title: 'Tour Guide',
      description: 'Survive all 5 zones in one run.',
      targetValue: 5,
      type: AchievementType.allZonesInRun,
      playGamesId: '${_pgPrefix}all_zones',
    ),
    Achievement(
      id: 'no_hit_zone',
      title: 'Flawless',
      description: 'Complete any zone without being hit.',
      targetValue: 1,
      type: AchievementType.zoneCompleteNoHit,
      playGamesId: '${_pgPrefix}no_hit_zone',
    ),
    Achievement(
      id: 'combo_5_run',
      title: 'Hot Streak',
      description: 'Reach a 5x combo in one run.',
      targetValue: 5,
      type: AchievementType.comboInRun,
      playGamesId: '${_pgPrefix}combo_5_run',
    ),
  ];

  static Achievement? byId(String id) {
    for (final a in catalog) {
      if (a.id == id) return a;
    }
    return null;
  }

  // ---- storage keys -------------------------------------------------------

  static const String _unlockedKey = 'ach_unlocked';
  static const String _delim = '\x1f';

  static const String _kTotalDepth = 'ach_total_depth';
  static const String _kBestCombo = 'ach_best_combo';
  static const String _kBestGemsRun = 'ach_best_gems_run';
  static const String _kBestSpeedGatesRun = 'ach_best_speedgates_run';
  static const String _kBestZonesRun = 'ach_best_zones_run';
  static const String _kBestZonesNoHitRun = 'ach_best_zones_no_hit_run';
  static const String _kLightningDeaths = 'ach_lightning_deaths';
  static const String _kJellyfishDeaths = 'ach_jellyfish_deaths';
  static const String _kLavaDeaths = 'ach_lava_deaths';
  static const String _kReachedCore = 'ach_reached_core';
  static const String _kFirstSkin = 'ach_first_skin';
  static const String _kUpgradeMaxed = 'ach_upgrade_maxed';
  static const String _kBestSingleRunDepth = 'ach_best_single_run_depth';

  // ---- dependencies + state ----------------------------------------------

  final LoginStorage storage;

  /// Phase 13: optional Play Games / Game Center mirror. When wired,
  /// every freshly-unlocked achievement that has a [Achievement.playGamesId]
  /// also fires [GooglePlayGamesService.unlockAchievement]. Null
  /// gracefully no-ops, which lets unit tests skip the platform layer.
  GooglePlayGamesService? gameServices;

  /// Phase 14: optional analytics mirror. Logs `achievement_unlocked`
  /// with the row's stable id every time we flip a fresh row.
  AnalyticsService? analytics;

  AchievementManager({
    LoginStorage? storage,
    this.gameServices,
    this.analytics,
  }) : storage = storage ?? SharedPreferencesLoginStorage();

  /// Fired the first frame [id] flips from locked to unlocked. The host
  /// wires this to the popup queue.
  void Function(Achievement achievement)? onAchievementUnlocked;

  // Persisted counters (cached after [load]).
  int _totalDepth = 0;
  int _bestCombo = 0;
  int _bestGemsInRun = 0;
  int _bestSpeedGatesInRun = 0;
  int _bestZonesInRun = 0;
  int _bestZonesNoHitInRun = 0;
  int _lightningDeaths = 0;
  int _jellyfishDeaths = 0;
  int _lavaDeaths = 0;
  bool _reachedCore = false;
  bool _firstSkinBought = false;
  bool _anyUpgradeMaxed = false;
  int _bestSingleRunDepth = 0;

  // Mirrored from external repos via [syncExternals] / [updateFromRunStats].
  int _lifetimeCoins = 0;
  int _lifetimeNearMisses = 0;
  int _consecutiveDays = 0;

  // Per-run live state.
  int _runGems = 0;
  int _runSpeedGates = 0;
  int _runMaxCombo = 0;
  int _runZonesEntered = 0;
  int _runZonesNoHit = 0;
  bool _currentZoneHadHit = false;

  Set<String> _unlocked = <String>{};
  bool _loaded = false;

  // ---- public reads -------------------------------------------------------

  /// All achievements in the catalog, in display order. Stable.
  List<Achievement> get allAchievements => catalog;

  /// Set of unlocked ids. Returns an unmodifiable view so callers don't
  /// accidentally mutate the internal state.
  Set<String> get unlockedIds => Set.unmodifiable(_unlocked);

  /// True iff [id] is in the unlocked set.
  bool checkUnlocked(String id) => _unlocked.contains(id);

  /// 0..1 progress fraction for [id]. Returns 1.0 once unlocked. Unknown
  /// ids return 0.0.
  double getProgress(String id) {
    final ach = byId(id);
    if (ach == null) return 0.0;
    if (_unlocked.contains(id)) return 1.0;
    if (ach.targetValue <= 0) return 0.0;
    final current = _currentValueFor(ach.type);
    return (current / ach.targetValue).clamp(0.0, 1.0);
  }

  /// Raw counter value backing [type]. Useful for the achievements
  /// screen's "X / Y" label.
  int currentValueFor(AchievementType type) => _currentValueFor(type);

  // ---- load / persist -----------------------------------------------------

  /// Hydrate every counter and the unlocked set from storage. Idempotent
  /// — calling twice is safe but the second call is a no-op.
  Future<void> load() async {
    if (_loaded) return;
    _totalDepth = await storage.getInt(_kTotalDepth);
    _bestCombo = await storage.getInt(_kBestCombo);
    _bestGemsInRun = await storage.getInt(_kBestGemsRun);
    _bestSpeedGatesInRun = await storage.getInt(_kBestSpeedGatesRun);
    _bestZonesInRun = await storage.getInt(_kBestZonesRun);
    _bestZonesNoHitInRun = await storage.getInt(_kBestZonesNoHitRun);
    _lightningDeaths = await storage.getInt(_kLightningDeaths);
    _jellyfishDeaths = await storage.getInt(_kJellyfishDeaths);
    _lavaDeaths = await storage.getInt(_kLavaDeaths);
    _reachedCore = (await storage.getInt(_kReachedCore)) > 0;
    _firstSkinBought = (await storage.getInt(_kFirstSkin)) > 0;
    _anyUpgradeMaxed = (await storage.getInt(_kUpgradeMaxed)) > 0;
    _bestSingleRunDepth = await storage.getInt(_kBestSingleRunDepth);

    final raw = await storage.getString(_unlockedKey);
    if (raw != null && raw.isNotEmpty) {
      _unlocked = raw.split(_delim).where((s) => s.isNotEmpty).toSet();
    }
    _loaded = true;
  }

  /// Push the latest values for counters that live outside this manager
  /// (lifetime coins, near-misses, login streak) so progress queries can
  /// stay sync. Triggers an unlock check.
  Future<void> syncExternals({
    int? lifetimeCoins,
    int? lifetimeNearMisses,
    int? consecutiveDays,
    bool? firstSkinBought,
    bool? anyUpgradeMaxed,
  }) async {
    if (lifetimeCoins != null) _lifetimeCoins = lifetimeCoins;
    if (lifetimeNearMisses != null) _lifetimeNearMisses = lifetimeNearMisses;
    if (consecutiveDays != null) _consecutiveDays = consecutiveDays;
    if (firstSkinBought != null && firstSkinBought && !_firstSkinBought) {
      _firstSkinBought = true;
      await storage.setInt(_kFirstSkin, 1);
    }
    if (anyUpgradeMaxed != null && anyUpgradeMaxed && !_anyUpgradeMaxed) {
      _anyUpgradeMaxed = true;
      await storage.setInt(_kUpgradeMaxed, 1);
    }
    await _checkAll();
  }

  // ---- per-run hooks ------------------------------------------------------

  /// Drop in-run state. Call at the start of each new run.
  void onRunStarted() {
    _runGems = 0;
    _runSpeedGates = 0;
    _runMaxCombo = 0;
    _runZonesEntered = 0;
    _runZonesNoHit = 0;
    _currentZoneHadHit = false;
  }

  /// Apply a run's [stats] to the lifetime counters and re-mirror
  /// external counters off [statsRepo]. Triggers a full unlock check.
  Future<void> updateFromRunStats(
    RunStats stats,
    StatsRepository statsRepo,
  ) async {
    _totalDepth += stats.depthMeters.round();
    await storage.setInt(_kTotalDepth, _totalDepth);

    if (stats.depthMeters.round() > _bestSingleRunDepth) {
      _bestSingleRunDepth = stats.depthMeters.round();
      await storage.setInt(_kBestSingleRunDepth, _bestSingleRunDepth);
    }

    if (stats.bestCombo > _bestCombo) {
      _bestCombo = stats.bestCombo;
      await storage.setInt(_kBestCombo, _bestCombo);
    }
    if (stats.gemsCollected > _bestGemsInRun) {
      _bestGemsInRun = stats.gemsCollected;
      await storage.setInt(_kBestGemsRun, _bestGemsInRun);
    }

    final snap = await statsRepo.snapshot();
    _lifetimeCoins = snap.totalCoins;
    _lifetimeNearMisses = snap.totalNearMisses;

    await _checkAll();
  }

  /// Pull the latest login streak from [loginRepo]. Triggers a check.
  Future<void> refreshLoginStreak(DailyLoginRepository loginRepo) async {
    _consecutiveDays = await loginRepo.getConsecutiveDays();
    await _checkAll();
  }

  /// Per-event entry point for in-run signals. See [AchievementEventKind]
  /// for what each kind means and what [AchievementEvent.value] carries.
  Future<void> onEvent(AchievementEvent event) async {
    switch (event.kind) {
      case AchievementEventKind.comboReached:
        if (event.value > _runMaxCombo) _runMaxCombo = event.value;
        if (event.value > _bestCombo) {
          _bestCombo = event.value;
          await storage.setInt(_kBestCombo, _bestCombo);
        }
        break;

      case AchievementEventKind.gemCollected:
        _runGems++;
        if (_runGems > _bestGemsInRun) {
          _bestGemsInRun = _runGems;
          await storage.setInt(_kBestGemsRun, _bestGemsInRun);
        }
        break;

      case AchievementEventKind.speedGatePassed:
        _runSpeedGates++;
        if (_runSpeedGates > _bestSpeedGatesInRun) {
          _bestSpeedGatesInRun = _runSpeedGates;
          await storage.setInt(_kBestSpeedGatesRun, _bestSpeedGatesInRun);
        }
        break;

      case AchievementEventKind.playerHit:
        _currentZoneHadHit = true;
        break;

      case AchievementEventKind.zoneEntered:
        // Closing the previous zone: if no hit landed during it, bump
        // the no-hit-zones counter. _runZonesEntered starts at 0; the
        // first zone-entered event is the player's starting zone, so
        // we don't try to "close" a non-existent prior zone.
        if (_runZonesEntered > 0 && !_currentZoneHadHit) {
          _runZonesNoHit++;
          if (_runZonesNoHit > _bestZonesNoHitInRun) {
            _bestZonesNoHitInRun = _runZonesNoHit;
            await storage.setInt(_kBestZonesNoHitRun, _bestZonesNoHitInRun);
          }
        }
        _runZonesEntered++;
        if (_runZonesEntered > _bestZonesInRun) {
          _bestZonesInRun = _runZonesEntered;
          await storage.setInt(_kBestZonesRun, _bestZonesInRun);
        }
        _currentZoneHadHit = false;
        if (event.value == 4 && !_reachedCore) {
          _reachedCore = true;
          await storage.setInt(_kReachedCore, 1);
        }
        break;

      case AchievementEventKind.skinPurchased:
        if (!_firstSkinBought) {
          _firstSkinBought = true;
          await storage.setInt(_kFirstSkin, 1);
        }
        break;

      case AchievementEventKind.upgradeMaxed:
        if (!_anyUpgradeMaxed) {
          _anyUpgradeMaxed = true;
          await storage.setInt(_kUpgradeMaxed, 1);
        }
        break;

      case AchievementEventKind.killedByLightning:
        _lightningDeaths++;
        await storage.setInt(_kLightningDeaths, _lightningDeaths);
        break;

      case AchievementEventKind.killedByJellyfish:
        _jellyfishDeaths++;
        await storage.setInt(_kJellyfishDeaths, _jellyfishDeaths);
        break;

      case AchievementEventKind.killedByLavaJet:
        _lavaDeaths++;
        await storage.setInt(_kLavaDeaths, _lavaDeaths);
        break;
    }
    await _checkAll();
  }

  // ---- internals ----------------------------------------------------------

  int _currentValueFor(AchievementType type) {
    switch (type) {
      case AchievementType.totalDepth:
        return _totalDepth;
      case AchievementType.singleRunDepth:
        return _bestSingleRunDepth;
      case AchievementType.comboReached:
        return _bestCombo;
      case AchievementType.comboInRun:
        return _runMaxCombo;
      case AchievementType.gemsInRun:
        return _bestGemsInRun;
      case AchievementType.firstSkinBought:
        return _firstSkinBought ? 1 : 0;
      case AchievementType.upgradeMaxed:
        return _anyUpgradeMaxed ? 1 : 0;
      case AchievementType.reachedCore:
        return _reachedCore ? 1 : 0;
      case AchievementType.lightningDeaths:
        return _lightningDeaths;
      case AchievementType.jellyfishDeaths:
        return _jellyfishDeaths;
      case AchievementType.lavaDeaths:
        return _lavaDeaths;
      case AchievementType.lifetimeCoins:
        return _lifetimeCoins;
      case AchievementType.nearMissesTotal:
        return _lifetimeNearMisses;
      case AchievementType.speedGatesInRun:
        return _bestSpeedGatesInRun;
      case AchievementType.consecutiveDays:
        return _consecutiveDays;
      case AchievementType.allZonesInRun:
        return _bestZonesInRun;
      case AchievementType.zoneCompleteNoHit:
        return _bestZonesNoHitInRun;
    }
  }

  Future<void> _checkAll() async {
    final newlyUnlocked = <Achievement>[];
    for (final ach in catalog) {
      if (_unlocked.contains(ach.id)) continue;
      final current = _currentValueFor(ach.type);
      if (current >= ach.targetValue) {
        _unlocked.add(ach.id);
        newlyUnlocked.add(ach);
      }
    }
    if (newlyUnlocked.isEmpty) return;

    await storage.setString(_unlockedKey, _unlocked.join(_delim));
    final cb = onAchievementUnlocked;
    final services = gameServices;
    final analyticsSvc = analytics;
    for (final ach in newlyUnlocked) {
      cb?.call(ach);
      // Phase 13: mirror to Play Games / Game Center. Fire-and-forget;
      // unlockAchievement no-ops cleanly when offline / not signed in.
      final pgId = ach.playGamesId;
      if (services != null && pgId != null) {
        unawaited(services.unlockAchievement(pgId));
      }
      // Phase 14: log to analytics. Same fire-and-forget pattern.
      if (analyticsSvc != null) {
        unawaited(analyticsSvc.logAchievementUnlocked(ach.id));
      }
    }
  }
}
