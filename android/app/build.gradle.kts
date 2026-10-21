import java.io.FileInputStream
import java.util.Properties

// 明示したローカル検証だけ別アプリにする。通常の配布ビルドは従来のIDを維持する。
val isCalendarTest = providers.gradleProperty("pancyoCalendarTest")
    .map { it.toBooleanStrict() }.getOrElse(false)
val isReworkTest = isCalendarTest || providers.gradleProperty("pancyoReworkTest")
    .map { it.toBooleanStrict() }.getOrElse(false)
if (isReworkTest && gradle.startParameter.taskNames.any {
        it.contains("release", ignoreCase = true) || it.contains("bundle", ignoreCase = true)
    }) {
    throw GradleException("改修テスト版はローカルProfile APK専用です。Release/AABは作成しません。")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (!isReworkTest && keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.pancyo.aiastrology"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = if (isCalendarTest) "com.pancyo.aiastrology.calendarqa" else if (isReworkTest) "com.pancyo.aiastrology.rework" else "com.pancyo.aiastrology"
        manifestPlaceholders["pancyoAppLabel"] =
            if (isCalendarTest) "星カレンダー確認版" else if (isReworkTest) "ぱんちょ式星占い（研究版）" else "ぱんちょ式星占い"
        manifestPlaceholders["pancyoTestOnly"] = isReworkTest.toString()
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName + if (isCalendarTest) "-reading-r17" else if (isReworkTest) "-rework" else ""
    }

    signingConfigs {
        if (!isReworkTest && keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Intentionally unsigned until a private release keystore is configured.
            // A store build must never fall back to the shared Android debug key.
            if (!isReworkTest && keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        getByName("profile") {
            if (isReworkTest) {
                // 正式配布用の鍵を使わず、別パッケージだけにローカル検証署名を使う。
                signingConfig = signingConfigs.getByName("debug")
            } else if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

