// Phase-11 audio facade tests.
//
// AudioService is a thin pass-through over four primitive hooks
// (playSfxFile / playMusicFile / stopMusicFile / setMusicVolumeOnPlayer).
// We verify:
//   * NullAudioService never throws on any public surface,
//   * sound/music flags short-circuit the public methods,
//   * volumes clamp to [0, 1],
//   * playZoneMusic dedups same-zone calls,
//   * coin/gem pickups feed the right pitch into playSfxFile,
//   * file id table covers every zone/coin tier.
//
// We use a [_RecordingAudioService] subclass that captures every
// primitive call so assertions can read what the service *attempted*
// to do without a real audio backend present.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/models/collectible.dart';
import 'package:freefall/models/zone.dart';
import 'package:freefall/services/audio_service.dart';

class _SfxCall {
  final String file;
  final double volume;
  final double rate;
  const _SfxCall(this.file, this.volume, this.rate);
}

class _MusicCall {
  final String file;
  final double volume;
  const _MusicCall(this.file, this.volume);
}

class _RecordingAudioService extends AudioService {
  _RecordingAudioService({
    super.soundEnabled,
    super.musicEnabled,
    super.musicVolume,
    super.sfxVolume,
  });

  final List<_SfxCall> sfxCalls = [];
  final List<_MusicCall> musicCalls = [];
  final List<double> volumeChanges = [];
  int stopMusicCount = 0;

  @override
  @protected
  Future<void> playSfxFile(
    String file, {
    double volume = 1.0,
    double rate = 1.0,
  }) async {
    sfxCalls.add(_SfxCall(file, volume, rate));
  }

  @override
  @protected
  Future<void> playMusicFile(String file, double volume) async {
    musicCalls.add(_MusicCall(file, volume));
  }

  @override
  @protected
  Future<void> stopMusicFile() async {
    stopMusicCount++;
  }

  @override
  @protected
  Future<void> setMusicVolumeOnPlayer(double volume) async {
    volumeChanges.add(volume);
  }
}

void main() {
  group('NullAudioService', () {
    test('every public method is a safe no-op', () async {
      final svc = NullAudioService();
      // None of these should throw.
      await svc.playZoneMusic(ZoneType.stratosphere);
      await svc.stopMusic();
      await svc.setMusicVolume(0.5);
      await svc.setSfxVolume(0.5);
      svc.playCoinCollect(CoinType.bronze);
      svc.playGemCollect(GemType.gold);
      svc.playPowerupPickup(PowerupType.shield);
      svc.playHitImpact();
      svc.playNearMiss();
      svc.playDeath();
      svc.playRespawn();
      svc.playZoneTransition();
      svc.playSpeedGate();
      svc.playNewHighScore();
      svc.playUiTap();
      svc.playStorePurchase();
      svc.playWhoosh(1.0);
    });

    test('NullAudioService starts with both flags off', () {
      final svc = NullAudioService();
      expect(svc.soundEnabled, isFalse);
      expect(svc.musicEnabled, isFalse);
    });
  });

  group('AudioFiles table', () {
    test('every ZoneType has a file', () {
      for (final z in ZoneType.values) {
        expect(AudioFiles.forZone(z), isNotEmpty);
      }
    });

    test('every CoinType has a file', () {
      for (final c in CoinType.values) {
        expect(AudioFiles.forCoin(c), isNotEmpty);
      }
    });

    test('zone files are unique', () {
      final files = ZoneType.values.map(AudioFiles.forZone).toSet();
      expect(files.length, ZoneType.values.length);
    });

    test('coin files are unique', () {
      final files = CoinType.values.map(AudioFiles.forCoin).toSet();
      expect(files.length, CoinType.values.length);
    });
  });

  group('Flag short-circuits', () {
    test('soundEnabled = false suppresses every SFX call', () {
      final svc = _RecordingAudioService(soundEnabled: false);
      svc.playCoinCollect(CoinType.gold);
      svc.playGemCollect(GemType.silver);
      svc.playPowerupPickup(PowerupType.magnet);
      svc.playHitImpact();
      svc.playNearMiss();
      svc.playDeath();
      svc.playRespawn();
      svc.playZoneTransition();
      svc.playSpeedGate();
      svc.playNewHighScore();
      svc.playUiTap();
      svc.playStorePurchase();
      svc.playWhoosh(1.5);
      expect(svc.sfxCalls, isEmpty);
    });

    test('soundEnabled = true forwards SFX through to the primitive',
        () {
      final svc = _RecordingAudioService(soundEnabled: true);
      svc.playHitImpact();
      svc.playNearMiss();
      expect(svc.sfxCalls.length, 2);
      expect(svc.sfxCalls[0].file, AudioFiles.hitImpact);
      expect(svc.sfxCalls[1].file, AudioFiles.nearMiss);
    });

    test('musicEnabled = false drops zone music + leaves player at rest',
        () async {
      final svc = _RecordingAudioService(musicEnabled: false);
      await svc.playZoneMusic(ZoneType.core);
      expect(svc.musicCalls, isEmpty);
      expect(svc.activeMusicFile, isNull);
    });

    test('musicEnabled = true plays the zone track', () async {
      final svc = _RecordingAudioService(musicEnabled: true);
      await svc.playZoneMusic(ZoneType.deepOcean);
      expect(svc.musicCalls.length, 1);
      expect(svc.musicCalls[0].file, AudioFiles.zoneOcean);
      expect(svc.activeMusicFile, AudioFiles.zoneOcean);
    });
  });

  group('playZoneMusic dedup', () {
    test('repeating the same zone is a no-op', () async {
      final svc = _RecordingAudioService(musicEnabled: true);
      await svc.playZoneMusic(ZoneType.stratosphere);
      await svc.playZoneMusic(ZoneType.stratosphere);
      expect(svc.musicCalls.length, 1);
      expect(svc.stopMusicCount, 1,
          reason: 'first call still stops any prior music');
    });

    test('switching zones stops then plays the new track', () async {
      final svc = _RecordingAudioService(musicEnabled: true);
      await svc.playZoneMusic(ZoneType.stratosphere);
      await svc.playZoneMusic(ZoneType.city);
      expect(svc.musicCalls.length, 2);
      expect(svc.musicCalls[0].file, AudioFiles.zoneStratosphere);
      expect(svc.musicCalls[1].file, AudioFiles.zoneCity);
      expect(svc.stopMusicCount, 2);
    });

    test('stopMusic clears the active file so the next playZoneMusic '
        'replays the same track', () async {
      final svc = _RecordingAudioService(musicEnabled: true);
      await svc.playZoneMusic(ZoneType.core);
      await svc.stopMusic();
      expect(svc.activeMusicFile, isNull);
      await svc.playZoneMusic(ZoneType.core);
      expect(svc.musicCalls.length, 2,
          reason: 'after stop, the same zone should re-play');
    });
  });

  group('Volume clamping', () {
    test('setMusicVolume clamps below 0 to 0', () async {
      final svc = _RecordingAudioService();
      await svc.setMusicVolume(-1.0);
      expect(svc.musicVolume, 0.0);
      expect(svc.volumeChanges.last, 0.0);
    });

    test('setMusicVolume clamps above 1 to 1', () async {
      final svc = _RecordingAudioService();
      await svc.setMusicVolume(99);
      expect(svc.musicVolume, 1.0);
    });

    test('setMusicVolume preserves valid mid-range values', () async {
      final svc = _RecordingAudioService();
      await svc.setMusicVolume(0.42);
      expect(svc.musicVolume, closeTo(0.42, 1e-9));
    });

    test('setSfxVolume clamps both ends', () async {
      final svc = _RecordingAudioService();
      await svc.setSfxVolume(-3);
      expect(svc.sfxVolume, 0.0);
      await svc.setSfxVolume(2);
      expect(svc.sfxVolume, 1.0);
    });

    test('constructor volumes are clamped', () {
      final svc = _RecordingAudioService(musicVolume: 5, sfxVolume: -1);
      expect(svc.musicVolume, 1.0);
      expect(svc.sfxVolume, 0.0);
    });

    test('playWhoosh clamps speedFactor into [0.5, 2.0]', () {
      final svc = _RecordingAudioService();
      svc.playWhoosh(0.1);
      svc.playWhoosh(99);
      expect(svc.sfxCalls[0].rate, 0.5);
      expect(svc.sfxCalls[1].rate, 2.0);
    });
  });

  group('Coin/gem pitch table', () {
    test('coin pitches match the spec (1.0 / 1.1 / 1.2 / 1.5)', () {
      final svc = _RecordingAudioService();
      svc.playCoinCollect(CoinType.bronze);
      svc.playCoinCollect(CoinType.silver);
      svc.playCoinCollect(CoinType.gold);
      svc.playCoinCollect(CoinType.diamond);
      expect(svc.sfxCalls.map((c) => c.rate).toList(),
          [1.0, 1.1, 1.2, 1.5]);
      expect(svc.sfxCalls.map((c) => c.file).toList(), [
        AudioFiles.coinBronze,
        AudioFiles.coinSilver,
        AudioFiles.coinGold,
        AudioFiles.coinDiamond,
      ]);
    });

    test('gem pitches climb monotonically and share one file', () {
      final svc = _RecordingAudioService();
      svc.playGemCollect(GemType.bronze);
      svc.playGemCollect(GemType.silver);
      svc.playGemCollect(GemType.gold);
      final rates = svc.sfxCalls.map((c) => c.rate).toList();
      expect(rates[0] < rates[1], isTrue);
      expect(rates[1] < rates[2], isTrue);
      expect(svc.sfxCalls.every((c) => c.file == AudioFiles.gemCollect),
          isTrue);
    });
  });

  group('AudioService.fromSettings + syncFromSettings', () {
    test('fromSettings mirrors the initial flag state', () {
      final svc = NullAudioService(); // start muted
      expect(svc.soundEnabled, isFalse);
      expect(svc.musicEnabled, isFalse);
    });

    test('flipping a flag back on does NOT auto-resume music — the host '
        'has to call playZoneMusic explicitly', () async {
      final svc = _RecordingAudioService(musicEnabled: true);
      await svc.playZoneMusic(ZoneType.city);
      svc.musicEnabled = false;
      await svc.stopMusic(); // simulate syncFromSettings tearing it down
      expect(svc.activeMusicFile, isNull);

      svc.musicEnabled = true;
      // Without a re-call, no new music plays.
      expect(svc.musicCalls.length, 1);
    });
  });
}
