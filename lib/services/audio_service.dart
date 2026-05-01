// services/audio_service.dart
//
// Phase 11 audio facade. AudioService is the high-level surface every
// gameplay system calls into ("play this coin sound", "switch to the
// Core music"). The base class is a complete no-op — game code can
// hold an AudioService and never know whether the audio backend is
// real or stubbed.
//
// The class owns three things:
//   * music + sfx volumes (clamped 0..1),
//   * soundEnabled / musicEnabled flags (set from SettingsService),
//   * the active music file id, so [playZoneMusic] is idempotent
//     within a zone — rebuilding a HUD or pausing the game won't
//     restart the same track.
//
// Everything else routes through four protected primitive hooks:
//   playSfxFile, playMusicFile, stopMusicFile, setMusicVolumeOnPlayer.
// FlameAudioService overrides those to drive flame_audio. NullAudioService
// inherits the base class' no-ops. A test recorder can subclass and
// observe what was *attempted* — independent of any real platform IO.
//
// Crossfade: built on top of stop+start with a tiny dedup so
// re-entering the same zone doesn't restart the loop. A real crossfade
// (two overlapping bgm players) lands when the music files do.

import 'package:flutter/foundation.dart';

import '../models/collectible.dart';
import '../models/zone.dart';
import 'settings_service.dart';

/// Stable file ids per audio asset. Centralized so tests can compare
/// what file was *requested* without hard-coding strings.
class AudioFiles {
  // Zone background music.
  static const String zoneStratosphere = 'zone_stratosphere.mp3';
  static const String zoneCity = 'zone_city.mp3';
  static const String zoneUnderground = 'zone_underground.mp3';
  static const String zoneOcean = 'zone_ocean.mp3';
  static const String zoneCore = 'zone_core.mp3';

  // Coin SFX (one per tier so pitch isn't the only differentiator).
  static const String coinBronze = 'coin_bronze.mp3';
  static const String coinSilver = 'coin_silver.mp3';
  static const String coinGold = 'coin_gold.mp3';
  static const String coinDiamond = 'coin_diamond.mp3';

  // Other gameplay SFX.
  static const String gemCollect = 'gem_collect.mp3';
  static const String powerupPickup = 'powerup_pickup.mp3';
  static const String hitImpact = 'hit_impact.mp3';
  static const String nearMiss = 'near_miss.mp3';
  static const String deathShatter = 'death_shatter.mp3';
  static const String respawn = 'respawn.mp3';
  static const String zoneTransition = 'zone_transition.mp3';
  static const String speedGate = 'speed_gate.mp3';
  static const String highScoreFanfare = 'high_score_fanfare.mp3';
  static const String uiTap = 'ui_tap.mp3';
  static const String storePurchase = 'store_purchase.mp3';
  static const String whoosh = 'whoosh.mp3';

  static String forZone(ZoneType zone) {
    switch (zone) {
      case ZoneType.stratosphere:
        return zoneStratosphere;
      case ZoneType.city:
        return zoneCity;
      case ZoneType.underground:
        return zoneUnderground;
      case ZoneType.deepOcean:
        return zoneOcean;
      case ZoneType.core:
        return zoneCore;
    }
  }

  static String forCoin(CoinType type) {
    switch (type) {
      case CoinType.bronze:
        return coinBronze;
      case CoinType.silver:
        return coinSilver;
      case CoinType.gold:
        return coinGold;
      case CoinType.diamond:
        return coinDiamond;
    }
  }
}

class AudioService {
  /// Honored on every SFX call. False short-circuits before any
  /// primitive IO so a muted player never hits the backend.
  bool soundEnabled;

  /// Honored on every music call.
  bool musicEnabled;

  double _musicVolume = 1.0;
  double _sfxVolume = 1.0;

  /// File id currently playing as background music. Null when stopped.
  /// Drives [playZoneMusic]'s same-zone dedup.
  String? activeMusicFile;

  AudioService({
    this.soundEnabled = true,
    this.musicEnabled = true,
    double musicVolume = 1.0,
    double sfxVolume = 1.0,
  })  : _musicVolume = musicVolume.clamp(0.0, 1.0),
        _sfxVolume = sfxVolume.clamp(0.0, 1.0);

  /// Convenience constructor that pulls initial flag state from the
  /// SettingsService. The flags stay in sync because the settings
  /// screen explicitly pokes [soundEnabled] / [musicEnabled] when the
  /// player toggles them — there's no listener stream needed.
  factory AudioService.fromSettings(SettingsService settings) {
    return AudioService(
      soundEnabled: settings.soundEnabled,
      musicEnabled: settings.musicEnabled,
    );
  }

  /// Pull the current flag state from settings. Call after the player
  /// changes them in the settings screen.
  void syncFromSettings(SettingsService settings) {
    soundEnabled = settings.soundEnabled;
    musicEnabled = settings.musicEnabled;
    if (!musicEnabled) {
      // Asynchronously stop — we don't await here because the caller
      // (settings screen) is mid-build.
      stopMusic();
    }
  }

  // ---- music --------------------------------------------------------------

  double get musicVolume => _musicVolume;
  double get sfxVolume => _sfxVolume;

  /// Switch to the music for [zone]. Same-zone calls are a no-op so
  /// pausing/resuming the game doesn't restart the track. When
  /// [musicEnabled] is false this is silently dropped.
  Future<void> playZoneMusic(ZoneType zone) async {
    if (!musicEnabled) return;
    final file = AudioFiles.forZone(zone);
    if (file == activeMusicFile) return;
    await stopMusicFile();
    activeMusicFile = file;
    await playMusicFile(file, _musicVolume);
  }

  /// Halt any active music. Idempotent.
  Future<void> stopMusic() async {
    activeMusicFile = null;
    await stopMusicFile();
  }

  /// Set the music volume (0..1). Active track is updated live; future
  /// tracks pick the new value up at construction.
  Future<void> setMusicVolume(double v) async {
    _musicVolume = v.clamp(0.0, 1.0);
    await setMusicVolumeOnPlayer(_musicVolume);
  }

  /// Set the SFX volume (0..1). Future SFX use the new value; in-flight
  /// one-shots play through at their original level.
  Future<void> setSfxVolume(double v) async {
    _sfxVolume = v.clamp(0.0, 1.0);
  }

  // ---- SFX ----------------------------------------------------------------

  /// Coin pickup. Pitch shifts with tier so the audio reinforces the
  /// payout — bronze low, diamond high.
  void playCoinCollect(CoinType type) {
    if (!soundEnabled) return;
    final pitch = switch (type) {
      CoinType.bronze => 1.0,
      CoinType.silver => 1.1,
      CoinType.gold => 1.2,
      CoinType.diamond => 1.5,
    };
    playSfxFile(AudioFiles.forCoin(type), volume: _sfxVolume, rate: pitch);
  }

  /// Gem pickup. All tiers share one file (gem_collect.mp3) and lean
  /// on the gem's score popup for differentiation.
  void playGemCollect(GemType type) {
    if (!soundEnabled) return;
    final pitch = switch (type) {
      GemType.bronze => 1.0,
      GemType.silver => 1.15,
      GemType.gold => 1.3,
    };
    playSfxFile(AudioFiles.gemCollect, volume: _sfxVolume, rate: pitch);
  }

  /// Powerup pickup. Same file for every powerup; the visual + HUD
  /// chip carry the meaning.
  void playPowerupPickup(PowerupType type) {
    if (!soundEnabled) return;
    playSfxFile(AudioFiles.powerupPickup, volume: _sfxVolume);
  }

  void playHitImpact() {
    if (!soundEnabled) return;
    playSfxFile(AudioFiles.hitImpact, volume: _sfxVolume);
  }

  void playNearMiss() {
    if (!soundEnabled) return;
    playSfxFile(AudioFiles.nearMiss, volume: _sfxVolume);
  }

  void playDeath() {
    if (!soundEnabled) return;
    playSfxFile(AudioFiles.deathShatter, volume: _sfxVolume);
  }

  void playRespawn() {
    if (!soundEnabled) return;
    playSfxFile(AudioFiles.respawn, volume: _sfxVolume);
  }

  void playZoneTransition() {
    if (!soundEnabled) return;
    playSfxFile(AudioFiles.zoneTransition, volume: _sfxVolume);
  }

  void playSpeedGate() {
    if (!soundEnabled) return;
    playSfxFile(AudioFiles.speedGate, volume: _sfxVolume);
  }

  void playNewHighScore() {
    if (!soundEnabled) return;
    playSfxFile(AudioFiles.highScoreFanfare, volume: _sfxVolume);
  }

  void playUiTap() {
    if (!soundEnabled) return;
    playSfxFile(AudioFiles.uiTap, volume: _sfxVolume);
  }

  void playStorePurchase() {
    if (!soundEnabled) return;
    playSfxFile(AudioFiles.storePurchase, volume: _sfxVolume);
  }

  /// Wind whoosh during the fall. [speedFactor] is clamped to [0.5, 2.0]
  /// and used as the playback rate so the pitch climbs with speed.
  void playWhoosh(double speedFactor) {
    if (!soundEnabled) return;
    final rate = speedFactor.clamp(0.5, 2.0);
    playSfxFile(AudioFiles.whoosh, volume: _sfxVolume, rate: rate);
  }

  // ---- primitive hooks (overridden by FlameAudioService) -----------------
  // The default implementations are no-ops — that's why the base class
  // doubles as the null service. Subclasses MUST NOT throw; they should
  // catch backend errors and return cleanly so a missing audio file
  // never escalates into a crash.

  @protected
  Future<void> playSfxFile(
    String file, {
    double volume = 1.0,
    double rate = 1.0,
  }) async {}

  @protected
  Future<void> playMusicFile(String file, double volume) async {}

  @protected
  Future<void> stopMusicFile() async {}

  @protected
  Future<void> setMusicVolumeOnPlayer(double volume) async {}
}

/// Explicit null implementation. The base [AudioService] is already
/// a no-op; this subclass exists for callers that want a name that
/// reads as "I'm intentionally choosing the silent backend."
class NullAudioService extends AudioService {
  NullAudioService() : super(soundEnabled: false, musicEnabled: false);
}
