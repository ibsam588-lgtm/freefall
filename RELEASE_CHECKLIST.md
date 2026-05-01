# Release checklist

Run through this list before every Play Store release. Items marked
**(once)** only need to be done the first time we ship to a track;
everything else is per-release.

## Versioning

- [ ] Bump `versionCode` (always +1) and `versionName` in
      [`android/app/build.gradle`](android/app/build.gradle).
- [ ] Update `version:` in [`pubspec.yaml`](pubspec.yaml).
- [ ] Update [`distribution/whatsnew/en-US/default.txt`](distribution/whatsnew/en-US/default.txt)
      with the user-facing changelog for this build.

## Provisioning (replace placeholders with production values)

- [ ] **(once)** Drop `android/app/google-services.json` from the
      Firebase Console. See
      [`android/SETUP.md`](android/SETUP.md).
- [ ] **(once)** Drop `ios/Runner/GoogleService-Info.plist` from the
      same Firebase project for the iOS build.
- [ ] **(once)** Generate the upload keystore (`keytool -genkey -v -keystore keystore.jks -alias freefall ...`),
      base64 it, and paste into the `KEYSTORE_BASE64` GitHub secret.
- [ ] **(once)** Add `KEYSTORE_PASS`, `KEY_ALIAS`, `KEY_PASS`,
      and `PLAY_SERVICE_ACCOUNT_JSON` to GitHub secrets.
- [ ] Replace AdMob test ad-unit ids in
      [`lib/services/admob_service.dart`](lib/services/admob_service.dart)
      with the real ids from the AdMob console.
- [ ] Replace placeholder Play Games leaderboard ids in
      [`lib/services/google_play_games_stub.dart`](lib/services/google_play_games_stub.dart)
      (`bestScoreLeaderboardId` / `bestDepthLeaderboardId`) with the
      real `CgkI...` ids issued by Play Console.
- [ ] Replace placeholder Play Games achievement ids in
      [`lib/systems/achievement_manager.dart`](lib/systems/achievement_manager.dart)
      (the `_pgPrefix` constant) with the real ids per row.
- [ ] Drop the real audio files into
      [`assets/audio/`](assets/audio/) — manifest in
      [`assets/audio/README.md`](assets/audio/README.md).

## QA (every release)

- [ ] `flutter analyze` — zero issues.
- [ ] `flutter test` — every test passes (currently 372).
- [ ] `flutter test --coverage` — review the lcov report; no
      previously-covered file regressed to 0%.
- [ ] Build + sideload on a physical Android device. Smoke-test:
  - [ ] Daily-login overlay appears on first launch.
  - [ ] Tilt control feels responsive (settings → Tilt sensitivity).
  - [ ] At least one obstacle of every type is hit during a 30s run.
  - [ ] Coin pickup audio plays (post-asset-drop).
  - [ ] Achievement popup fires (e.g. fall-10km after enough runs,
        or zone-no-hit on a clean dive).
  - [ ] Run summary shows correct stats + the share button generates
        a sensible PNG.
  - [ ] Store: skin purchase flow works in-app currency; coin pack
        IAP triggers the platform purchase dialog.

## Store listing

- [ ] **(once)** Create the Play Console app entry under package id
      `com.corsairlabs.freefall`.
- [ ] **(once)** Take 5 portrait phone screenshots of in-game
      moments (one per zone is ideal). 16:9 1080×1920 recommended.
- [ ] **(once)** Create the feature graphic (1024×500 px PNG/JPG)
      for the Play Store header.
- [ ] **(once)** Write the long description, short description, and
      full title in Play Console.
- [ ] Complete the content rating questionnaire in Play Console.
- [ ] Complete the data safety form:
      - location: no
      - personal info: no
      - device or other identifiers: yes (AdMob advertising id)
      - app activity: yes (Firebase Analytics)
      - crash logs: yes (Crashlytics)
- [ ] Confirm Privacy Policy URL is reachable.

## Release stages

Promote one track at a time. Roll back fast if Crashlytics shows a
spike on the new build.

1. [ ] Tag `vX.Y.Z` and push — the
       [release workflow](.github/workflows/release.yml) builds + uploads
       the AAB to **Internal Testing**.
2. [ ] Walk through the QA list above on the Internal track build.
3. [ ] Promote to **Closed Testing** in Play Console. Wait 24h for
       any crash spike to surface.
4. [ ] Promote to **Open Testing**. Wait 48h.
5. [ ] Promote to **Production** with a **staged rollout** (start at
       10%; ramp to 100% over 5 days unless a regression appears).

## Post-release

- [ ] Watch the Crashlytics dashboard for any new fatal events.
- [ ] Watch the Firebase Analytics → Realtime tab to confirm
      `run_completed` lands within 30s of an actual run.
- [ ] Watch the Play Console pre-launch report for any device-specific
      compatibility issues.
- [ ] If a hotfix is needed, branch off the `vX.Y.Z` tag, fix, ship
      `vX.Y.Z+1` through the same pipeline.
