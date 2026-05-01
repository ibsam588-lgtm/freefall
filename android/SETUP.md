# Android Firebase setup

The Firebase Analytics + Crashlytics integration shipped in Phase 14
is opt-in: the app boots cleanly **without** Firebase config files
(see `lib/services/firebase_service.dart` — the bootstrap returns the
no-op `AnalyticsService` / `CrashlyticsService` when `Firebase.initializeApp`
fails). To enable real telemetry on Android:

1. **Create a Firebase project** in the
   [Firebase Console](https://console.firebase.google.com/) and
   register the Android app. Use `com.example.freefall` (or whatever
   you've set as `applicationId` in `android/app/build.gradle`).

2. **Download `google-services.json`** from the project settings page.

3. **Drop the file at `android/app/google-services.json`.** The
   gradle plugin picks it up at build time.

4. **Add the Google Services Gradle plugin** to
   `android/app/build.gradle`:

   ```groovy
   apply plugin: 'com.google.gms.google-services'
   apply plugin: 'com.google.firebase.crashlytics'
   ```

   And to `android/build.gradle`'s `buildscript.dependencies`:

   ```groovy
   classpath 'com.google.gms:google-services:4.4.2'
   classpath 'com.google.firebase:firebase-crashlytics-gradle:3.0.2'
   ```

5. **Verify** with `flutter run` and check the Firebase Console's
   Analytics → Realtime tab. The `run_completed` event should land
   within ~30s of finishing a run.

## What's gitignored

`google-services.json` contains your project's API key — keep it out
of the repo. Add this line to `.gitignore` if it's not already there:

```
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
```

## iOS

The iOS counterpart is `ios/Runner/GoogleService-Info.plist` — same
Firebase Console download, different platform pane. Drop it at the
listed path and the `firebase_core` plugin's CocoaPods integration
handles the rest.

## Confirming the no-op fallback

If the file is missing, you should see this line in the debug log on
launch:

```
[FirebaseService] initializeApp skipped: <error>
```

That's expected — telemetry quietly degrades to the null backend
and the rest of the app keeps working.
