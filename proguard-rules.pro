# eSportlyic release R8 rules
#
# This file is new — build.gradle previously had minifyEnabled false, so no
# proguard/R8 rules file was wired in at all. If you already have an existing
# android/app/proguard-rules.pro in the project with rules of your own, send
# it over so it can be merged instead of replaced with just this baseline.
#
# Everything below is intentionally targeted (specific packages/attributes),
# not a blanket "-keep class ** { *; }" — broad keep rules are exactly what
# defeats R8 shrinking/obfuscation, which is the thing being turned on here.

# ── Flutter engine ──────────────────────────────────────────────────────
# The Flutter embedding is called into from native (JNI) code that R8 can't
# see statically, so a few of its own packages need an explicit keep even
# though most of the embedding already ships consumer rules in its own AAR.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# ── Play Core (deferred components) ─────────────────────────────────────
# The Flutter engine references Play Core's split-install/split-compat
# classes for deferred component support even when the app doesn't use
# dynamic feature modules. Without this, R8 fails on missing-class errors
# for com.google.android.play.core.* during release builds.
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-dontwarn com.google.android.play.core.**

# ── Stack traces / Crashlytics deobfuscation ────────────────────────────
# Keeps enough debug metadata for the Crashlytics Gradle plugin (already
# applied in build.gradle) to symbolicate obfuscated release stack traces
# via the mapping file it uploads automatically on release builds.
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature

# ── Multidex ─────────────────────────────────────────────────────────────
-keep class androidx.multidex.** { *; }

# NOTE: Google Play Billing, Firebase (Auth/Firestore/Crashlytics/etc.),
# AndroidX Media3, and Google Play services libraries all ship their own
# consumer-rules.pro inside their AARs, which R8 applies automatically —
# they intentionally are NOT re-declared here. If a specific release build
# turns up a "missing class" or reflection-related crash after this is
# enabled, that's the point to add one narrow rule for that class, not a
# wildcard keep for its whole package.
