# vpn_app

A Flutter WebRTC VPN client with an Android `VpnService` backend.

## Getting Started

```bash
flutter pub get
flutter run
```

## Build fix

This repository previously failed to build with:

```
* What went wrong:
Plugin [id: 'dev.flutter.flutter-gradle-plugin'] was not found in any of the following sources:
- Gradle Core Plugins (plugin is not in 'org.gradle' namespace)
- Plugin Repositories (plugin dependency must include a version number for this source)
```

### Root cause

The app module (`android/app/build.gradle.kts`) applies the Flutter Gradle
Plugin through the declarative `plugins {}` DSL:

```kotlin
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}
```

`dev.flutter.flutter-gradle-plugin` is not published to any plugin repository —
it ships inside the Flutter SDK and must be made available through the
**Flutter plugin loader** in `android/settings.gradle.kts`. The original
`settings.gradle.kts` only contained `include(":app")`, so Gradle had nowhere
to resolve the plugin from, producing the error above.

### What changed

- `android/settings.gradle.kts` — added the `pluginManagement` block that
  `includeBuild`s `flutter_tools/gradle` plus the `dev.flutter.flutter-plugin-loader`
  and module plugin versions (`com.android.application`, `org.jetbrains.kotlin.android`).
- `android/build.gradle.kts` — removed the legacy `buildscript { classpath(...) }`
  block, which conflicted with the modern plugins DSL.
- `android/app/build.gradle.kts` — applied the Kotlin Android plugin (the app is
  written in Kotlin) and added `kotlinOptions { jvmTarget = "17" }`.
- `android/app/src/main/AndroidManifest.xml` — removed the deprecated `package`
  attribute (AGP 8 requires `namespace` in Gradle instead).
- `test/widget_test.dart` — replaced the leftover counter template test (which
  could never pass) with a test of the real home screen.
