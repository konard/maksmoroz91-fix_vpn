plugins {
    id("com.android.application")
    // The app is written in Kotlin (MainActivity.kt, AppVpnService.kt, ...), so the
    // Kotlin Android plugin must be applied. It was missing in the original
    // project, which would fail the build right after the Flutter plugin issue
    // was resolved.
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin
    // Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.vpn_app"
    compileSdk = 34

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.vpn_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    packaging {
        jniLibs {
            // Optional gomobile AARs such as libbox.aar and olcrtc.aar ship
            // JNI libraries; extract them consistently for device builds.
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Optional gomobile AARs. Keep this as fileTree so CI still builds when
    // android/app/libs/libbox.aar or olcrtc.aar is not committed to the repo.
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar", "*.jar"))))
}

flutter {
    source = "../.."
}
