# Phase-16 release ProGuard / R8 rules.
#
# `minifyEnabled = true` in build.gradle activates R8, which strips
# unused classes + obfuscates the rest. The package list below tells
# R8 to keep classes the platform plugins reach via reflection (where
# the bytecode-level call graph doesn't see them) — without these
# rules a release build silently produces a Play-Store-rejected APK
# whose plugin channels return null on every call.
#
# Order: each block is one third-party plugin, with the relevant
# Android docs link in the comment. Re-check these rules after every
# major bump of the corresponding package.

# ---------------------------------------------------------------------
# Flutter — the framework's own rules ship via the Flutter Gradle
# plugin, but we keep our entry-point + main-thread classes explicitly
# so reflection-based crash reporting doesn't lose its handle on them.
# ---------------------------------------------------------------------
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ---------------------------------------------------------------------
# Flame engine — uses internal reflection for component lifecycle and
# for the audio plugin's resource loader.
# ---------------------------------------------------------------------
-keep class org.flame_engine.** { *; }
-dontwarn org.flame_engine.**

# ---------------------------------------------------------------------
# Firebase Core / Analytics / Crashlytics
# https://firebase.google.com/docs/crashlytics/get-deobfuscated-reports?platform=android
# Keep the Crashlytics mapping classes so symbolicated stacks land on
# the dashboard. Analytics reads field names via reflection.
# ---------------------------------------------------------------------
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-keepattributes SourceFile,LineNumberTable

# ---------------------------------------------------------------------
# Google Mobile Ads (AdMob)
# https://developers.google.com/admob/android/quick-start#proguard
# ---------------------------------------------------------------------
-keep public class com.google.android.gms.ads.** { public *; }
-keep public class com.google.ads.** { public *; }
-dontwarn com.google.android.gms.ads.**

# ---------------------------------------------------------------------
# In-app purchase (Google Play Billing)
# https://developer.android.com/google/play/billing/integrate#proguard
# ---------------------------------------------------------------------
-keep class com.android.billingclient.api.** { *; }
-keep class com.android.vending.billing.** { *; }
-dontwarn com.android.billingclient.**

# ---------------------------------------------------------------------
# Play Games Services
# Kept for the games_services Flutter plugin's reflection paths.
# ---------------------------------------------------------------------
-keep class com.google.android.gms.games.** { *; }
-dontwarn com.google.android.gms.games.**

# ---------------------------------------------------------------------
# Sensors plus / share plus / path provider — small reflection
# surfaces. Easier to keep wholesale than narrow per-class.
# ---------------------------------------------------------------------
-keep class dev.fluttercommunity.plus.** { *; }
-dontwarn dev.fluttercommunity.plus.**

# ---------------------------------------------------------------------
# Kotlin coroutines + serialization runtimes used by several plugins.
# ---------------------------------------------------------------------
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
-keep class kotlinx.serialization.** { *; }
-dontwarn kotlinx.serialization.**

# ---------------------------------------------------------------------
# AndroidX core — generally safe under R8, but a few annotation-only
# classes get aggressively pruned. Keep what's documented.
# ---------------------------------------------------------------------
-keep class androidx.lifecycle.DefaultLifecycleObserver { *; }
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
