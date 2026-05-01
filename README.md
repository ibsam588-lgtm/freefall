# Freefall

An infinite falling arcade game built with Flutter and
[Flame](https://flame-engine.org/). You're a glowing orb plummeting
through procedurally-shifted hazards across five visually distinct
zones. Tilt the device (or tap left/right zones) to dodge. The
deeper you fall, the faster the camera scrolls.

> _Screenshots placeholder_ — drop captures of each zone here once
> the v1.0.0 build is on a physical device.

## Status

**v1.0.0 — release-ready.** All 16 build phases shipped; 372 unit
+ widget tests pass; static analysis clean; signed-AAB CI/CD
pipeline wired up. Pending external assets (real audio files +
google-services.json) before submitting to Play Store —
[`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) tracks the gates.

## Architecture

Sixteen ordered phases, each landing as a self-contained commit on
`main`:

| Phase | Surface | Key files |
| ----- | ------- | --------- |
| 1     | Project setup + core engine — fixed-step `GameLoop`, `GravitySystem`, `CameraSystem`, `CollisionSystem`, `ObjectPool<T>`, base `Player` | [lib/systems/](lib/systems/) |
| 2     | Zone system — 5 zones × 1000m, parallax backgrounds, difficulty scaling, zone transitions | [lib/models/zone.dart](lib/models/zone.dart), [lib/components/zone_background.dart](lib/components/zone_background.dart), [lib/systems/zone_manager.dart](lib/systems/zone_manager.dart), [lib/systems/difficulty_scaler.dart](lib/systems/difficulty_scaler.dart) |
| 3     | 12 obstacle / hazard types + procedural spawner | [lib/components/obstacles/](lib/components/obstacles/), [lib/components/hazards/](lib/components/hazards/), [lib/systems/obstacle_spawner.dart](lib/systems/obstacle_spawner.dart) |
| 4     | Player system — 9 skins, 7 trails, death/respawn particles, zone color sync, shield visual | [lib/components/player.dart](lib/components/player.dart), [lib/components/player_trail.dart](lib/components/player_trail.dart), [lib/components/particle_system.dart](lib/components/particle_system.dart), [lib/models/player_skin.dart](lib/models/player_skin.dart) |
| 5     | Collectibles & powerups — 4 coin types, 3 gem types, 6 powerups, magnet, persistent coin balance | [lib/systems/collectible_manager.dart](lib/systems/collectible_manager.dart), [lib/systems/powerup_manager.dart](lib/systems/powerup_manager.dart), [lib/repositories/coin_repository.dart](lib/repositories/coin_repository.dart) |
| 6     | Scoring & combo system | [lib/systems/score_manager.dart](lib/systems/score_manager.dart), [lib/components/near_miss_detector.dart](lib/components/near_miss_detector.dart) |
| 7     | Coin economy — daily login, ad rewards, settings, main menu | [lib/repositories/daily_login_repository.dart](lib/repositories/daily_login_repository.dart), [lib/repositories/ad_reward_repository.dart](lib/repositories/ad_reward_repository.dart), [lib/services/settings_service.dart](lib/services/settings_service.dart), [lib/screens/main_menu_screen.dart](lib/screens/main_menu_screen.dart) |
| 8     | Store — cosmetics, upgrades, purchase/equip, animated UI | [lib/repositories/store_repository.dart](lib/repositories/store_repository.dart), [lib/store/store_inventory.dart](lib/store/store_inventory.dart), [lib/screens/store_screen.dart](lib/screens/store_screen.dart) |
| 9     | Menus & HUD — pause, stats, leaderboard stub, full HUD wiring | [lib/components/hud.dart](lib/components/hud.dart), [lib/screens/](lib/screens/) |
| 10    | Achievements & progression — 20 achievements, ghost runner, Play Games stub | [lib/systems/achievement_manager.dart](lib/systems/achievement_manager.dart), [lib/systems/ghost_runner.dart](lib/systems/ghost_runner.dart), [lib/screens/achievements_screen.dart](lib/screens/achievements_screen.dart) |
| 11    | Audio — zone music, 20 SFX, null-audio fallback, settings integration | [lib/services/audio_service.dart](lib/services/audio_service.dart), [lib/services/audio_service_impl.dart](lib/services/audio_service_impl.dart) |
| 12    | Monetization — AdMob rewarded/interstitial, 6 IAP products, coin packs UI, no-ads | [lib/services/admob_service.dart](lib/services/admob_service.dart), [lib/services/iap_service.dart](lib/services/iap_service.dart), [lib/models/iap_product.dart](lib/models/iap_product.dart) |
| 13    | Social — Google Play Games leaderboards, achievements sync, share-score image | [lib/services/google_play_games_service.dart](lib/services/google_play_games_service.dart), [lib/services/share_service.dart](lib/services/share_service.dart) |
| 14    | Performance & technical — Firebase analytics/crashlytics, adaptive particles, pool stats, frame monitor | [lib/services/firebase_service.dart](lib/services/firebase_service.dart), [lib/services/analytics_service.dart](lib/services/analytics_service.dart), [lib/systems/performance_monitor.dart](lib/systems/performance_monitor.dart) |
| 15    | Testing & QA — edge-case tests, widget tests, integration test stubs | [test/](test/), [test/widget/](test/widget/), [integration_test/](integration_test/) |
| 16    | Release prep — CI/CD release pipeline, signing config, ProGuard, release checklist, README | [.github/workflows/release.yml](.github/workflows/release.yml), [android/app/build.gradle](android/app/build.gradle), [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) |

## File structure

```
freefall/
├── lib/
│   ├── app/                # AppDependencies + named-route table
│   ├── components/         # Flame components (player, hazards, hud, …)
│   ├── game/               # FreefallGame root, GameLoop wiring
│   ├── models/             # Pure-data types (skins, zones, run stats, …)
│   ├── repositories/       # Persistent stores (coins, store, stats, …)
│   ├── screens/            # Flutter screens (menu, store, summary, …)
│   ├── services/           # Platform facades (audio, ads, IAP, Firebase, …)
│   ├── store/              # Store catalog + ID encoding
│   ├── systems/            # Pure-Dart game systems (zone, score, achievements, …)
│   └── main.dart           # App entry — Firebase init + dependency wiring
├── test/                   # Unit + widget tests (372 total)
├── integration_test/       # Device-attached integration test stubs
├── assets/audio/           # SFX + music (manifest in README — files added per release)
├── android/                # Native Android build + ProGuard rules
├── .github/workflows/      # CI (every push) + release (on `v*` tag)
├── distribution/whatsnew/  # Per-locale store changelog
└── RELEASE_CHECKLIST.md    # Pre-release gates
```

## Setup requirements

- **Flutter 3.27+** (Dart 3.6). Earlier versions may compile but
  CI is pinned to stable.
- **Android Studio / Android SDK** with API 21–34 installed for
  device testing.
- **JDK 17** (matches CI; required for AGP 8.x).
- **Firebase project** (optional for `flutter run`; required for
  Analytics + Crashlytics in production). Drop
  `android/app/google-services.json` per
  [`android/SETUP.md`](android/SETUP.md).
- **AdMob account** (optional for development — the test ad-unit
  ids in [`admob_service.dart`](lib/services/admob_service.dart)
  serve real test ads).
- **Audio assets** — see
  [`assets/audio/README.md`](assets/audio/README.md). The game
  runs silently when files are missing (defensive fallback).

## Running

```bash
flutter pub get
flutter run -d <device-id>
```

The game ships with safe defaults for every external service —
missing google-services.json, missing audio files, no Play Games
sign-in all degrade to local-only behavior without crashing.

## Tests

```bash
flutter analyze
flutter test
flutter test --coverage    # writes coverage/lcov.info (gitignored)
```

372 tests across the unit + widget suite. The
[`integration_test/`](integration_test/) stubs run on a real device
or emulator only — they document end-to-end flows for a future
device-attached CI runner.

## CI / CD

- **Every push to `main` and every PR**:
  [`.github/workflows/flutter_ci.yml`](.github/workflows/flutter_ci.yml)
  runs analyze + tests + builds debug + release APK + AAB. The AAB
  is uploaded as an artifact for ad-hoc download.
- **Tag `v*` push**:
  [`.github/workflows/release.yml`](.github/workflows/release.yml)
  decodes the upload keystore from secrets, builds a signed AAB,
  and uploads it to the Play Console's **Internal Testing** track.
  Promotion through closed/open/production is a manual step in
  Play Console — see [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md).

## Release checklist

See [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) for the per-
release gates: versioning bumps, store-listing prep, QA pass, and
the staged-rollout playbook.

## License

Proprietary. © 2026 Corsair Labs.
