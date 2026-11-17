import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "top.yiqikan.app"
    // 原包用 compileSdk 36，但 permission_handler_android 14.1.1 的 AAR 元数据要求
    // 消费方 compileSdk >= 37，否则 :app:checkDebugAarMetadata 直接失败；本机已装 Platform 37.0。
    // targetSdk 仍保持 36（运行时行为与原包一致），只提高编译期 SDK。
    compileSdk = 37
    // 原包 NDK 27.0.12077973，但当前 Flutter 3.44.6 生态的插件（fvp / flutter_webrtc / media_kit 等）
    // 全部要求 NDK 28.2.13676358（NDK 向后兼容），本机已装，故取 28.2。
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "top.yiqikan.app"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        // 原包仅 arm64-v8a（libmpv/libass 只有该 ABI）
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    buildFeatures {
        // I-82：release 收紧调试面（/local/peer）要靠 BuildConfig.DEBUG 判断构建类型，
        // AGP 8 起 buildConfig 默认不生成，这里显式打开。
        buildConfig = true
    }

    compileOptions {
        // flutter_local_notifications 22.x 的 AAR 元数据要求开启 core library desugaring
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        // 只打 arm64，减少体积
        resources.excludes += setOf("META-INF/*.kotlin_module")
        jniLibs {
            // 安装时把 .so 真正解压到 nativeLibraryDir：Android 10+ 起 targetSdk>=29 的
            // filesDir(/data/data/<pkg>) 是 noexec，只有 nativeLibraryDir 里的文件能 exec。
            useLegacyPackaging = true
            // 阻止 AGP 的 StripDebugSymbols 改写这个 .so（字节一变就可能 exec 失败）
            keepDebugSymbols.add("**/libcloudflared.so")
        }
    }

    // release 签名：从 android/local.properties 读（该文件已被 .gitignore 排除）
    // 需要四个键：
    //   RELEASE_STORE_FILE=../keystore/yiqikan.jks   （相对 android/app/）
    //   RELEASE_STORE_PASSWORD=...
    //   RELEASE_KEY_ALIAS=yiqikan
    //   RELEASE_KEY_PASSWORD=...
    // 没有这本证书时 release 回落到 debug 签名（能装能跑，但不能上架、
    // assetlinks 的 SHA-256 会失配，扫码不会被系统直接打开）。
    val ksProps = Properties()
    val ksFile = rootProject.file("local.properties")
    if (ksFile.exists()) {
        ksFile.inputStream().use { stream -> ksProps.load(stream) }
    }
    val ksStoreFile: String? = ksProps.getProperty("RELEASE_STORE_FILE")
    val ksStorePwd: String? = ksProps.getProperty("RELEASE_STORE_PASSWORD")
    val ksAlias: String? = ksProps.getProperty("RELEASE_KEY_ALIAS")
    val ksKeyPwd: String? = ksProps.getProperty("RELEASE_KEY_PASSWORD")
    val hasReleaseKey = !ksStoreFile.isNullOrBlank()

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(ksStoreFile!!)
                storePassword = ksStorePwd
                keyAlias = ksAlias
                keyPassword = ksKeyPwd
                // 显式打开 v1/v2/v3：AGP 默认只落 v2，assetlinks/直装兼容性都靠这三档
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // 有证书才用 release 签名；没有就留空，AGP 会回落到 debug 签名
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else null
            // 本版不混淆、不压资源，先保证能跑；ProGuard 规则文件保留备用
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }
}

// AGP 9 已废弃 android.kotlinOptions，改用 KGP 的 kotlin { compilerOptions { } }
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter { source = "../.." }

dependencies {
    // core library desugaring（flutter_local_notifications 依赖的 java.time 等 API）
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // 与原包对齐（取自 APK 的 META-INF/*.version）
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.media:media:1.7.0")
    implementation("androidx.activity:activity-ktx:1.13.0")
    // TVBox（catvod）兼容层：P0b 起编 Spider/Net/OkHttp 用
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("com.squareup.okhttp3:okhttp-dnsoverhttps:4.12.0")
    implementation("com.google.guava:guava:33.3.1-android")
    implementation("com.google.code.gson:gson:2.11.0")
    implementation("org.jsoup:jsoup:1.18.1")
    // P3：QuickJS 的 java 层（FongMi 预编译件），与 jniLibs 里的 libquickjs-wrapper.so 配对
    implementation(files("libs/wrapper-java.jar"))
}
