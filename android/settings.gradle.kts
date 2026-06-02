// Modern Flutter Android settings file.
//
// The Flutter Gradle Plugin (`dev.flutter.flutter-gradle-plugin`) is NOT
// published to a normal plugin repository. It is provided by the Flutter SDK
// itself through the "flutter plugin loader", which has to be wired up here in
// `pluginManagement`. Without this block Gradle cannot find the plugin and the
// build fails with:
//
//   Plugin [id: 'dev.flutter.flutter-gradle-plugin'] was not found ...
//
// That missing wiring was the root cause of the reported build failure.
pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    // Makes the Flutter Gradle Plugin available to the app module.
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // Mirrors kept from the original project for faster downloads in CN.
        maven("https://maven.aliyun.com/repository/public")
        maven("https://mirrors.huaweicloud.com/repository/maven")
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Plugin versions are declared once here and applied (without a version) in
    // the module build files. This matches the Flutter 3.x Kotlin DSL template.
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
}

include(":app")
