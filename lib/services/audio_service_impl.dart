// services/audio_service_impl.dart
//
// Centralized audio dispatch for SFX and zone music. flame_audio is
// pre-cached on boot so the first hit/coin doesn't stutter.
//
// Asset filenames listed in [_sfx] and [_music] are the source of truth
// for assets/audio/ — the release-prep tooling reads this file to know
// which placeholders to ship.

import 'package:flame_audio/flame_audio.dart';

class AudioServiceImpl {
  AudioServiceImpl._();
  static final AudioServiceImpl instance = AudioServiceImpl._();

  bool _muted = false;

  static const List<String> _sfx = <String>[
    'coin_pickup.mp3',
    'coin_combo.mp3',
    'player_hit.mp3',
    'player_death.mp3',
    'powerup.mp3',
    'ui_click.mp3',
    'achievement.mp3',
    'daily_reward.mp3',
    'zone_transition.mp3',
  ];

  static const List<String> _music = <String>[
    'music_stratosphere.mp3',
    'music_city.mp3',
    'music_underground.mp3',
    'music_ocean.mp3',
    'music_core.mp3',
  ];

  static List<String> get allAssets => <String>[..._sfx, ..._music];

  Future<void> preload() async {
    await FlameAudio.audioCache.loadAll(allAssets);
  }

  void setMuted(bool muted) => _muted = muted;
  bool get isMuted => _muted;

  void playCoinPickup() => _play('coin_pickup.mp3');
  void playCoinCombo() => _play('coin_combo.mp3');
  void playHit() => _play('player_hit.mp3');
  void playDeath() => _play('player_death.mp3');
  void playPowerup() => _play('powerup.mp3');
  void playClick() => _play('ui_click.mp3');
  void playAchievement() => _play('achievement.mp3');
  void playDailyReward() => _play('daily_reward.mp3');
  void playZoneTransition() => _play('zone_transition.mp3');

  void playZoneMusic(String track) {
    if (_muted) return;
    FlameAudio.bgm.play(track);
  }

  void stopMusic() => FlameAudio.bgm.stop();

  void _play(String name) {
    if (_muted) return;
    FlameAudio.play(name);
  }
}
