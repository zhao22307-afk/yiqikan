pluginManagement {
    // 与 Flutter 3.44 模板一致：从 local.properties 读 flutter.sdk，兼容 FLUTTER_ROOT 环境变量
    val flutterSdkPath: String = run {
        val properties = java.util.Properties()
        val localPropertiesFile = file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { properties.load(it) }
        }
        properties.getProperty("flutter.sdk") ?: System.getenv("FLUTTER_ROOT") ?: ""
    }
    require(flutterSdkPath.isNotEmpty()) {
        "flutter.sdk 未在 local.properties 中配置，且 FLUTTER_ROOT 环境变量为空"
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // 阿里云镜像优先（与 ferry-bot-android 保持一致）
        maven("https://maven.aliyun.com/repository/gradle-plugin")
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.3.0" apply false
    id("org.jetbrains.kotlin.android") version "2.3.10" apply false
}

include(":app")
