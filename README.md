# Freefall

An infinite falling arcade game built with Flutter and [Flame](https://flame-engine.org/).

You're a glowing orb plummeting through procedurally-shifted hazards. Tilt the device (or tap left/right zones) to dodge. The deeper you fall, the faster the camera scrolls.

## Status

Phase 1 is in. The core engine is wired up and unit-tested:

- Fixed-timestep `GameLoop` (60 Hz, dt clamping, spiral-of-death guard)
- `GravitySystem` — accel + air resistance + terminal-velocity cap
- `CameraSystem` — auto-scroll that ramps with depth, hard-capped
- `CollisionSystem` — uniform spatial-grid broadphase
- `ObjectPool<T>` with pre-wired pools for Obstacle / Coin / Particle
- `Player` component — tilt + touch input, motion trail, wind streaks, lives + i-frames + death burst

Future phases will fill in the system stubs (input routing, obstacles, coins, ambient particles), zone progression, audio, ads, IAP, and Play Games.

## Running

```bash
flutter pub get
flutter run -d <device-id>
```

## Tests

```bash
flutter analyze
flutter test
```

CI runs all of the above plus `flutter build apk --release` and `flutter build appbundle --release` on every push and PR — see [`.github/workflows/flutter_ci.yml`](.github/workflows/flutter_ci.yml).
