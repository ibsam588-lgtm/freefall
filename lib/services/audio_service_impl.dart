// services/audio_service_impl.dart
//
// Phase 11 real audio backend. Wraps flame_audio (which itself wraps
// audioplayers) so the gameplay code can keep talking to the
// engine-agnostic [AudioService] surface and not care that the
// platform plugins exist.
//
// Defensive on every primitive — flame_audio raises [Exception]s when
// an asset is missing, when the player isn't initialized on a platform
// without audio support (CI, headless tests), or when audioplayers'
// platform plugin throws. We catch broadly and log in debug only so
// the game keeps running on a fresh dev machine that hasn't dropped
// the actual mp3 files in yet.
//
// Pitch shifting (used by [playCoinCollect] and [playWhoosh]) routes
// through audioplayers' [AudioPlayer.setPlaybackRate]; not every
// platform supports it (it's a no-op on web). The base AudioService
// passes a `rate` arg into the primitive — this impl applies it
// post-play, again with try/catch.

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

import 'audio_service.dart';

class FlameAudioService extends AudioService {
  FlameAudioService({
    super.soundEnabled,
    super.musicEnabled,
    super.musicVolume,
    super.sfxVolume,
  });

  // ---- primitive overrides -----------------------------------------------

  @override
  Future<void> playSfxFile(
    String file, {
    double volume = 1.0,
    double rate = 1.0,
  }) async {
    try {
      final player = await FlameAudio.play(file, volume: volume);
      // setPlaybackRate is a best-effort — audioplayers raises on
      // platforms without rate support, which is fine: pitch is a
      // nice-to-have, not a correctness requirement.
      if (rate != 1.0) {
        try {
          await player.setPlaybackRate(rate);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[FlameAudioService] setPlaybackRate($file) skipped: $e');
          }
        }
      }
    } catch (e) {
      // Asset missing / platform plugin missing / channel error —
      // swallow so the game doesn't crash on a fresh checkout.
      if (kDebugMode) {
        debugPrint('[FlameAudioService] playSfxFile($file) skipped: $e');
      }
    }
  }

  @override
  Future<void> playMusicFile(String file, double volume) async {
    try {
      await FlameAudio.bgm.play(file, volume: volume);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FlameAudioService] playMusicFile($file) skipped: $e');
      }
    }
  }

  @override
  Future<void> stopMusicFile() async {
    try {
      await FlameAudio.bgm.stop();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FlameAudioService] stopMusicFile skipped: $e');
      }
    }
  }

  @override
  Future<void> setMusicVolumeOnPlayer(double volume) async {
    try {
      await FlameAudio.bgm.audioPlayer.setVolume(volume);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FlameAudioService] setMusicVolumeOnPlayer skipped: $e');
      }
    }
  }
}
