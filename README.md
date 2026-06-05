# vpn_app

A Flutter WebRTC VPN client with an Android `VpnService` backend.

## olcRTC/VLESS bridge configuration

The home screen accepts:

- an olcRTC room URL or ID, for example
  `https://telemost.yandex.ru/j/......` or a Jitsi room URL;
- the olcRTC carrier and transport, defaulting to `telemost` and
  `datachannel`;
- a 64 character olcRTC encryption key;
- a `vless://...` endpoint with `security=reality`.

The Flutter layer validates and normalizes these values, starts olcRTC through
`olcrtc_channel`, waits for the native bridge to report SOCKS readiness, and
only then starts the Android VPN through `vpn_channel.start`. Android creates
the `VpnService` TUN interface and starts sing-box through the optional
`libbox.aar` command server API. If olcRTC fails before SOCKS is ready, Flutter
does not start the Android VPN service.

## Android sing-box AAR

`SingBoxRunner` loads sing-box's gomobile AAR reflectively, so CI can compile
without committing native binaries. Device builds that start the VPN with
sing-box must include:

```text
android/app/libs/libbox.aar
```

The app accepts the package exposed by current sing-box Android builds:

```text
io.nekohasekai.libbox
```

The older draft imports `go.libbox.Libbox`, `go.libbox.BoxService`, and calls
`service.start(fd)`, but the provided AAR exposes `Libbox.setup(SetupOptions)`,
`CommandServer`, `PlatformInterface`, and `startOrReloadService(...)`. The app
uses that API through reflection and duplicates the already established Android
TUN descriptor from `PlatformInterface.openTun`.

## Android olcRTC AAR

Dart clients that call `olcrtc_channel` are handled by `OlcrtcPlugin` on
Android. The plugin loads the gomobile AAR reflectively so CI can still build
without committing native binaries, but device builds that start olcRTC must
include:

```text
android/app/libs/olcrtc.aar
```

If the AAR is missing, `start` reports an `olcrtc_missing` platform error
instead of Flutter throwing `MissingPluginException` for `getDeviceId`.

When Dart starts olcRTC with `carrier=jitsi` and does not pass an explicit
`transport`, the Android bridge requests `datachannel`. The upstream mobile API
defaults to `vp8channel`, but upstream olcRTC documentation recommends
`jitsi + datachannel` as the stable starting path. Callers can still pass
`transport=vp8channel` or another supported value to override this behavior.

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

Newer Flutter SDKs also reject Android Gradle Plugin `8.5.2`:

```
Error: Your project's Android Gradle Plugin version (Android Gradle Plugin version 8.5.2) is lower than Flutter's minimum supported version of Android Gradle Plugin version 8.6.0.
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

Current Flutter SDKs also validate the Android Gradle Plugin version before the
Android build proceeds. The repository still pinned `com.android.application`
to `8.5.2`, while Flutter requires at least `8.6.0`, so the Gradle task stopped
while applying the Flutter Gradle Plugin.

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
- `android/settings.gradle.kts` — bumped `com.android.application` to `8.6.0`
  so current Flutter SDKs accept the Android build configuration.
- `test/android_gradle_config_test.dart` — added a regression test that fails if
  the Android Gradle Plugin is pinned below Flutter's supported minimum.
