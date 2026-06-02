// Root project build file.
//
// Note: the legacy `buildscript { classpath(...) }` block was removed. With the
// modern plugins DSL (see settings.gradle.kts) plugin versions are resolved
// through `pluginManagement`, so declaring them here as well caused a conflict.
allprojects {
    repositories {
        // Mirrors kept from the original project for faster downloads in CN.
        maven("https://maven.aliyun.com/repository/public")
        maven("https://mirrors.huaweicloud.com/repository/maven")
        google()
        mavenCentral()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
