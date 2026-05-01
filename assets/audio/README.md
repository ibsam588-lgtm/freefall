# Audio assets

The Phase-11 audio system (`lib/services/audio_service.dart` +
`audio_service_impl.dart`) plays files out of this directory through
`flame_audio`. The directory is deliberately empty in the source
tree — production builds drop the real assets here before shipping.
While the directory is empty, `FlameAudioService` swallows every
"file not found" error in debug-mode and the game runs silently —
no code change required when the files arrive.

`AudioFiles` (in `audio_service.dart`) is the single source of truth
for filenames. If you rename anything below, also update that class.

## Zone music (looping background tracks)

| Zone           | File                       | Notes |
| -------------- | -------------------------- | ----- |
| Stratosphere   | `zone_stratosphere.mp3`    | airy synth pad, calm |
| City           | `zone_city.mp3`            | neon arpeggios |
| Underground    | `zone_underground.mp3`     | low brass, dust ambience |
| Deep Ocean     | `zone_ocean.mp3`           | submerged drone, sonar pings |
| Core           | `zone_core.mp3`            | distorted bass, rumble |

`playZoneMusic(zone)` switches via `FlameAudio.bgm.play()`. Same-zone
calls dedup, so pausing/resuming doesn't restart the loop.

## Coin pickup SFX (one per tier)

Pitch-shifted at runtime: bronze 1.0×, silver 1.1×, gold 1.2×,
diamond 1.5×.

| File                  |
| --------------------- |
| `coin_bronze.mp3`     |
| `coin_silver.mp3`     |
| `coin_gold.mp3`       |
| `coin_diamond.mp3`    |

## Other SFX

| Event                     | File                       |
| ------------------------- | -------------------------- |
| Gem pickup (any tier)     | `gem_collect.mp3`          |
| Powerup pickup (any kind) | `powerup_pickup.mp3`       |
| Player damage             | `hit_impact.mp3`           |
| Near-miss                 | `near_miss.mp3`            |
| Death                     | `death_shatter.mp3`        |
| Respawn                   | `respawn.mp3`              |
| Zone change accent        | `zone_transition.mp3`      |
| Speed gate                | `speed_gate.mp3`           |
| New high score            | `high_score_fanfare.mp3`   |
| UI button tap             | `ui_tap.mp3`               |
| Store purchase            | `store_purchase.mp3`       |
| Wind during fall          | `whoosh.mp3`               |

`whoosh.mp3` is pitch-shifted on playback by `playWhoosh(speedFactor)`
where `speedFactor` is mapped from camera speed into [0.5, 2.0].

## Format expectations

* Container: `.mp3` (so audioplayers' low-latency mode works on every
  target platform).
* Sample rate: 44.1 kHz, stereo.
* Music tracks should loop seamlessly — flame_audio's `bgm` uses the
  underlying `audioplayers` ReleaseMode.loop on `play`, which on
  Android stitches end → start each iteration.
